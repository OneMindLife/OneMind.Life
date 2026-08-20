-- TOPIC VOTE (game mode): democratic topic selection.
--
-- The loop: a game ends -> result + leaderboard -> host taps "Next game" ->
-- TOPIC ROUND (everyone proposes a topic, single round, most votes wins,
-- tie -> the engine's pick) -> that topic becomes the ANSWER game's question
-- -> the answer game runs and converges normally. Host paces (when to move on),
-- the GROUP picks the topic.
--
-- A topic cycle (cycles.is_topic = TRUE) is a SINGLE round: on_round_winner_set
-- short-circuits convergence for it, copies the winning topic onto the chat's
-- question, and opens the answer cycle. The topic round is selection, not the
-- game, so it does not affect the leaderboard (the leaderboard queries the
-- latest non-topic cycle — client-side).

ALTER TABLE public.cycles
  ADD COLUMN IF NOT EXISTS is_topic boolean NOT NULL DEFAULT false;

-- ── on_round_winner_set: + topic-round branch (rest of the body is unchanged) ──
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
    v_answer_cycle BIGINT;
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

    -- TOPIC ROUND (game mode): a single round whose winner becomes the NEXT
    -- game's question; then the answer game starts immediately. No convergence,
    -- carry-forward, or auto-pause — the topic round is SELECTION, not the game.
    IF (SELECT is_topic FROM cycles WHERE id = v_cycle_id) THEN
        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW()
        WHERE id = v_cycle_id;

        -- Winning topic becomes the chat's question; reopen the room and start
        -- the answer game (fresh non-topic cycle straight into proposing).
        UPDATE chats
        SET initial_message = (SELECT content FROM propositions WHERE id = NEW.winning_proposition_id),
            ended_at = NULL
        WHERE id = v_chat_id;

        INSERT INTO cycles (chat_id, is_topic, question)
        VALUES (v_chat_id, FALSE,
                (SELECT content FROM propositions WHERE id = NEW.winning_proposition_id))
        RETURNING id INTO v_answer_cycle;

        INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
        VALUES (v_answer_cycle, 1, 'proposing', NOW());

        RAISE NOTICE '[TOPIC ROUND] topic % won -> answer game cycle % on chat %',
            NEW.winning_proposition_id, v_answer_cycle, v_chat_id;
        RETURN NEW;
    END IF;

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
    -- A human counts as ENGAGED this round if they did ANY of: submitted a new
    -- proposition, skipped proposing, or cast a rating vote (grid OR
    -- pairwise/matches). Only when ZERO humans engaged at all do we auto-pause,
    -- so agents don't spin indefinitely on an abandoned chat. Carried-forward
    -- propositions don't count (not fresh activity); rating_skips don't count
    -- (can be auto-generated for stranded raters — not genuine engagement).
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
            -- Humans who explicitly skipped proposing
            SELECT rs.id
            FROM round_skips rs
            JOIN participants pt ON pt.id = rs.participant_id
            WHERE rs.round_id = NEW.id
              AND pt.is_agent = false
            UNION ALL
            -- Humans who rated (grid mode)
            SELECT g.id
            FROM grid_rankings g
            JOIN participants pt ON pt.id = g.participant_id
            WHERE g.round_id = NEW.id
              AND pt.is_agent = false
            UNION ALL
            -- Humans who rated (matches / pairwise mode)
            SELECT pc.id
            FROM pairwise_comparisons pc
            JOIN participants pt ON pt.id = pc.participant_id
            WHERE pc.round_id = NEW.id
              AND pt.is_agent = false
        ) human_activity;

        IF v_human_propositions = 0 THEN
            UPDATE chats SET host_paused = true WHERE id = v_chat_id;
            RAISE NOTICE '[AUTO PAUSE] Chat % auto-paused: round % completed with no human activity (propose/skip/rate)',
                v_chat_id, NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$

;

-- ── start_topic_round: host opens the next game's topic vote ──
CREATE OR REPLACE FUNCTION public.start_topic_round(p_chat_id bigint, p_prompt text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_service_role boolean;
  v_caller uuid;
  v_is_host boolean;
  v_mode text;
  v_cycle_id bigint;
BEGIN
  v_is_service_role := COALESCE(current_setting('role', true) = 'service_role', false)
                    OR COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', false);

  SELECT mode INTO v_mode FROM chats WHERE id = p_chat_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat % not found', p_chat_id;
  END IF;
  IF v_mode <> 'game' THEN
    RAISE EXCEPTION 'start_topic_round is only available for game-mode chats';
  END IF;
  IF p_prompt IS NULL OR length(btrim(p_prompt)) = 0 THEN
    RAISE EXCEPTION 'A prompt is required for the topic round';
  END IF;

  -- Authz: active host (or service role).
  IF NOT v_is_service_role THEN
    v_caller := auth.uid();
    IF v_caller IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;
    SELECT is_host INTO v_is_host
    FROM participants
    WHERE chat_id = p_chat_id AND user_id = v_caller AND status = 'active';
    IF v_is_host IS NOT TRUE THEN
      RAISE EXCEPTION 'Only the host can start the next game';
    END IF;
  END IF;

  -- Reopen the room; the prompt frames the topic round (group proposes topics).
  UPDATE chats
  SET ended_at = NULL,
      initial_message = p_prompt
  WHERE id = p_chat_id;

  -- TOPIC cycle = single round; its winner becomes the answer game's question
  -- (on_round_winner_set topic branch). Group already present -> straight to
  -- proposing.
  INSERT INTO cycles (chat_id, is_topic, question)
  VALUES (p_chat_id, TRUE, p_prompt)
  RETURNING id INTO v_cycle_id;

  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle_id, 1, 'proposing', NOW());

  RETURN v_cycle_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.start_topic_round(bigint, text) TO anon, authenticated, service_role;
