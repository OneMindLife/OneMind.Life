-- Convert check_early_advance_on_rating from FOR EACH ROW to FOR EACH STATEMENT,
-- and remove the per-user-done Movda recalc that was the root cause of the
-- "Failed to save ratings" timeouts users were hitting.
--
-- Two problems collapsed into one migration:
--
-- (1) Per-row trigger on a batched upsert. agent-rate writes ~5 rating rows
--     per agent in a single INSERT statement. The previous AFTER INSERT FOR
--     EACH ROW trigger fired 5 times per agent, each acquiring
--     pg_advisory_xact_lock(round_id). Concurrent agent calls queued on the
--     lock and frequently hit the 8s statement_timeout, returning DB_ERROR
--     and silently losing their ratings.
--
-- (2) Inline calculate_movda_scores_for_round() on every per-user-done
--     threshold crossing. With 5 agents + 1 human all crossing their
--     thresholds within seconds, proposition_movda_ratings became heavily
--     row-locked. Even after fix (1) the human's "5th" rating regularly
--     timed out at exactly 8.1s with PostgreSQL error 57014 — confirmed via
--     frontend remote logging that captured the exact PostgrestException.
--
-- Fix:
--   - Trigger is FOR EACH STATEMENT, exposing inserted rows via a
--     `new_ratings` transition table. One fire per upsert batch.
--   - Per-user-done Movda recalc removed entirely. The final recalc still
--     runs at round end inside complete_round_with_winner() (it's the very
--     first PERFORM in that function), so end-of-round scores remain
--     correct. Live mid-round leaderboard updates are the only thing lost.
--   - Early-advance check (advisory lock + complete_round_with_winner +
--     apply_adaptive_duration) preserved unchanged.

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
    -- Early-advance check. Runs once per statement. The advisory lock
    -- serializes per-round so only one writer at a time can attempt to
    -- complete the round.
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

-- Replace the per-row trigger with a per-statement one that exposes the
-- newly-inserted rows via the `new_ratings` transition table.
DROP TRIGGER IF EXISTS trigger_early_advance_rating ON grid_rankings;

CREATE TRIGGER trigger_early_advance_rating
AFTER INSERT ON grid_rankings
REFERENCING NEW TABLE AS new_ratings
FOR EACH STATEMENT
EXECUTE FUNCTION check_early_advance_on_rating();
