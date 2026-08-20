-- =============================================================================
-- Conditional self-inclusion (CSI): make 2-person / 2-proposition rounds ratable.
--
-- Principle: a rater NEVER rates their own proposition — unless excluding it
-- would leave them with fewer than 2 votable propositions (the binary-comparison
-- and matches UIs both need 2). With propositions_per_user = 1 this means CSI
-- activates iff the round has exactly 2 propositions; rounds with >= 3 props
-- behave exactly as before (strict superset — no behavior change for healthy
-- rounds).
--
-- Why self-votes are safe where CSI activates: if both authors self-max, the
-- self-ratings add the same constant to every proposition and the outcome is
-- decided entirely by the cross-ratings (the bias cancels). Where the bias
-- would NOT cancel (>= 3 props, asymmetric participation), CSI never activates
-- and exclusion still applies.
--
-- Changes:
--   1. get_least_rated_propositions  — self-filter becomes conditional
--   2. get_propositions_for_rating   — same, + keep AI (NULL-author) props
--      (the old `!=` comparison silently dropped them)
--   3. check_early_advance_on_rating — per-prop threshold uses
--      active_raters − 0 (not − 1) in CSI rounds. Without this, a 2-person
--      round would advance after ONE user rated both props (each prop gets 1
--      rating, threshold = max(2−1,1) = 1) — a single-voter decision.
--   4. recompute_round_participation_percent — same − 1 → − 0 so the progress
--      bar doesn't read 100% before the advance condition is met
--   5. matches_preview_maybe_finalize — "pending voter" votability uses CSI
--      (round has >= 2 props) instead of ">= rating_minimum non-own props";
--      without this a 2-person quick chat counts both users as stranded
--      (pending = 0) and finalizes after the FIRST vote instead of both.
--   6. chats_proposing_minimum_check relaxed >= 3 → >= 2, default 3 → 2. The
--      "3 guarantees every author a votable match" invariant is now provided
--      by CSI at 2 props, so 2 fresh ideas is a legitimate floor.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. get_least_rated_propositions — conditional self-exclusion
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_least_rated_propositions(
  p_round_id bigint,
  p_participant_id bigint,
  p_count integer DEFAULT 2,
  p_exclude_ids bigint[] DEFAULT '{}'::bigint[]
)
 RETURNS TABLE(id bigint, round_id bigint, participant_id bigint, content text, carried_from_id bigint, created_at timestamp with time zone, rating_count bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t0 TIMESTAMPTZ := clock_timestamp();
  v_t1 TIMESTAMPTZ;
  v_pid INT := pg_backend_pid();
  v_non_own INT;
BEGIN
  RAISE LOG 'LRP_PROBE pid=% round=% stage=enter ms=0', v_pid, p_round_id;

  -- CSI: how many props could this rater see under strict self-exclusion?
  -- If fewer than 2, include their own (the rating UIs need 2 to function).
  SELECT COUNT(*) INTO v_non_own
  FROM public.propositions p
  WHERE p.round_id = p_round_id
    AND (p.participant_id IS NULL OR p.participant_id != p_participant_id);

  RETURN QUERY
    SELECT p.id, p.round_id, p.participant_id, p.content, p.carried_from_id,
           p.created_at, p.rating_count::BIGINT
    FROM public.propositions p
    WHERE p.round_id = p_round_id
      AND (
        v_non_own < 2  -- CSI active: own props are votable too
        OR (p.participant_id IS NULL OR p.participant_id != p_participant_id)
      )
      AND NOT (p.id = ANY(p_exclude_ids))
    ORDER BY p.rating_count ASC,
             hashtext(p_participant_id::TEXT || ':' || p.id::TEXT)
    LIMIT p_count;

  v_t1 := clock_timestamp();
  RAISE LOG 'LRP_PROBE pid=% round=% stage=done ms=%',
    v_pid, p_round_id,
    (EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000)::INT;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. get_propositions_for_rating — conditional self-exclusion + keep AI props
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_propositions_for_rating(
  p_round_id bigint,
  p_participant_id bigint
)
 RETURNS TABLE(id bigint, content text, participant_id bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_non_own INT;
BEGIN
  -- Verify the caller is a participant in the chat that owns this round
  IF NOT EXISTS (
    SELECT 1
    FROM participants p
    JOIN cycles c ON c.chat_id = p.chat_id
    JOIN rounds r ON r.cycle_id = c.id
    WHERE r.id = p_round_id
      AND p.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a participant in this chat';
  END IF;

  -- NULL-author (AI) props are votable by everyone; the old `!=` comparison
  -- silently dropped them.
  SELECT COUNT(*) INTO v_non_own
  FROM propositions pr
  WHERE pr.round_id = p_round_id
    AND (pr.participant_id IS NULL OR pr.participant_id != p_participant_id);

  -- All props except the caller's own — unless that leaves fewer than 2 (CSI).
  RETURN QUERY
    SELECT pr.id, pr.content, pr.participant_id
    FROM propositions pr
    WHERE pr.round_id = p_round_id
      AND (
        v_non_own < 2
        OR (pr.participant_id IS NULL OR pr.participant_id != p_participant_id)
      );
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. check_early_advance_on_rating — CSI-aware per-prop threshold
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_early_advance_on_rating()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round_id INTEGER;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 7;
    v_phase TEXT;
    v_chat_id INTEGER;
    v_prop_count INTEGER;
    v_self_excl INTEGER;
    v_corr UUID := gen_random_uuid();
    v_trigger_start TIMESTAMPTZ := clock_timestamp();
    v_pre_lock TIMESTAMPTZ;
    v_post_lock TIMESTAMPTZ;
    v_advanced BOOLEAN := FALSE;
BEGIN
    SELECT round_id INTO v_round_id FROM new_ratings LIMIT 1;
    IF v_round_id IS NULL THEN RETURN NULL; END IF;

    SELECT r.phase, c.chat_id INTO v_phase, v_chat_id
    FROM rounds r JOIN cycles c ON c.id = r.cycle_id WHERE r.id = v_round_id;

    IF v_phase IS DISTINCT FROM 'rating' THEN RETURN NULL; END IF;

    SELECT * INTO v_chat FROM chats WHERE id = v_chat_id;

    IF v_chat.rating_threshold_percent IS NULL
       AND v_chat.rating_threshold_count IS NULL THEN RETURN NULL; END IF;

    IF v_chat.start_mode = 'manual' THEN RETURN NULL; END IF;

    -- Time the lock acquisition. If 20 triggers serialize on this lock,
    -- the late ones see a multi-second wait; this number tells us so.
    v_pre_lock := clock_timestamp();
    PERFORM pg_advisory_xact_lock(v_round_id);
    v_post_lock := clock_timestamp();

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'rating_trigger.lock_wait',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (v_post_lock - v_pre_lock)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := v_round_id
    );

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase IS DISTINCT FROM 'rating' THEN RETURN NULL; END IF;

    v_total_participants := public.get_funded_participant_count(v_round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants WHERE chat_id = v_chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN RETURN NULL; END IF;

    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips rs JOIN participants p ON p.id = rs.participant_id
    WHERE rs.round_id = v_round_id AND p.status = 'active';

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
        v_advanced := TRUE;
    ELSE
        -- The "- 1" assumes each prop's author can't rate it. In a CSI round
        -- (<= 2 props) authors DO rate their own, so every prop's audience is
        -- the full rater set. Without this, a 2-person round advances after a
        -- single user rates both props (threshold would be 1).
        SELECT COUNT(*) INTO v_prop_count
        FROM propositions WHERE round_id = v_round_id;
        v_self_excl := CASE WHEN v_prop_count <= 2 THEN 0 ELSE 1 END;

        v_threshold := LEAST(v_cap, GREATEST(v_active_raters - v_self_excl, 1));

        SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
        FROM (
            SELECT p.id,
                (SELECT COUNT(*) FROM grid_rankings gr
                 WHERE gr.proposition_id = p.id AND gr.round_id = v_round_id) AS cnt
            FROM propositions p WHERE p.round_id = v_round_id
        ) prop_ratings;

        IF v_min_ratings >= v_threshold THEN
            RAISE NOTICE '[EARLY ADVANCE] Per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
                v_min_ratings, v_threshold, v_active_raters, v_skip_count, v_round_id;
            PERFORM complete_round_with_winner(v_round_id);
            PERFORM apply_adaptive_duration(v_round_id);
            v_advanced := TRUE;
        END IF;
    END IF;

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := CASE WHEN v_advanced THEN 'rating_trigger.advanced'
                                  ELSE 'rating_trigger.bail' END,
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_trigger_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := v_round_id,
        p_payload        := jsonb_build_object(
            'min_ratings', v_min_ratings,
            'threshold', v_threshold,
            'active_raters', v_active_raters
        )
    );

    RETURN NULL;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. recompute_round_participation_percent — CSI-aware rating denominator
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 5. matches_preview_maybe_finalize — CSI-aware "pending voter" definition.
--    Rebased on the LATEST committed body (20260625120500, seat-fill aware —
--    NOT 20260624100000): the game/player done/eligible override is preserved
--    verbatim. Only the v_pending votability rule changes: under CSI a
--    participant can vote whenever the round has >= 2 props (they get their
--    own prop served when excluding it would leave them under 2), so the old
--    ">= rating_minimum non-own props" stranded-author rule collapses to
--    "round has >= 2 props at all".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.matches_preview_maybe_finalize()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_round_id    BIGINT := NEW.round_id;
  v_phase       TEXT;
  v_completed   TIMESTAMPTZ;
  v_chat_id     BIGINT;
  v_rating_mode TEXT;
  v_max_cycles  INTEGER;
  v_is_preview  BOOLEAN;
  v_agent_cnt   INTEGER;
  v_mode        TEXT;
  v_has_player  BOOLEAN;
  v_prop_count  INTEGER;
  v_done        INTEGER;
  v_eligible    INTEGER;
  v_pending     INTEGER;
  v_votes       INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, c.chat_id, ch.rating_mode, ch.max_cycles,
         ch.is_preview, ch.rating_agent_count, ch.mode
    INTO v_phase, v_completed, v_chat_id, v_rating_mode, v_max_cycles,
         v_is_preview, v_agent_cnt, v_mode
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  IF v_phase <> 'rating'
     OR v_completed IS NOT NULL
     OR v_rating_mode <> 'matches'
     OR v_max_cycles IS DISTINCT FROM 1 THEN
    RETURN NEW;
  END IF;

  -- done = distinct raters across all three completion signals.
  SELECT COUNT(*) INTO v_done FROM (
    SELECT participant_id FROM rating_completions WHERE round_id = v_round_id AND participant_id IS NOT NULL
    UNION
    SELECT gr.participant_id FROM grid_rankings gr
      JOIN propositions p ON p.id = gr.proposition_id
      WHERE p.round_id = v_round_id
    UNION
    SELECT participant_id FROM rating_skips WHERE round_id = v_round_id
  ) u;

  v_eligible := get_rating_eligible_count(v_chat_id);

  -- pending = able voters who haven't acted. Under conditional self-inclusion
  -- (20260704160000) anyone can vote when the round has >= 2 props: they see
  -- all non-own props, plus their own when excluding it would leave fewer
  -- than 2. A "stranded" voter only exists when the board itself has < 2.
  SELECT COUNT(*) INTO v_prop_count
  FROM propositions WHERE round_id = v_round_id;

  IF v_prop_count < 2 THEN
    v_pending := 0;
  ELSE
    SELECT COUNT(*) INTO v_pending
    FROM participants p
    WHERE p.chat_id = v_chat_id
      AND p.status = 'active'
      AND (p.is_agent = false OR v_agent_cnt > 0)
      AND NOT EXISTS (SELECT 1 FROM rating_completions rc WHERE rc.round_id = v_round_id AND rc.participant_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM rating_skips rs WHERE rs.round_id = v_round_id AND rs.participant_id = p.id)
      AND NOT EXISTS (
        SELECT 1 FROM grid_rankings gr
        JOIN propositions gp ON gp.id = gr.proposition_id
        WHERE gp.round_id = v_round_id AND gr.participant_id = p.id
      );
  END IF;

  -- Seat-fill override: for a game round with an active 'player' agent, take
  -- done/eligible from the player+host-aware progress fn so the round waits for
  -- the async bots AND the host (v_pending still guards stranded humans).
  SELECT EXISTS (
    SELECT 1 FROM participants p
    WHERE p.chat_id = v_chat_id AND p.is_agent = true
      AND p.status = 'active' AND p.agent_role = 'player'
  ) INTO v_has_player;

  IF v_mode = 'game' AND v_has_player THEN
    SELECT done, eligible INTO v_done, v_eligible
    FROM get_matches_rating_progress(v_round_id, v_chat_id);
  END IF;

  SELECT COUNT(*) INTO v_votes
  FROM pairwise_comparisons
  WHERE round_id = v_round_id AND COALESCE(is_skip, false) = false;

  -- Finalize when everyone's accounted for (v_done >= v_eligible) OR no ABLE
  -- voter is still pending — and, for a real multi-user round, at least one
  -- real vote was cast.
  IF v_eligible > 0
     AND (v_done >= v_eligible OR v_pending = 0)
     AND (v_is_preview IS TRUE OR v_votes >= 1) THEN
    PERFORM complete_round_with_winner(v_round_id);
  END IF;

  RETURN NEW;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. proposing_minimum: floor 3 → 2 (CSI restores the votability guarantee)
-- -----------------------------------------------------------------------------
ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_proposing_minimum_check;
ALTER TABLE public.chats ADD CONSTRAINT chats_proposing_minimum_check
  CHECK (proposing_minimum >= 2);
ALTER TABLE public.chats ALTER COLUMN proposing_minimum SET DEFAULT 2;

COMMENT ON CONSTRAINT chats_proposing_minimum_check ON public.chats IS
'Floor of 2: any 2 propositions form a votable set for every participant under
conditional self-inclusion (authors are served their own prop when excluding it
would leave them under 2). The old floor of 3 existed to guarantee authors a
non-own pair — CSI provides that guarantee at 2.';
