-- Quick-create / capped chats: a tie at the top is a FINAL result, not a new round.
--
-- on_round_winner_set completes the cycle only on a SOLE win (is_sole_winner=TRUE). On a
-- tie it falls through to "create the next round + carry forward". For a normal continuous
-- chat that's correct (run another round to break the tie). But a quick-create ranking has
-- a FIXED option list and confirmation_rounds_required=1 — there's nothing to re-propose,
-- and "stop after one result" means a tie is simply the result (two options tied for #1).
-- Spinning a new (empty/waiting) round there strands the user on "waiting for participants".
--
-- This was latent before (process-timers sets the same is_sole_winner flag → same trigger);
-- it only surfaces when the votes tie. Both the preview auto-finalize and the host
-- "End voting" button hit it.
--
-- Fix: in the non-consensus branch, if the chat is CAPPED (max_cycles IS NOT NULL) AND
-- single-confirmation (required_wins = 1), complete the cycle with this round's winner
-- instead of creating a new round. on_cycle_winner_set then seals the chat (cap reached).
-- Scoped so uncapped chats and multi-confirmation chats are completely unchanged.
--
-- Body is otherwise verbatim from the prod definition (20260529115515).

CREATE OR REPLACE FUNCTION public.on_round_winner_set()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
    new_prop_id BIGINT;
    v_winner_category TEXT;
    v_agents_enabled BOOLEAN;
    v_human_propositions INTEGER;
    v_max_cycles INTEGER;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    v_cycle_id := NEW.cycle_id;

    -- Get chat_id, confirmation_rounds_required, enable_agents, max_cycles from chat settings
    SELECT c.chat_id, ch.confirmation_rounds_required, ch.enable_agents, ch.max_cycles
    INTO v_chat_id, required_wins, v_agents_enabled, v_max_cycles
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

        -- Get the winning proposition's category for denormalization onto cycle
        SELECT category INTO v_winner_category
        FROM propositions
        WHERE id = NEW.winning_proposition_id;

        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW(),
            category = v_winner_category
        WHERE id = v_cycle_id;
    ELSIF v_max_cycles IS NOT NULL AND required_wins = 1 THEN
        -- CAPPED single-confirmation chat (quick-create ranking): a non-sole result is
        -- a TIE at the top, which is a legitimate FINAL result — there's nothing to
        -- re-propose (fixed options) and "stop after one result" means we don't drag the
        -- group into another round. Complete the cycle with this winner; on_cycle_winner_set
        -- then seals the chat (cap reached). No new round.
        SELECT category INTO v_winner_category
        FROM propositions
        WHERE id = NEW.winning_proposition_id;

        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW(),
            category = v_winner_category
        WHERE id = v_cycle_id;

        RAISE NOTICE '[ROUND WINNER] Capped conf=1 chat: non-sole (tie) result is final, completing cycle % with winner % (no new round)',
            v_cycle_id, NEW.winning_proposition_id;
    ELSE
        -- Need more rounds, create next one using the helper function
        -- This properly handles auto-start conditions (creates in proposing phase
        -- if auto mode + enough participants, instead of always waiting)
        new_round_id := create_round_for_cycle(v_cycle_id, v_chat_id, get_next_custom_id(v_cycle_id));

        RAISE NOTICE '[ROUND WINNER] Created next round % for cycle %', new_round_id, v_cycle_id;

        -- CARRY FORWARD: Copy all winning propositions to the new round
        -- This enables consensus tracking across rounds (same root ID)
        FOR winner_record IN
            SELECT rw.proposition_id, p.content, p.participant_id, p.carried_from_id, p.category
            FROM round_winners rw
            JOIN propositions p ON rw.proposition_id = p.id
            WHERE rw.round_id = NEW.id AND rw.rank = 1
        LOOP
            -- Determine the root proposition ID
            -- If already carried, use its carried_from_id; otherwise use the proposition itself
            root_prop_id := COALESCE(winner_record.carried_from_id, winner_record.proposition_id);

            -- Insert the carried-forward proposition (including category)
            INSERT INTO propositions (round_id, participant_id, content, carried_from_id, category)
            VALUES (new_round_id, winner_record.participant_id, winner_record.content, root_prop_id, winner_record.category)
            RETURNING id INTO new_prop_id;

            RAISE NOTICE '[CARRY FORWARD] Copied proposition "%" to round % (root: %, new_id: %, category: %)',
                LEFT(winner_record.content, 30), new_round_id, root_prop_id, new_prop_id, winner_record.category;

            -- COPY TRANSLATIONS from the root proposition to the new carried proposition
            -- This ensures duplicate detection works correctly
            INSERT INTO translations (proposition_id, entity_type, field_name, language_code, translated_text)
            SELECT
                new_prop_id,
                t.entity_type,
                t.field_name,
                t.language_code,
                t.translated_text
            FROM translations t
            WHERE t.proposition_id = root_prop_id
              AND t.field_name = 'content';

            RAISE NOTICE '[CARRY FORWARD] Copied translations for proposition % from root %',
                new_prop_id, root_prop_id;
        END LOOP;
    END IF;

    -- =========================================================================
    -- AUTO-PAUSE SAFETY: Prevent runaway agent-only rounds
    -- =========================================================================
    IF v_agents_enabled THEN
        SELECT COUNT(*) INTO v_human_propositions
        FROM (
            -- Humans who submitted a new proposition
            SELECT p.id
            FROM propositions p
            JOIN participants pt ON pt.id = p.participant_id
            WHERE p.round_id = NEW.id
              AND p.carried_from_id IS NULL
              AND pt.is_agent = false
            UNION ALL
            -- Humans who explicitly skipped (still counts as active participation)
            SELECT rs.id
            FROM round_skips rs
            JOIN participants pt ON pt.id = rs.participant_id
            WHERE rs.round_id = NEW.id
              AND pt.is_agent = false
        ) human_activity;

        IF v_human_propositions = 0 THEN
            UPDATE chats SET host_paused = true WHERE id = v_chat_id;
            RAISE NOTICE '[AUTO PAUSE] Chat % auto-paused: round % completed with no human propositions',
                v_chat_id, NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
