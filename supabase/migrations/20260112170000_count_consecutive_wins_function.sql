-- Migration: Add function to count consecutive sole wins using root proposition IDs
-- This is used by the frontend to display progress toward consensus

CREATE OR REPLACE FUNCTION count_consecutive_sole_wins(p_cycle_id BIGINT, p_proposition_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    target_root_id BIGINT;
    consecutive_count INTEGER := 0;
    round_record RECORD;
    round_root_id BIGINT;
BEGIN
    -- Get the root ID of the target proposition
    target_root_id := get_root_proposition_id(p_proposition_id);

    -- Walk through completed rounds in reverse order (most recent first)
    FOR round_record IN
        SELECT id, winning_proposition_id, is_sole_winner, custom_id
        FROM rounds
        WHERE cycle_id = p_cycle_id
        AND winning_proposition_id IS NOT NULL
        ORDER BY custom_id DESC
    LOOP
        -- Get root ID of this round's winner
        round_root_id := get_root_proposition_id(round_record.winning_proposition_id);

        -- Check if same root AND was a sole win
        IF round_root_id = target_root_id AND round_record.is_sole_winner = TRUE THEN
            consecutive_count := consecutive_count + 1;
        ELSE
            -- Chain broken
            EXIT;
        END IF;
    END LOOP;

    RETURN consecutive_count;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION count_consecutive_sole_wins(BIGINT, BIGINT) IS 'Counts consecutive sole wins for a proposition (by root ID) in a cycle';
