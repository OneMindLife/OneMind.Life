-- =============================================================================
-- Denormalize participation_percent on rounds — fix the cross-client bar drift.
-- =============================================================================
-- Today the round-status bar percent is computed *client-side* from
-- multiple independently-arriving realtime streams (propositions,
-- round_skips, rating_skips, affirmations, grid_rankings, participants).
-- Each client builds the percent from whichever subset of events its
-- websocket has delivered so far, so two viewers can see different bar
-- values for the same logical state — sometimes diverging by 5+ seconds
-- and 25+ percentage points.
--
-- Single source of truth: store the percent on the `rounds` row,
-- maintain it via SECURITY DEFINER triggers on every table whose change
-- affects the value. The trigger UPDATE on rounds fans out via the
-- existing rounds realtime channel, so all viewers receive the same
-- authoritative value (modulo per-client websocket delivery latency,
-- which we already accept for phase changes).
--
-- Same pattern as 20260502120000 (propositions.rating_count denorm) but
-- for a different aggregate. SECURITY DEFINER from the start because
-- triggers fire from user-initiated INSERTs and the rounds UPDATE
-- policy is not granted to authenticated/anon (would silently no-op).
-- See feedback_trigger_security_definer.md.
-- =============================================================================

ALTER TABLE public.rounds
  ADD COLUMN IF NOT EXISTS participation_percent INT;

COMMENT ON COLUMN public.rounds.participation_percent IS
  'Server-computed completion of the current phase, 0-100, NULL for '
  'phases without a meaningful percent (waiting/results). Maintained by '
  'recompute_round_participation_percent + AFTER triggers on propositions, '
  'round_skips, rating_skips, affirmations, grid_rankings, and rounds '
  'phase change. Source of truth for the round-status bar; clients read '
  'this directly rather than computing from local state.';

-- =============================================================================
-- Recompute helper. Idempotent: callable from any trigger.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.recompute_round_participation_percent(p_round_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_phase           TEXT;
  v_chat_id         BIGINT;
  v_total           INT;
  v_done            INT;
  v_skip_count      INT;
  v_active_raters   INT;
  v_threshold       INT;
  v_min_ratings     INT;
  v_percent         INT;
BEGIN
  SELECT r.phase, cy.chat_id INTO v_phase, v_chat_id
  FROM public.rounds r
  JOIN public.cycles cy ON cy.id = r.cycle_id
  WHERE r.id = p_round_id;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.participants
  WHERE chat_id = v_chat_id AND status = 'active';

  IF v_phase = 'proposing' THEN
    -- Done = unique participants who acted: proposed (new only),
    -- skipped propose, or affirmed.
    SELECT COUNT(DISTINCT pid) INTO v_done FROM (
      SELECT participant_id AS pid FROM public.propositions
        WHERE round_id = p_round_id
          AND carried_from_id IS NULL
          AND participant_id IS NOT NULL
      UNION
      SELECT participant_id FROM public.round_skips WHERE round_id = p_round_id
      UNION
      SELECT participant_id FROM public.affirmations WHERE round_id = p_round_id
    ) acted;

    v_percent := CASE WHEN v_total = 0 THEN 0
                      ELSE LEAST(100, (v_done * 100 / v_total)) END;

  ELSIF v_phase = 'rating' THEN
    -- Mirror lib/providers/notifiers/chat_detail_notifier.dart's
    -- ratingProgressPercent: min(per-prop rating count) / threshold,
    -- where threshold = clamp(active_raters - 1, 1, 10).
    SELECT COUNT(*) INTO v_skip_count
    FROM public.rating_skips rs
    JOIN public.participants p ON p.id = rs.participant_id
    WHERE rs.round_id = p_round_id AND p.status = 'active';

    v_active_raters := v_total - v_skip_count;
    IF v_active_raters <= 0 THEN
      v_percent := 100;
    ELSE
      v_threshold := LEAST(10, GREATEST(v_active_raters - 1, 1));
      SELECT COALESCE(MIN(p.rating_count), 0) INTO v_min_ratings
      FROM public.propositions p
      WHERE p.round_id = p_round_id;
      v_percent := LEAST(100, (v_min_ratings * 100 / v_threshold));
    END IF;

  ELSE
    v_percent := NULL;
  END IF;

  UPDATE public.rounds
  SET participation_percent = v_percent
  WHERE id = p_round_id
    AND participation_percent IS DISTINCT FROM v_percent;
END;
$$;

-- =============================================================================
-- Triggers — one per source table. All call the recompute helper.
-- Each trigger is SECURITY DEFINER (it just calls the helper, which is
-- DEFINER), so trigger DML on rounds bypasses the missing UPDATE policy.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.refresh_round_participation_from_proposition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.recompute_round_participation_percent(
    COALESCE(NEW.round_id, OLD.round_id));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS sync_round_participation_proposition ON public.propositions;
CREATE TRIGGER sync_round_participation_proposition
AFTER INSERT OR DELETE ON public.propositions
FOR EACH ROW EXECUTE FUNCTION public.refresh_round_participation_from_proposition();

-- The L1 trigger updates propositions.rating_count on grid_rankings
-- INSERT/DELETE; an AFTER UPDATE trigger on propositions.rating_count
-- catches that change without us having to also subscribe to grid_rankings.
DROP TRIGGER IF EXISTS sync_round_participation_proposition_rating_count
  ON public.propositions;
CREATE TRIGGER sync_round_participation_proposition_rating_count
AFTER UPDATE OF rating_count ON public.propositions
FOR EACH ROW
WHEN (NEW.rating_count IS DISTINCT FROM OLD.rating_count)
EXECUTE FUNCTION public.refresh_round_participation_from_proposition();

CREATE OR REPLACE FUNCTION public.refresh_round_participation_from_round_skip()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.recompute_round_participation_percent(
    COALESCE(NEW.round_id, OLD.round_id));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS sync_round_participation_round_skip ON public.round_skips;
CREATE TRIGGER sync_round_participation_round_skip
AFTER INSERT OR DELETE ON public.round_skips
FOR EACH ROW EXECUTE FUNCTION public.refresh_round_participation_from_round_skip();

CREATE OR REPLACE FUNCTION public.refresh_round_participation_from_rating_skip()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.recompute_round_participation_percent(
    COALESCE(NEW.round_id, OLD.round_id));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS sync_round_participation_rating_skip ON public.rating_skips;
CREATE TRIGGER sync_round_participation_rating_skip
AFTER INSERT OR DELETE ON public.rating_skips
FOR EACH ROW EXECUTE FUNCTION public.refresh_round_participation_from_rating_skip();

CREATE OR REPLACE FUNCTION public.refresh_round_participation_from_affirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.recompute_round_participation_percent(
    COALESCE(NEW.round_id, OLD.round_id));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS sync_round_participation_affirmation ON public.affirmations;
CREATE TRIGGER sync_round_participation_affirmation
AFTER INSERT OR DELETE ON public.affirmations
FOR EACH ROW EXECUTE FUNCTION public.refresh_round_participation_from_affirmation();

-- Phase change triggers a recompute (formula differs between proposing
-- and rating). Fires AFTER UPDATE OF phase to avoid recursion when the
-- helper itself UPDATEs participation_percent.
CREATE OR REPLACE FUNCTION public.refresh_round_participation_on_phase_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.recompute_round_participation_percent(NEW.id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS sync_round_participation_phase_change ON public.rounds;
CREATE TRIGGER sync_round_participation_phase_change
AFTER UPDATE OF phase ON public.rounds
FOR EACH ROW
WHEN (NEW.phase IS DISTINCT FROM OLD.phase)
EXECUTE FUNCTION public.refresh_round_participation_on_phase_change();

-- =============================================================================
-- Backfill: compute participation_percent for every existing round so
-- the column matches reality on rollout. Cheap; O(rounds).
-- =============================================================================
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.rounds LOOP
    PERFORM public.recompute_round_participation_percent(r.id);
  END LOOP;
END $$;
