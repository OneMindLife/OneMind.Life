-- Migration: Move carry forward winners logic to database trigger
-- This ensures winners are automatically carried forward when a round completes

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
        -- Need more rounds, create next one
        INSERT INTO rounds (cycle_id, custom_id, phase)
        VALUES (v_cycle_id, get_next_custom_id(v_cycle_id), 'waiting')
        RETURNING id INTO new_round_id;

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

COMMENT ON FUNCTION on_round_winner_set() IS 'Handles round completion: tracks consensus, creates next round, and carries forward winners';
