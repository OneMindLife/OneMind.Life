-- Optimize round creation: Skip waiting phase when auto-start conditions are met
--
-- When a new round is created (either within the same cycle or in a new cycle),
-- it should start in proposing phase immediately if auto-start conditions are met,
-- instead of always creating in waiting phase and waiting for cron.

-- =============================================================================
-- Step 1: Create shared helper function
-- =============================================================================

-- Helper function to create a round for a cycle
-- Checks auto-start conditions and creates the round in the appropriate phase
CREATE OR REPLACE FUNCTION create_round_for_cycle(
    p_cycle_id BIGINT,
    p_chat_id BIGINT,
    p_custom_id INTEGER DEFAULT 1
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_new_round_id BIGINT;
    v_phase_ends_at TIMESTAMPTZ;
BEGIN
    -- Get chat settings
    SELECT
        c.start_mode,
        c.auto_start_participant_count,
        c.proposing_duration_seconds
    INTO v_chat
    FROM chats c
    WHERE c.id = p_chat_id;

    -- Check if auto-start conditions are met
    IF v_chat.start_mode = 'auto' THEN
        -- Count active participants
        SELECT COUNT(*) INTO v_participant_count
        FROM participants
        WHERE chat_id = p_chat_id
        AND status = 'active';

        IF v_participant_count >= v_chat.auto_start_participant_count THEN
            -- Auto-start conditions met: create in proposing phase with timer
            v_phase_ends_at := calculate_round_minute_end(v_chat.proposing_duration_seconds);

            INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
            VALUES (p_cycle_id, p_custom_id, 'proposing', NOW(), v_phase_ends_at)
            RETURNING id INTO v_new_round_id;

            RETURN v_new_round_id;
        END IF;
    END IF;

    -- Either manual mode or auto-start conditions not met: create in waiting phase
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (p_cycle_id, p_custom_id, 'waiting')
    RETURNING id INTO v_new_round_id;

    RETURN v_new_round_id;
END;
$$;

COMMENT ON FUNCTION create_round_for_cycle IS
'Creates a round for a cycle. For auto-mode chats with sufficient participants,
creates in proposing phase with timer. Otherwise creates in waiting phase.
Used by on_round_winner_set, on_cycle_winner_set, and check_auto_start_on_participant_join.';

-- =============================================================================
-- Step 2: Update on_cycle_winner_set to use the helper
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."on_cycle_winner_set"()
RETURNS "trigger"
LANGUAGE "plpgsql"
AS $$
DECLARE
    v_chat_id BIGINT;
    new_cycle_id BIGINT;
    new_round_id BIGINT;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    -- Get chat_id from this cycle
    SELECT chat_id INTO v_chat_id FROM cycles WHERE id = NEW.id;

    -- Create new cycle for the chat
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO new_cycle_id;

    -- Create first round of new cycle using shared helper
    -- This will check auto-start conditions and create in appropriate phase
    new_round_id := create_round_for_cycle(new_cycle_id, v_chat_id, 1);

    RETURN NEW;
END;
$$;

-- =============================================================================
-- Step 3: Update check_auto_start_on_participant_join to use the helper
-- =============================================================================

CREATE OR REPLACE FUNCTION check_auto_start_on_participant_join()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_existing_cycle_id INTEGER;
    v_new_cycle_id BIGINT;
    v_new_round_id BIGINT;
BEGIN
    -- Only proceed for active participants (not pending approval)
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT
        c.id,
        c.start_mode,
        c.auto_start_participant_count
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

        -- Create first cycle
        INSERT INTO cycles (chat_id)
        VALUES (NEW.chat_id)
        RETURNING id INTO v_new_cycle_id;

        -- Create first round using shared helper
        -- (will create in proposing phase since we just verified conditions are met)
        v_new_round_id := create_round_for_cycle(v_new_cycle_id, NEW.chat_id, 1);

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

COMMENT ON FUNCTION check_auto_start_on_participant_join IS
'Automatically starts a chat (creates cycle/round) when participant count reaches auto_start_participant_count for auto mode chats. Uses shared helper for round creation.';

-- =============================================================================
-- Step 4: Update on_round_winner_set to use the helper
-- =============================================================================

CREATE OR REPLACE FUNCTION on_round_winner_set()
RETURNS TRIGGER AS $$
DECLARE
    consecutive_sole_wins INTEGER := 0;
    required_wins INTEGER;
    v_cycle_id BIGINT;
    v_chat_id BIGINT;
    current_custom_id INTEGER;
    check_custom_id INTEGER;
    prev_winner_id BIGINT;
    prev_is_sole BOOLEAN;
    new_round_id BIGINT;
    current_root_id BIGINT;
    prev_root_id BIGINT;
    winner_record RECORD;
    root_prop_id BIGINT;
    next_custom_id INTEGER;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    v_cycle_id := NEW.cycle_id;

    -- Get chat_id and confirmation_rounds_required from chat settings
    SELECT c.chat_id, ch.confirmation_rounds_required
    INTO v_chat_id, required_wins
    FROM cycles c
    JOIN chats ch ON ch.id = c.chat_id
    WHERE c.id = v_cycle_id;

    -- Default to 2 if not set
    IF required_wins IS NULL THEN
        required_wins := 2;
    END IF;

    -- Mark current round as completed
    NEW.completed_at := NOW();

    -- Get the ROOT proposition ID for the current winner
    current_root_id := get_root_proposition_id(NEW.winning_proposition_id);

    -- CRITICAL: Only count this win toward consensus if it's a SOLE win (no ties)
    IF NEW.is_sole_winner = TRUE THEN
        consecutive_sole_wins := 1;

        -- Walk backwards through previous rounds to count consecutive SOLE wins
        current_custom_id := NEW.custom_id;
        check_custom_id := current_custom_id - 1;

        WHILE check_custom_id >= 1 LOOP
            SELECT winning_proposition_id, is_sole_winner
            INTO prev_winner_id, prev_is_sole
            FROM rounds
            WHERE cycle_id = v_cycle_id
            AND custom_id = check_custom_id;

            -- Get the ROOT proposition ID for the previous winner
            IF prev_winner_id IS NOT NULL THEN
                prev_root_id := get_root_proposition_id(prev_winner_id);
            ELSE
                prev_root_id := NULL;
            END IF;

            -- Count only if: same ROOT winner AND was a sole win (not tied)
            IF prev_root_id IS NOT NULL
               AND prev_root_id = current_root_id
               AND prev_is_sole = TRUE THEN
                consecutive_sole_wins := consecutive_sole_wins + 1;
                check_custom_id := check_custom_id - 1;
            ELSE
                -- Chain broken (different winner OR was a tie)
                EXIT;
            END IF;
        END LOOP;

        RAISE NOTICE '[ROUND WINNER] Proposition % (root: %) has % consecutive sole win(s), need %',
            NEW.winning_proposition_id, current_root_id, consecutive_sole_wins, required_wins;
    ELSE
        -- Tied win - does not count toward consensus
        RAISE NOTICE '[ROUND WINNER] Round % ended in tie (is_sole_winner=FALSE), does not count toward consensus',
            NEW.id;
    END IF;

    -- Check if we've reached the required consecutive SOLE wins
    IF consecutive_sole_wins >= required_wins THEN
        -- Consensus reached! Complete the cycle
        RAISE NOTICE '[ROUND WINNER] CONSENSUS REACHED! Completing cycle % with winner % (root: %)',
            v_cycle_id, NEW.winning_proposition_id, current_root_id;

        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW()
        WHERE id = v_cycle_id;
    ELSE
        -- Need more rounds, create next one using shared helper
        next_custom_id := get_next_custom_id(v_cycle_id);
        new_round_id := create_round_for_cycle(v_cycle_id, v_chat_id, next_custom_id);

        RAISE NOTICE '[ROUND WINNER] Created next round % for cycle %', new_round_id, v_cycle_id;

        -- CARRY FORWARD: Copy all winning propositions to the new round
        -- This enables consensus tracking across rounds (same root ID)
        FOR winner_record IN
            SELECT rw.proposition_id, p.content, p.participant_id, p.carried_from_id
            FROM round_winners rw
            JOIN propositions p ON rw.proposition_id = p.id
            WHERE rw.round_id = NEW.id AND rw.rank = 1
        LOOP
            -- Determine the root proposition ID
            -- If already carried, use its carried_from_id; otherwise use the proposition itself
            root_prop_id := COALESCE(winner_record.carried_from_id, winner_record.proposition_id);

            INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
            VALUES (new_round_id, winner_record.participant_id, winner_record.content, root_prop_id);

            RAISE NOTICE '[CARRY FORWARD] Copied proposition "%" to round % (root: %)',
                LEFT(winner_record.content, 30), new_round_id, root_prop_id;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION on_round_winner_set() IS 'Handles round completion: tracks consensus, creates next round using shared helper, and carries forward winners';
