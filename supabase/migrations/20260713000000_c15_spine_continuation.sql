-- C15 spine continuation — in a branching chat the stack DESCENDS: when any
-- cycle (root or child) seals, the next position is the WINNER's follow-up
-- subround, not another root cycle. The tip of the spine is always live
-- ("leaf nodes always running"), born into a fresh proposing window so the
-- tree keeps flipping together; the AI proposer fires on the round INSERT.
-- Non-winner options still materialize lazily on demand.

CREATE OR REPLACE FUNCTION public.on_cycle_winner_set()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_chat_id BIGINT;
    v_max_cycles INTEGER;
    v_branching BOOLEAN;
    v_proposing_secs INTEGER;
    v_completed_count INTEGER;
    new_cycle_id BIGINT;
    new_round_id BIGINT;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    SELECT c.chat_id, ch.max_cycles, ch.branching_enabled, ch.proposing_duration_seconds
    INTO v_chat_id, v_max_cycles, v_branching, v_proposing_secs
    FROM cycles c
    JOIN chats ch ON ch.id = c.chat_id
    WHERE c.id = NEW.id;

    -- C15 tree mode: the spine continues INTO the winner. Any sealing cycle
    -- (root or child) spawns the winning proposition's follow-up subround —
    -- unless it already exists (someone explored it early).
    IF v_branching THEN
        IF NOT EXISTS (SELECT 1 FROM cycles WHERE parent_proposition_id = NEW.winning_proposition_id) THEN
            INSERT INTO cycles (chat_id, parent_proposition_id)
            VALUES (v_chat_id, NEW.winning_proposition_id)
            RETURNING id INTO new_cycle_id;

            INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
            VALUES (new_cycle_id, 1, 'proposing', NOW(), NOW() + make_interval(secs => v_proposing_secs));
        END IF;
        RETURN NEW;
    END IF;

    -- Non-branching child cycles (defensive; shouldn't exist) seal quietly.
    IF NEW.parent_proposition_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Stop-after-N: only ROOT cycles count toward the cap.
    IF v_max_cycles IS NOT NULL THEN
        SELECT COUNT(*) INTO v_completed_count
        FROM cycles
        WHERE chat_id = v_chat_id AND completed_at IS NOT NULL
          AND parent_proposition_id IS NULL;

        IF v_completed_count >= v_max_cycles THEN
            UPDATE chats SET ended_at = NOW() WHERE id = v_chat_id AND ended_at IS NULL;
            RETURN NEW;
        END IF;
    END IF;

    -- Continuous (default): create new ROOT cycle for the chat
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO new_cycle_id;

    new_round_id := create_round_for_cycle(new_cycle_id, v_chat_id, 1);

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.on_cycle_winner_set() IS
    'On cycle consensus. Branching chats: the spine descends — sealing any cycle spawns the winner''s follow-up subround (fresh proposing window; AI proposer fires on the round INSERT). Non-branching: max_cycles cap or next root cycle (continuous default).';
