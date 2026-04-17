-- =============================================================================
-- MIGRATION: Recalculate MOVDA scores when a user finishes rating
-- =============================================================================
-- Previously, MOVDA scores were only calculated when the round completes.
-- This meant there were no official scores visible during the rating phase.
--
-- Now: each time a grid_ranking is inserted, we check if the inserting
-- participant just crossed the "done" threshold (min(10, non-self props)).
-- If so, we recalculate MOVDA scores for the round, giving live rankings.
--
-- This is much cheaper than the old per-insert trigger because it only
-- fires the expensive MOVDA calculation once per participant completion,
-- not on every single grid_ranking insert.
-- =============================================================================

CREATE OR REPLACE FUNCTION check_early_advance_on_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_proposition RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 10;
    -- User-done detection
    v_participant_rated_count INTEGER;
    v_total_props INTEGER;
    v_own_props INTEGER;
    v_non_self_props INTEGER;
    v_done_threshold INTEGER;
BEGIN
    -- Get proposition and round info
    SELECT p.*, r.id as round_id, r.phase, r.cycle_id, c.chat_id
    INTO v_proposition
    FROM propositions p
    JOIN rounds r ON r.id = p.round_id
    JOIN cycles c ON c.id = r.cycle_id
    WHERE p.id = NEW.proposition_id;

    -- Only check during rating phase
    IF v_proposition.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM chats
    WHERE id = v_proposition.chat_id;

    -- =========================================================================
    -- CHECK: Did the inserting participant just become "done"?
    -- If so, recalculate MOVDA scores for live ranking updates.
    -- =========================================================================
    IF NEW.participant_id IS NOT NULL THEN
        -- Count how many propositions this participant has now rated in this round
        SELECT COUNT(*) INTO v_participant_rated_count
        FROM grid_rankings
        WHERE round_id = v_proposition.round_id
          AND participant_id = NEW.participant_id;

        -- Count total propositions in this round
        SELECT COUNT(*) INTO v_total_props
        FROM propositions
        WHERE round_id = v_proposition.round_id;

        -- Count propositions authored by this participant
        SELECT COUNT(*) INTO v_own_props
        FROM propositions
        WHERE round_id = v_proposition.round_id
          AND participant_id = NEW.participant_id;

        v_non_self_props := v_total_props - v_own_props;
        v_done_threshold := LEAST(v_cap, v_non_self_props);

        -- Recalculate MOVDA exactly when user crosses the done threshold
        IF v_done_threshold > 0 AND v_participant_rated_count = v_done_threshold THEN
            RAISE NOTICE '[MOVDA] Participant % completed rating (% ratings). Recalculating scores for round %.',
                NEW.participant_id, v_participant_rated_count, v_proposition.round_id;
            PERFORM calculate_movda_scores_for_round(v_proposition.round_id);
        END IF;
    END IF;

    -- =========================================================================
    -- EXISTING: Early advance check
    -- =========================================================================

    -- Skip if no thresholds configured
    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip manual mode
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- Serialize per round (concurrency fix)
    PERFORM pg_advisory_xact_lock(v_proposition.round_id);

    -- Re-check phase after acquiring lock
    SELECT phase INTO v_proposition.phase
    FROM rounds WHERE id = v_proposition.round_id;

    IF v_proposition.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Count active participants (funding-aware)
    v_total_participants := public.get_funded_participant_count(v_proposition.round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_proposition.chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count rating skippers (they can't contribute ratings)
    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips
    WHERE round_id = v_proposition.round_id;

    -- Active raters = participants who haven't skipped
    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        -- Everyone skipped — just advance
        PERFORM complete_round_with_winner(v_proposition.round_id);
        PERFORM apply_adaptive_duration(v_proposition.round_id);
        RETURN NEW;
    END IF;

    -- Threshold: min(cap, max(active_raters - 1, 1))
    -- active_raters - 1 because a proposition's author can't rate their own
    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

    -- Find the minimum rating count across all propositions in this round
    SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
    FROM (
        SELECT
            p.id,
            (
                SELECT COUNT(*) FROM grid_rankings gr
                WHERE gr.proposition_id = p.id
                  AND gr.round_id = v_proposition.round_id
            ) AS cnt
        FROM propositions p
        WHERE p.round_id = v_proposition.round_id
    ) prop_ratings;

    -- Advance when every proposition has enough ratings
    IF v_min_ratings >= v_threshold THEN
        RAISE NOTICE '[EARLY ADVANCE] Per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
            v_min_ratings, v_threshold, v_active_raters, v_skip_count, v_proposition.round_id;

        PERFORM complete_round_with_winner(v_proposition.round_id);
        PERFORM apply_adaptive_duration(v_proposition.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
