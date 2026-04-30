-- Remove the per-user-done Movda recalc from check_early_advance_on_rating.
--
-- Problem: every time a participant crossed their personal "done rating"
-- threshold, the trigger called calculate_movda_scores_for_round() inline,
-- inside the user's INSERT transaction. With 5 agents + 1 human all
-- crossing their thresholds within seconds of each other, proposition_movda_ratings
-- rows became heavily row-locked, queuing later transactions until they hit
-- the 8s statement_timeout. Result: the human's "5th" rating regularly
-- failed with PostgreSQL error 57014 ("canceling statement due to statement
-- timeout") — which the app surfaced as "Failed to save ratings".
--
-- Confirmed by client_logs (frontend remote logging captured the exact error
-- + 8.1s elapsed time on the failed upsert).
--
-- Fix: drop the per-user recalc. The final Movda recalc still runs at
-- round end inside complete_round_with_winner() — it's the very first
-- thing that function does — so end-of-round scores remain correct.
-- The only thing lost is the live-leaderboard refresh that happened as
-- each rater finished; those scores now update only when the round
-- completes (timer or early-advance threshold). Acceptable trade-off
-- given the failure mode it eliminates.
--
-- The early-advance check (which calls complete_round_with_winner under
-- pg_advisory_xact_lock) is preserved unchanged.

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
    v_cap CONSTANT INTEGER := 10;
    v_phase TEXT;
    v_chat_id INTEGER;
BEGIN
    -- All rows in a single statement come from one round (true on both the
    -- agent-rate batched-upsert path and the human-UI single-row path).
    SELECT round_id INTO v_round_id FROM new_ratings LIMIT 1;
    IF v_round_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Resolve round phase + chat in one shot
    SELECT r.phase, c.chat_id
      INTO v_phase, v_chat_id
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = v_round_id;

    -- Only act during the rating phase
    IF v_phase IS DISTINCT FROM 'rating' THEN
        RETURN NULL;
    END IF;

    SELECT * INTO v_chat FROM chats WHERE id = v_chat_id;

    -- ========================================================================
    -- (Removed) Per-user-done Movda recalc.
    -- The final Movda recalc runs at round end inside
    -- complete_round_with_winner(), which is invoked either by the
    -- early-advance branch below or by the process-timers cron when
    -- the rating phase ends. Computing it inline on every per-user
    -- threshold crossing was the root cause of the 8s statement_timeout
    -- failures users saw as "Failed to save ratings".
    -- ========================================================================

    -- ========================================================================
    -- Early-advance check (preserved). Runs once per statement (the trigger
    -- is FOR EACH STATEMENT after the earlier migration).
    -- ========================================================================

    -- Skip if no thresholds configured
    IF v_chat.rating_threshold_percent IS NULL
       AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NULL;
    END IF;

    -- Skip manual-start chats
    IF v_chat.start_mode = 'manual' THEN
        RETURN NULL;
    END IF;

    -- Serialize per round
    PERFORM pg_advisory_xact_lock(v_round_id);

    -- Re-check phase after acquiring lock (could have advanced)
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase IS DISTINCT FROM 'rating' THEN
        RETURN NULL;
    END IF;

    -- Active participant count (funding-aware)
    v_total_participants := public.get_funded_participant_count(v_round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NULL;
    END IF;

    -- Skipper count
    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips WHERE round_id = v_round_id;

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
        RETURN NULL;
    END IF;

    -- Threshold per proposition: every prop needs at least this many ratings
    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

    -- Minimum rating count across all props
    SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
    FROM (
        SELECT
            p.id,
            (SELECT COUNT(*)
               FROM grid_rankings gr
              WHERE gr.proposition_id = p.id
                AND gr.round_id = v_round_id) AS cnt
        FROM propositions p
        WHERE p.round_id = v_round_id
    ) prop_ratings;

    IF v_min_ratings >= v_threshold THEN
        RAISE NOTICE '[EARLY ADVANCE] Per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
            v_min_ratings, v_threshold, v_active_raters, v_skip_count, v_round_id;
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
    END IF;

    RETURN NULL;
END;
$function$;
