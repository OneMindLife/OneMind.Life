-- Fix: participation_percent counted LEFT/KICKED participants as "done".
--
-- The proposing-branch `v_done` counted distinct proposers/skippers/affirmers
-- with NO status filter, while the denominator `v_total` is ACTIVE-only. So a
-- participant who proposed and then left kept counting as "done", inflating the
-- bar (e.g. 4 proposers where 1 had left, over 4 active → 100% instead of 75%).
--
-- Fix: join `participants` and require `status = 'active'` in the numerator.
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
  v_prop_count      INT;
  v_self_excl       INT;
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
    -- Done = unique ACTIVE participants who acted: proposed (new only),
    -- skipped propose, or affirmed. Active-only now — a left/kicked account's
    -- earlier proposal no longer counts.
    SELECT COUNT(DISTINCT pid) INTO v_done FROM (
      SELECT p.participant_id AS pid FROM public.propositions p
        JOIN public.participants part ON part.id = p.participant_id
        WHERE p.round_id = p_round_id
          AND p.carried_from_id IS NULL
          AND p.participant_id IS NOT NULL
          AND part.status = 'active'
      UNION
      SELECT rs.participant_id FROM public.round_skips rs
        JOIN public.participants part ON part.id = rs.participant_id
        WHERE rs.round_id = p_round_id AND part.status = 'active'
      UNION
      SELECT a.participant_id FROM public.affirmations a
        JOIN public.participants part ON part.id = a.participant_id
        WHERE a.round_id = p_round_id AND part.status = 'active'
    ) acted;

    v_percent := CASE WHEN v_total = 0 THEN 0
                      ELSE LEAST(100, (v_done * 100 / v_total)) END;

  ELSIF v_phase = 'rating' THEN
    -- Mirror lib/providers/notifiers/chat_detail_notifier.dart's
    -- ratingProgressPercent: min(per-prop rating count) / threshold,
    -- where threshold = clamp(active_raters - self_excl, 1, 10).
    -- self_excl is 0 in CSI rounds (<= 2 props: authors rate their own too),
    -- 1 otherwise — keep in sync with check_early_advance_on_rating.
    SELECT COUNT(*) INTO v_skip_count
    FROM public.rating_skips rs
    JOIN public.participants p ON p.id = rs.participant_id
    WHERE rs.round_id = p_round_id AND p.status = 'active';

    v_active_raters := v_total - v_skip_count;
    IF v_active_raters <= 0 THEN
      v_percent := 100;
    ELSE
      SELECT COUNT(*) INTO v_prop_count
      FROM public.propositions WHERE round_id = p_round_id;
      v_self_excl := CASE WHEN v_prop_count <= 2 THEN 0 ELSE 1 END;

      v_threshold := LEAST(10, GREATEST(v_active_raters - v_self_excl, 1));
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
