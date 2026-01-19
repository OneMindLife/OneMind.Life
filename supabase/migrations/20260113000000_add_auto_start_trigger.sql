-- Add auto-start trigger for chats with start_mode = 'auto'
-- When participant count reaches auto_start_participant_count, automatically create first cycle/round

-- Function to check if auto-start should trigger and create first cycle/round
CREATE OR REPLACE FUNCTION check_auto_start_on_participant_join()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_existing_cycle_id INTEGER;
    v_new_cycle_id INTEGER;
    v_new_round_id INTEGER;
    v_phase_ends_at TIMESTAMPTZ;
BEGIN
    -- Only proceed for active participants (not pending approval)
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT
        c.id,
        c.start_mode,
        c.auto_start_participant_count,
        c.proposing_duration_seconds
    INTO v_chat
    FROM chats c
    WHERE c.id = NEW.chat_id;

    -- Only proceed if chat is in auto mode
    IF v_chat.start_mode != 'auto' THEN
        RETURN NEW;
    END IF;

    -- Check if there's already an existing cycle (chat already started)
    SELECT id INTO v_existing_cycle_id
    FROM cycles
    WHERE chat_id = NEW.chat_id
    LIMIT 1;

    IF v_existing_cycle_id IS NOT NULL THEN
        -- Chat already started, nothing to do
        RETURN NEW;
    END IF;

    -- Count active participants
    SELECT COUNT(*) INTO v_participant_count
    FROM participants
    WHERE chat_id = NEW.chat_id
    AND status = 'active';

    RAISE NOTICE '[AUTO-START] Chat % has % active participants, threshold is %',
        NEW.chat_id, v_participant_count, v_chat.auto_start_participant_count;

    -- Check if we've reached the threshold
    IF v_participant_count >= v_chat.auto_start_participant_count THEN
        RAISE NOTICE '[AUTO-START] Threshold reached! Creating cycle and round for chat %', NEW.chat_id;

        -- Calculate phase end time (auto mode uses timers)
        v_phase_ends_at := NOW() + (v_chat.proposing_duration_seconds * INTERVAL '1 second');

        -- Create first cycle
        INSERT INTO cycles (chat_id)
        VALUES (NEW.chat_id)
        RETURNING id INTO v_new_cycle_id;

        -- Create first round in proposing phase (auto mode starts immediately)
        INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
        VALUES (v_new_cycle_id, 1, 'proposing', NOW(), v_phase_ends_at)
        RETURNING id INTO v_new_round_id;

        -- Update chat last_activity_at
        UPDATE chats
        SET last_activity_at = NOW()
        WHERE id = NEW.chat_id;

        RAISE NOTICE '[AUTO-START] Created cycle % and round % for chat %',
            v_new_cycle_id, v_new_round_id, NEW.chat_id;
    END IF;

    RETURN NEW;
END;
$$;

-- Create trigger on participants table
DROP TRIGGER IF EXISTS trigger_check_auto_start ON participants;

CREATE TRIGGER trigger_check_auto_start
AFTER INSERT OR UPDATE OF status ON participants
FOR EACH ROW
EXECUTE FUNCTION check_auto_start_on_participant_join();

COMMENT ON FUNCTION check_auto_start_on_participant_join IS
'Automatically starts a chat (creates cycle/round) when participant count reaches auto_start_participant_count for auto mode chats.';
