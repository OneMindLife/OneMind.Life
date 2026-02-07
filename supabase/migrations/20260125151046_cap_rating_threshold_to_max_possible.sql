-- =============================================================================
-- MIGRATION: Cap Rating Threshold to What's Maximally Possible
-- =============================================================================
-- PROBLEM: rating_threshold_percent = 100% is impossible because users can't
-- rate their own propositions. With 5 participants, 100% = 5 but max = 4.
--
-- FIX: Cap the effective threshold to (participants - 1), which is the
-- maximum average ratings per proposition achievable.
--
-- Example with 5 participants, threshold_percent = 100%:
--   OLD: required = CEIL(5 * 100 / 100) = 5 (impossible!)
--   NEW: required = LEAST(5, 5 - 1) = 4 (achievable)
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
    v_max_possible INTEGER;
    v_effective_required INTEGER;
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

    -- Calculate required threshold using helper function
    v_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    -- NEW: Cap to what's maximally possible
    -- Each proposition can only get (participants - 1) ratings max
    -- because users can't rate their own propositions
    v_max_possible := v_total_participants - 1;
    v_effective_required := LEAST(v_required, v_max_possible);

    -- Ensure at least rating_minimum is met
    v_effective_required := GREATEST(v_effective_required, v_chat.rating_minimum);

    RAISE NOTICE '[EARLY ADVANCE] Rating check: avg %.2f raters/prop. Required: % (raw: %, max possible: %). Total: % ratings on % props.',
        v_avg_raters_per_prop, v_effective_required, v_required, v_max_possible, v_total_ratings, v_total_propositions;

    -- Check if average raters per proposition meets threshold
    IF v_effective_required IS NOT NULL AND v_avg_raters_per_prop >= v_effective_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating threshold met (avg %.2f >= %). Completing round %.',
            v_avg_raters_per_prop, v_effective_required, v_proposition.round_id;

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
Completes the round immediately if AVERAGE RATERS PER PROPOSITION >= effective threshold.
The effective threshold is capped to (participants - 1) since users cannot rate their own propositions.
This ensures 100% threshold means "everyone who CAN rate HAS rated" rather than an impossible target.';

-- =============================================================================
-- Also update the process-timers compatible function for consistency
-- =============================================================================

-- Add a helper function for capping rating threshold
CREATE OR REPLACE FUNCTION calculate_rating_threshold_capped(
    threshold_percent INTEGER,
    threshold_count INTEGER,
    total_participants INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    raw_required INTEGER;
    max_possible INTEGER;
BEGIN
    -- Calculate raw requirement using existing helper
    raw_required := calculate_early_advance_required(threshold_percent, threshold_count, total_participants);

    IF raw_required IS NULL THEN
        RETURN NULL;
    END IF;

    -- Cap to what's maximally possible (participants - 1)
    -- Users can't rate their own propositions
    max_possible := total_participants - 1;

    RETURN LEAST(raw_required, max_possible);
END;
$$;

COMMENT ON FUNCTION calculate_rating_threshold_capped IS
'Calculates the effective rating threshold, capped to what is maximally achievable.
Since users cannot rate their own propositions, the max average ratings per proposition
is (participants - 1). This function ensures 100% threshold is achievable.';
