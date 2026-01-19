-- Migration: Carry forward winners for consensus tracking
-- Adds carried_from_id to track original proposition through rounds

-- Add carried_from_id column to propositions
ALTER TABLE propositions
ADD COLUMN carried_from_id BIGINT REFERENCES propositions(id) ON DELETE SET NULL;

-- Add index for efficient lookups
CREATE INDEX idx_propositions_carried_from ON propositions(carried_from_id) WHERE carried_from_id IS NOT NULL;

-- Function to get the root proposition ID (follows the carried_from chain)
CREATE OR REPLACE FUNCTION get_root_proposition_id(p_proposition_id BIGINT)
RETURNS BIGINT AS $$
DECLARE
    current_id BIGINT := p_proposition_id;
    parent_id BIGINT;
    iteration_count INT := 0;
BEGIN
    -- Follow the chain up to 100 iterations (safety limit)
    LOOP
        SELECT carried_from_id INTO parent_id
        FROM propositions
        WHERE id = current_id;

        IF parent_id IS NULL THEN
            -- No parent, this is the root
            RETURN current_id;
        END IF;

        current_id := parent_id;
        iteration_count := iteration_count + 1;

        IF iteration_count > 100 THEN
            RAISE EXCEPTION 'Circular reference detected in proposition chain';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- Update the on_round_winner_set trigger to use root proposition IDs
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
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON COLUMN propositions.carried_from_id IS 'References the original proposition this was carried forward from (for consensus tracking)';
COMMENT ON FUNCTION get_root_proposition_id(BIGINT) IS 'Follows the carried_from chain to find the root proposition ID';
