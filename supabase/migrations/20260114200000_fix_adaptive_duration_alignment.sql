-- =============================================================================
-- MIGRATION: Fix Adaptive Duration for Cron Alignment & Early Advance
-- =============================================================================
-- Issues fixed:
-- 1. Minimum duration allows 30s - Should be 60s (cron granularity)
-- 2. Adaptive calculations don't align to minutes
-- 3. Early advance doesn't apply adaptive duration
-- =============================================================================

-- =============================================================================
-- FIX 1: Update minimum duration constraint from >= 30 to >= 60
-- =============================================================================

ALTER TABLE chats DROP CONSTRAINT IF EXISTS min_phase_duration_positive;
ALTER TABLE chats ADD CONSTRAINT min_phase_duration_positive
    CHECK (min_phase_duration_seconds IS NULL OR min_phase_duration_seconds >= 60);

-- Update any existing values below 60
UPDATE chats SET min_phase_duration_seconds = 60
WHERE min_phase_duration_seconds IS NOT NULL AND min_phase_duration_seconds < 60;

-- =============================================================================
-- FIX 2: Update calculate_adaptive_duration to round to nearest minute
-- =============================================================================

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

    -- Round to nearest 60 seconds for cron alignment
    v_new_duration := (ROUND(v_new_duration / 60.0) * 60)::INTEGER;

    -- Ensure minimum is 60 seconds (cron granularity)
    v_new_duration := GREATEST(v_new_duration, 60);

    -- Clamp to bounds
    v_new_duration := GREATEST(v_new_duration, p_min_duration);
    v_new_duration := LEAST(v_new_duration, p_max_duration);

    RETURN v_new_duration;
END;
$$;

COMMENT ON FUNCTION calculate_adaptive_duration IS
'Calculates adjusted phase duration based on participation. Rounds to nearest minute for cron alignment.';

-- =============================================================================
-- FIX 3: Update early advance rating trigger to apply adaptive duration
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
    v_unique_raters INTEGER;
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

    -- Skip manual mode
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

    -- Count unique raters in this round (from grid_rankings)
    SELECT COUNT(DISTINCT gr.participant_id) INTO v_unique_raters
    FROM grid_rankings gr
    JOIN propositions p ON p.id = gr.proposition_id
    WHERE p.round_id = v_proposition.round_id;

    -- Calculate required count
    v_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    -- Check if threshold met
    IF v_required IS NOT NULL AND v_unique_raters >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating threshold met (% of % rated, required %). Completing round %.',
            v_unique_raters, v_total_participants, v_required, v_proposition.round_id;

        -- Complete the round with winner calculation
        PERFORM complete_round_with_winner(v_proposition.round_id);

        -- Apply adaptive duration for next round (if enabled)
        PERFORM apply_adaptive_duration(v_proposition.round_id);
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION check_early_advance_on_rating IS
'Trigger function that checks if rating threshold is met after each rating insert. Completes the round immediately if threshold reached and applies adaptive duration.';
