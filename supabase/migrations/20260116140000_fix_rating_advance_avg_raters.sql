-- =============================================================================
-- MIGRATION: Fix Rating Auto-Advance to Use Average Raters Per Proposition
-- =============================================================================
-- BUG: rating_threshold_count was checking "unique participants who have rated"
-- FIX: Now checks "average number of raters per proposition"
--
-- Example with threshold=2:
--   OLD: 2 people rate anything → advance (even if each only rated 1 prop)
--   NEW: Average of 2 raters per proposition → advance only when coverage is adequate
--
-- This aligns with rating_minimum which already uses "avg raters per proposition"
-- =============================================================================

CREATE OR REPLACE FUNCTION check_early_advance_on_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_proposition RECORD;
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_total_propositions INTEGER;
    v_total_ratings INTEGER;
    v_avg_raters_per_prop NUMERIC;
    v_required INTEGER;
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

    -- Skip if no thresholds configured
    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip manual mode (manual facilitation doesn't use auto-advance)
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- Count active participants
    SELECT COUNT(*) INTO v_total_participants
    FROM participants
    WHERE chat_id = v_proposition.chat_id AND status = 'active';

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count total propositions in this round
    SELECT COUNT(*) INTO v_total_propositions
    FROM propositions
    WHERE round_id = v_proposition.round_id;

    IF v_total_propositions = 0 THEN
        RETURN NEW;
    END IF;

    -- Count total ratings in this round (from grid_rankings)
    SELECT COUNT(*) INTO v_total_ratings
    FROM grid_rankings gr
    JOIN propositions p ON p.id = gr.proposition_id
    WHERE p.round_id = v_proposition.round_id;

    -- Calculate average raters per proposition
    v_avg_raters_per_prop := v_total_ratings::NUMERIC / v_total_propositions::NUMERIC;

    -- Calculate required threshold
    -- For rating_threshold_percent: X% of participants must rate (on average per prop)
    -- For rating_threshold_count: At least X raters per proposition (on average)
    v_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    -- Check if average raters per proposition meets threshold
    IF v_required IS NOT NULL AND v_avg_raters_per_prop >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating threshold met (avg %.2f raters/prop >= %, % total ratings on % props). Completing round %.',
            v_avg_raters_per_prop, v_required, v_total_ratings, v_total_propositions, v_proposition.round_id;

        -- Complete the round with winner calculation
        PERFORM complete_round_with_winner(v_proposition.round_id);

        -- Apply adaptive duration for next round (if enabled)
        PERFORM apply_adaptive_duration(v_proposition.round_id);
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION check_early_advance_on_rating IS
'Trigger function that checks if rating threshold is met after each rating insert.
Completes the round immediately if AVERAGE RATERS PER PROPOSITION >= threshold.
This ensures all propositions have adequate rating coverage before advancing,
not just that X unique participants have submitted any rating.';

-- =============================================================================
-- Update calculate_early_advance_required comment to clarify usage
-- =============================================================================

COMMENT ON FUNCTION calculate_early_advance_required IS
'Calculates the required participation count for early advance.
Returns MAX of percent-based and count-based thresholds.
For proposing: required number of unique proposers.
For rating: required AVERAGE number of raters per proposition.';
