-- =============================================================================
-- MIGRATION: Simplify Adaptive Duration
-- =============================================================================
-- Change: Remove adaptive_threshold_count and reuse existing early advance
-- thresholds (proposing_threshold_*, rating_threshold_*) instead.
--
-- This makes adaptive duration simpler and more consistent:
-- - Proposing threshold determines if proposing duration adjusts
-- - Rating threshold determines if rating duration adjusts
-- =============================================================================

-- =============================================================================
-- STEP 1: Drop the adaptive_threshold_count column
-- =============================================================================

ALTER TABLE chats DROP CONSTRAINT IF EXISTS adaptive_threshold_positive;
ALTER TABLE chats DROP COLUMN IF EXISTS adaptive_threshold_count;

-- =============================================================================
-- STEP 2: Update apply_adaptive_duration to use existing thresholds
-- =============================================================================

-- Must DROP first since return type is changing (can't use CREATE OR REPLACE)
DROP FUNCTION IF EXISTS apply_adaptive_duration(BIGINT);

CREATE OR REPLACE FUNCTION apply_adaptive_duration(p_round_id BIGINT)
RETURNS TABLE (
    new_proposing_duration INTEGER,
    new_rating_duration INTEGER,
    proposing_participation INTEGER,
    rating_participation INTEGER,
    adjustment_applied TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participation RECORD;
    v_total_participants INTEGER;
    v_proposing_required INTEGER;
    v_rating_required INTEGER;
    v_new_proposing INTEGER;
    v_new_rating INTEGER;
    v_proposing_adjustment TEXT;
    v_rating_adjustment TEXT;
BEGIN
    -- Get chat settings via round -> cycle -> chat
    SELECT c.* INTO v_chat
    FROM chats c
    JOIN cycles cy ON cy.chat_id = c.id
    JOIN rounds r ON r.cycle_id = cy.id
    WHERE r.id = p_round_id;

    -- If adaptive duration not enabled, return current values
    IF NOT v_chat.adaptive_duration_enabled THEN
        RETURN QUERY SELECT
            v_chat.proposing_duration_seconds,
            v_chat.rating_duration_seconds,
            0,
            0,
            'disabled'::TEXT;
        RETURN;
    END IF;

    -- Get participation counts for this round
    SELECT * INTO v_participation FROM count_round_participation(p_round_id);

    -- Get total active participants
    SELECT COUNT(*) INTO v_total_participants
    FROM participants
    WHERE chat_id = v_chat.id AND status = 'active';

    -- If no participants, skip adjustment
    IF v_total_participants = 0 THEN
        RETURN QUERY SELECT
            v_chat.proposing_duration_seconds,
            v_chat.rating_duration_seconds,
            0,
            0,
            'no_participants'::TEXT;
        RETURN;
    END IF;

    -- Calculate required thresholds using existing early advance settings
    v_proposing_required := calculate_early_advance_required(
        v_chat.proposing_threshold_percent,
        v_chat.proposing_threshold_count,
        v_total_participants
    );

    v_rating_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    -- Default to current durations
    v_new_proposing := v_chat.proposing_duration_seconds;
    v_new_rating := v_chat.rating_duration_seconds;
    v_proposing_adjustment := 'unchanged';
    v_rating_adjustment := 'unchanged';

    -- Adjust proposing duration if threshold is configured
    IF v_proposing_required IS NOT NULL THEN
        IF v_participation.proposing_count >= v_proposing_required THEN
            -- Met threshold: decrease duration
            v_new_proposing := calculate_adaptive_duration(
                v_chat.proposing_duration_seconds,
                v_participation.proposing_count,
                v_proposing_required,
                v_chat.adaptive_adjustment_percent,
                v_chat.min_phase_duration_seconds,
                v_chat.max_phase_duration_seconds
            );
            v_proposing_adjustment := 'decreased';
        ELSE
            -- Below threshold: increase duration
            v_new_proposing := calculate_adaptive_duration(
                v_chat.proposing_duration_seconds,
                v_participation.proposing_count,
                v_proposing_required,
                v_chat.adaptive_adjustment_percent,
                v_chat.min_phase_duration_seconds,
                v_chat.max_phase_duration_seconds
            );
            v_proposing_adjustment := 'increased';
        END IF;
    END IF;

    -- Adjust rating duration if threshold is configured
    IF v_rating_required IS NOT NULL THEN
        IF v_participation.rating_count >= v_rating_required THEN
            -- Met threshold: decrease duration
            v_new_rating := calculate_adaptive_duration(
                v_chat.rating_duration_seconds,
                v_participation.rating_count,
                v_rating_required,
                v_chat.adaptive_adjustment_percent,
                v_chat.min_phase_duration_seconds,
                v_chat.max_phase_duration_seconds
            );
            v_rating_adjustment := 'decreased';
        ELSE
            -- Below threshold: increase duration
            v_new_rating := calculate_adaptive_duration(
                v_chat.rating_duration_seconds,
                v_participation.rating_count,
                v_rating_required,
                v_chat.adaptive_adjustment_percent,
                v_chat.min_phase_duration_seconds,
                v_chat.max_phase_duration_seconds
            );
            v_rating_adjustment := 'increased';
        END IF;
    END IF;

    -- Update the chat with new durations
    UPDATE chats SET
        proposing_duration_seconds = v_new_proposing,
        rating_duration_seconds = v_new_rating
    WHERE id = v_chat.id;

    -- Update round with participation counts
    UPDATE rounds SET
        proposing_participant_count = v_participation.proposing_count,
        rating_participant_count = v_participation.rating_count
    WHERE id = p_round_id;

    -- Return combined adjustment status
    RETURN QUERY SELECT
        v_new_proposing,
        v_new_rating,
        v_participation.proposing_count,
        v_participation.rating_count,
        (v_proposing_adjustment || '/' || v_rating_adjustment)::TEXT;
END;
$$;

COMMENT ON FUNCTION apply_adaptive_duration IS
'Applies adaptive duration adjustment after a round completes. Uses existing early advance thresholds (proposing_threshold_*, rating_threshold_*) to determine if participation was sufficient.';
