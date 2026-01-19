-- =============================================================================
-- MIGRATION: Add adaptive duration feature
-- =============================================================================
-- Allows chats to automatically adjust phase durations based on participation
-- - If participation >= threshold: decrease duration by X%
-- - If participation < threshold: increase duration by X%
-- =============================================================================

-- ============================================================================
-- STEP 1: Add adaptive duration columns to chats table
-- ============================================================================

ALTER TABLE "public"."chats"
ADD COLUMN IF NOT EXISTS "adaptive_duration_enabled" BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS "adaptive_threshold_count" INTEGER DEFAULT 10,
ADD COLUMN IF NOT EXISTS "adaptive_adjustment_percent" INTEGER DEFAULT 10,
ADD COLUMN IF NOT EXISTS "min_phase_duration_seconds" INTEGER DEFAULT 60,
ADD COLUMN IF NOT EXISTS "max_phase_duration_seconds" INTEGER DEFAULT 86400;

-- Add constraints
ALTER TABLE "public"."chats"
ADD CONSTRAINT "adaptive_threshold_positive"
    CHECK ("adaptive_threshold_count" IS NULL OR "adaptive_threshold_count" >= 1),
ADD CONSTRAINT "adaptive_adjustment_range"
    CHECK ("adaptive_adjustment_percent" IS NULL OR ("adaptive_adjustment_percent" >= 1 AND "adaptive_adjustment_percent" <= 50)),
ADD CONSTRAINT "min_phase_duration_positive"
    CHECK ("min_phase_duration_seconds" IS NULL OR "min_phase_duration_seconds" >= 30),
ADD CONSTRAINT "max_phase_duration_valid"
    CHECK ("max_phase_duration_seconds" IS NULL OR ("max_phase_duration_seconds" >= "min_phase_duration_seconds" AND "max_phase_duration_seconds" <= 86400));

-- ============================================================================
-- STEP 2: Add columns to track participation per round
-- ============================================================================

ALTER TABLE "public"."rounds"
ADD COLUMN IF NOT EXISTS "proposing_participant_count" INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS "rating_participant_count" INTEGER DEFAULT 0;

-- ============================================================================
-- STEP 3: Create function to count unique participants in a round
-- ============================================================================

CREATE OR REPLACE FUNCTION count_round_participation(p_round_id BIGINT)
RETURNS TABLE (proposing_count INTEGER, rating_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(DISTINCT participant_id)::INTEGER
         FROM propositions WHERE round_id = p_round_id) AS proposing_count,
        (SELECT COUNT(DISTINCT participant_id)::INTEGER
         FROM grid_rankings WHERE round_id = p_round_id) AS rating_count;
END;
$$;

-- ============================================================================
-- STEP 4: Create function to adjust duration based on participation
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_adaptive_duration(
    p_current_duration INTEGER,
    p_participation_count INTEGER,
    p_threshold_count INTEGER,
    p_adjustment_percent INTEGER,
    p_min_duration INTEGER,
    p_max_duration INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_new_duration INTEGER;
    v_adjustment NUMERIC;
BEGIN
    -- Calculate adjustment factor (e.g., 10% = 0.10)
    v_adjustment := p_adjustment_percent / 100.0;

    IF p_participation_count >= p_threshold_count THEN
        -- Met threshold: decrease duration
        v_new_duration := (p_current_duration * (1 - v_adjustment))::INTEGER;
    ELSE
        -- Below threshold: increase duration
        v_new_duration := (p_current_duration * (1 + v_adjustment))::INTEGER;
    END IF;

    -- Clamp to bounds
    v_new_duration := GREATEST(v_new_duration, p_min_duration);
    v_new_duration := LEAST(v_new_duration, p_max_duration);

    RETURN v_new_duration;
END;
$$;

-- ============================================================================
-- STEP 5: Create function to apply adaptive duration after round completion
-- ============================================================================

CREATE OR REPLACE FUNCTION apply_adaptive_duration(p_round_id BIGINT)
RETURNS TABLE (
    new_proposing_duration INTEGER,
    new_rating_duration INTEGER,
    participation_used INTEGER,
    threshold INTEGER,
    adjustment_applied TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participation RECORD;
    v_phase TEXT;
    v_count INTEGER;
    v_new_proposing INTEGER;
    v_new_rating INTEGER;
    v_adjustment TEXT;
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

    -- Get participation counts
    SELECT * INTO v_participation FROM count_round_participation(p_round_id);

    -- Use the higher of proposing or rating count as participation metric
    v_count := GREATEST(v_participation.proposing_count, v_participation.rating_count);

    -- Calculate new durations
    v_new_proposing := calculate_adaptive_duration(
        v_chat.proposing_duration_seconds,
        v_count,
        v_chat.adaptive_threshold_count,
        v_chat.adaptive_adjustment_percent,
        v_chat.min_phase_duration_seconds,
        v_chat.max_phase_duration_seconds
    );

    v_new_rating := calculate_adaptive_duration(
        v_chat.rating_duration_seconds,
        v_count,
        v_chat.adaptive_threshold_count,
        v_chat.adaptive_adjustment_percent,
        v_chat.min_phase_duration_seconds,
        v_chat.max_phase_duration_seconds
    );

    -- Determine adjustment type for logging
    IF v_count >= v_chat.adaptive_threshold_count THEN
        v_adjustment := 'decreased';
    ELSE
        v_adjustment := 'increased';
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

    RETURN QUERY SELECT
        v_new_proposing,
        v_new_rating,
        v_count,
        v_chat.adaptive_threshold_count,
        v_adjustment;
END;
$$;

-- ============================================================================
-- STEP 6: Add comments for documentation
-- ============================================================================

COMMENT ON COLUMN chats.adaptive_duration_enabled IS
    'Enable automatic phase duration adjustment based on participation';
COMMENT ON COLUMN chats.adaptive_threshold_count IS
    'Minimum participants required to decrease duration (default: 10)';
COMMENT ON COLUMN chats.adaptive_adjustment_percent IS
    'Percentage to adjust duration by (default: 10%)';
COMMENT ON COLUMN chats.min_phase_duration_seconds IS
    'Floor for phase duration in seconds (default: 60 = 1 min)';
COMMENT ON COLUMN chats.max_phase_duration_seconds IS
    'Ceiling for phase duration in seconds (default: 86400 = 1 day)';
