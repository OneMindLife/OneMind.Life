-- Immediate early advance triggers
-- Advances phase immediately when participation thresholds are met
-- (Instead of waiting for cron job)

-- =============================================================================
-- HELPER FUNCTION: Calculate required participation count
-- =============================================================================
CREATE OR REPLACE FUNCTION calculate_early_advance_required(
    threshold_percent INTEGER,
    threshold_count INTEGER,
    total_participants INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    percent_required INTEGER;
    count_required INTEGER;
BEGIN
    -- If both are null, early advance is disabled
    IF threshold_percent IS NULL AND threshold_count IS NULL THEN
        RETURN NULL;
    END IF;

    -- Calculate percent-based requirement (rounded up)
    IF threshold_percent IS NOT NULL THEN
        percent_required := CEIL(total_participants::NUMERIC * threshold_percent / 100);
    ELSE
        percent_required := 0;
    END IF;

    -- Count-based requirement
    count_required := COALESCE(threshold_count, 0);

    -- Return MAX (more restrictive)
    RETURN GREATEST(percent_required, count_required);
END;
$$;

-- =============================================================================
-- TRIGGER FUNCTION: Check early advance on proposition insert
-- =============================================================================
CREATE OR REPLACE FUNCTION check_early_advance_on_proposition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_unique_submitters INTEGER;
    v_required INTEGER;
    v_phase_ends_at TIMESTAMPTZ;
BEGIN
    -- Get round info
    SELECT r.*, c.id as cycle_id, c.chat_id
    INTO v_round
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = NEW.round_id;

    -- Only check during proposing phase
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM chats
    WHERE id = v_round.chat_id;

    -- Skip if no thresholds configured
    IF v_chat.proposing_threshold_percent IS NULL AND v_chat.proposing_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip manual mode
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- Count active participants
    SELECT COUNT(*) INTO v_total_participants
    FROM participants
    WHERE chat_id = v_round.chat_id AND status = 'active';

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count unique submitters in this round
    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM propositions
    WHERE round_id = NEW.round_id;

    -- Calculate required count
    v_required := calculate_early_advance_required(
        v_chat.proposing_threshold_percent,
        v_chat.proposing_threshold_count,
        v_total_participants
    );

    -- Check if threshold met
    IF v_required IS NOT NULL AND v_unique_submitters >= v_required THEN
        -- Calculate phase_ends_at using round-minute alignment
        v_phase_ends_at := calculate_round_minute_end(v_chat.rating_duration_seconds);

        -- Advance to rating phase
        UPDATE rounds
        SET phase = 'rating',
            phase_started_at = NOW(),
            phase_ends_at = v_phase_ends_at
        WHERE id = NEW.round_id;

        RAISE NOTICE '[EARLY ADVANCE] Proposing threshold met (% of % submitted, required %). Advancing round % to rating.',
            v_unique_submitters, v_total_participants, v_required, NEW.round_id;
    END IF;

    RETURN NEW;
END;
$$;

-- =============================================================================
-- HELPER FUNCTION: Complete round with winner calculation
-- =============================================================================
CREATE OR REPLACE FUNCTION complete_round_with_winner(p_round_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_winner_id BIGINT;
    v_max_score REAL;
    v_tied_count INTEGER;
    v_is_sole_winner BOOLEAN;
BEGIN
    -- Get round info
    SELECT * INTO v_round FROM rounds WHERE id = p_round_id;

    IF v_round IS NULL OR v_round.completed_at IS NOT NULL THEN
        RETURN; -- Round doesn't exist or already completed
    END IF;

    -- Get the winner(s) from proposition_global_scores (MOVDA already calculated by trigger)
    SELECT proposition_id, global_score INTO v_winner_id, v_max_score
    FROM proposition_global_scores
    WHERE round_id = p_round_id
    ORDER BY global_score DESC
    LIMIT 1;

    IF v_winner_id IS NULL THEN
        -- No scores yet, use oldest proposition
        SELECT id INTO v_winner_id
        FROM propositions
        WHERE round_id = p_round_id
        ORDER BY created_at ASC
        LIMIT 1;
        v_is_sole_winner := TRUE;
    ELSE
        -- Check for ties
        SELECT COUNT(*) INTO v_tied_count
        FROM proposition_global_scores
        WHERE round_id = p_round_id AND global_score = v_max_score;

        v_is_sole_winner := (v_tied_count = 1);

        -- Insert all winners into round_winners table
        INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
        SELECT p_round_id, proposition_id,
               ROW_NUMBER() OVER (ORDER BY global_score DESC),
               global_score
        FROM proposition_global_scores
        WHERE round_id = p_round_id
        ORDER BY global_score DESC;
    END IF;

    -- Update round with winner (triggers on_round_winner_set for consensus check)
    UPDATE rounds
    SET winning_proposition_id = v_winner_id,
        is_sole_winner = v_is_sole_winner,
        completed_at = NOW()
    WHERE id = p_round_id;

    RAISE NOTICE '[EARLY ADVANCE] Completed round % with winner %, sole_winner=%',
        p_round_id, v_winner_id, v_is_sole_winner;
END;
$$;

-- =============================================================================
-- TRIGGER FUNCTION: Check early advance on rating insert
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
    END IF;

    RETURN NEW;
END;
$$;

-- =============================================================================
-- CREATE TRIGGERS
-- =============================================================================

-- Trigger on propositions for proposing phase early advance
DROP TRIGGER IF EXISTS trigger_early_advance_proposition ON propositions;
CREATE TRIGGER trigger_early_advance_proposition
    AFTER INSERT ON propositions
    FOR EACH ROW
    EXECUTE FUNCTION check_early_advance_on_proposition();

-- Trigger on grid_rankings for rating phase early advance
DROP TRIGGER IF EXISTS trigger_early_advance_rating ON grid_rankings;
CREATE TRIGGER trigger_early_advance_rating
    AFTER INSERT ON grid_rankings
    FOR EACH ROW
    EXECUTE FUNCTION check_early_advance_on_rating();

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON FUNCTION calculate_early_advance_required IS
'Calculates the required participation count for early advance. Returns MAX of percent-based and count-based thresholds.';

COMMENT ON FUNCTION check_early_advance_on_proposition IS
'Trigger function that checks if proposing threshold is met after each proposition insert. Advances to rating phase immediately if threshold reached.';

COMMENT ON FUNCTION check_early_advance_on_rating IS
'Trigger function that checks if rating threshold is met after each rating insert. Completes the round immediately if threshold reached.';
