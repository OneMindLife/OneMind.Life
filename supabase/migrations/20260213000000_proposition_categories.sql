-- ============================================================================
-- Proposition Categories & State Machine
-- ============================================================================
-- Adds a category system to control deliberation flow at the agent level:
--   question → [question, thought, human_task, research_task]
--   thought → [question]
--   human_task → [human_task_result]       (agents STOP, wait for host)
--   human_task_result → [question]
--   research_task → [research_task_result]  (auto-executed by orchestrator)
--   research_task_result → [question]
--   NULL (legacy) → [question, thought, human_task, research_task]
--
-- Categories are enforced at the AGENT level only — human users can propose
-- freely without category constraints.
-- ============================================================================

-- (a) Add category column to propositions
ALTER TABLE propositions ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE propositions ADD CONSTRAINT propositions_category_check
  CHECK (category IS NULL OR category IN (
    'question', 'thought', 'human_task', 'research_task',
    'human_task_result', 'research_task_result'
  ));

-- (b) Add category column to cycles (denormalized from winning proposition)
ALTER TABLE cycles ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE cycles ADD CONSTRAINT cycles_category_check
  CHECK (category IS NULL OR category IN (
    'question', 'thought', 'human_task', 'research_task',
    'human_task_result', 'research_task_result'
  ));

-- (c) State machine function: returns allowed categories given previous category
CREATE OR REPLACE FUNCTION get_allowed_categories(p_previous_category TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  CASE p_previous_category
    WHEN 'question' THEN RETURN ARRAY['question','thought','human_task','research_task'];
    WHEN 'thought' THEN RETURN ARRAY['question'];
    WHEN 'human_task' THEN RETURN ARRAY['human_task_result'];
    WHEN 'human_task_result' THEN RETURN ARRAY['question'];
    WHEN 'research_task' THEN RETURN ARRAY['question','thought','human_task','research_task'];
    WHEN 'research_task_result' THEN RETURN ARRAY['question']; -- legacy: kept for backward compat
    ELSE RETURN ARRAY['question','thought','human_task','research_task']; -- NULL/legacy
  END CASE;
END; $$;

-- (d) RPC: get allowed categories for a specific chat (looks up last completed cycle)
CREATE OR REPLACE FUNCTION get_chat_allowed_categories(p_chat_id BIGINT DEFAULT NULL)
RETURNS TEXT[]
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_prev_category TEXT;
BEGIN
  IF p_chat_id IS NOT NULL THEN
    -- Get the category from the last completed cycle for this chat
    SELECT category INTO v_prev_category
    FROM cycles
    WHERE chat_id = p_chat_id
      AND completed_at IS NOT NULL
    ORDER BY completed_at DESC
    LIMIT 1;
  ELSE
    -- Global fallback: last completed cycle overall
    SELECT category INTO v_prev_category
    FROM cycles
    WHERE completed_at IS NOT NULL
    ORDER BY completed_at DESC
    LIMIT 1;
  END IF;

  RETURN get_allowed_categories(v_prev_category);
END; $$;

-- Security: revoke from public, grant to authenticated and service_role
REVOKE EXECUTE ON FUNCTION get_chat_allowed_categories(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_chat_allowed_categories(BIGINT) TO authenticated, service_role;

-- (e) Update on_round_winner_set() to copy category during carry-forward
--     and to set category on cycle when consensus is reached
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
    new_prop_id BIGINT;
    v_winner_category TEXT;
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

        -- Get the winning proposition's category for denormalization onto cycle
        SELECT category INTO v_winner_category
        FROM propositions
        WHERE id = NEW.winning_proposition_id;

        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW(),
            category = v_winner_category
        WHERE id = v_cycle_id;
    ELSE
        -- Need more rounds, create next one using the helper function
        -- This properly handles auto-start conditions
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

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Restore SECURITY DEFINER (was set in 20260118100000)
ALTER FUNCTION on_round_winner_set() SECURITY DEFINER;

COMMENT ON FUNCTION on_round_winner_set() IS
  'Handles round completion: tracks consensus, creates next round, carries forward winners with translations and category. '
  'Copies category from winning proposition to cycle on consensus. Uses SECURITY DEFINER.';

-- (f) Update host_force_consensus to accept optional p_category parameter
--     and allow service_role to skip host check (for auto-forcing research results)
DROP FUNCTION IF EXISTS host_force_consensus(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION host_force_consensus(
    p_chat_id BIGINT,
    p_content TEXT,
    p_category TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_is_host BOOLEAN;
  v_participant_id BIGINT;
  v_current_cycle_id BIGINT;
  v_current_round_id BIGINT;
  v_proposition_id BIGINT;
  v_allowed TEXT[];
  v_is_service_role BOOLEAN;
  v_effective_category TEXT;
BEGIN
  -- Detect if caller is service_role
  v_is_service_role := current_setting('role', true) = 'service_role'
                    OR current_setting('request.jwt.claim.role', true) = 'service_role';

  IF v_is_service_role THEN
    -- Service role: find any active participant to use as author (prefer host)
    SELECT id INTO v_participant_id
    FROM participants
    WHERE chat_id = p_chat_id AND status = 'active'
    ORDER BY is_host DESC
    LIMIT 1;

    IF v_participant_id IS NULL THEN
      RAISE EXCEPTION 'No active participants in chat';
    END IF;
  ELSE
    -- Regular user: verify authentication and host status
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT id, is_host INTO v_participant_id, v_is_host
    FROM participants
    WHERE chat_id = p_chat_id
      AND user_id = v_caller_id
      AND status = 'active';

    IF v_is_host IS NOT TRUE THEN
      RAISE EXCEPTION 'Only the host can force a consensus';
    END IF;
  END IF;

  -- Validate content
  IF p_content IS NULL OR TRIM(p_content) = '' THEN
    RAISE EXCEPTION 'Content cannot be empty';
  END IF;

  -- Get allowed categories for this chat
  v_allowed := get_chat_allowed_categories(p_chat_id);

  IF p_category IS NOT NULL THEN
    -- Explicit category: validate against allowed
    IF NOT (p_category = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'Category "%" not allowed. Allowed: %', p_category, v_allowed;
    END IF;
    v_effective_category := p_category;
  ELSE
    -- No category provided: auto-detect if only one is allowed
    IF array_length(v_allowed, 1) = 1 THEN
      v_effective_category := v_allowed[1];
    ELSE
      v_effective_category := NULL;
    END IF;
  END IF;

  -- Find the current (incomplete) cycle for this chat
  SELECT id INTO v_current_cycle_id
  FROM cycles
  WHERE chat_id = p_chat_id
    AND completed_at IS NULL
  ORDER BY id DESC
  LIMIT 1;

  IF v_current_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No active cycle found for this chat';
  END IF;

  -- Find the current round in this cycle
  SELECT id INTO v_current_round_id
  FROM rounds
  WHERE cycle_id = v_current_cycle_id
  ORDER BY id DESC
  LIMIT 1;

  IF v_current_round_id IS NULL THEN
    RAISE EXCEPTION 'No active round found for this cycle';
  END IF;

  -- Create a proposition with the host's content in the current round
  INSERT INTO propositions (round_id, participant_id, content, category)
  VALUES (v_current_round_id, v_participant_id, TRIM(p_content), v_effective_category)
  RETURNING id INTO v_proposition_id;

  -- Mark ALL rounds in this cycle as completed so timer queries don't pick them up
  UPDATE rounds
  SET completed_at = NOW()
  WHERE cycle_id = v_current_cycle_id AND completed_at IS NULL;

  -- Set this proposition as the cycle winner and mark completed
  -- The on_cycle_winner_set trigger will auto-create next cycle + round
  -- The on_round_winner_set trigger won't fire here because we update cycles directly
  UPDATE cycles
  SET winning_proposition_id = v_proposition_id,
      completed_at = NOW(),
      host_override = TRUE,
      category = v_effective_category
  WHERE id = v_current_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_current_cycle_id,
    'proposition_id', v_proposition_id,
    'category', v_effective_category
  );
END;
$$;

COMMENT ON FUNCTION host_force_consensus(BIGINT, TEXT, TEXT) IS
  'Force a consensus by creating a proposition and setting it as cycle winner. '
  'Host-only for regular users; service_role can call directly (for auto-forcing research results). '
  'Validates category against the state machine when provided.';

-- Security grants for new 3-param signature
REVOKE EXECUTE ON FUNCTION host_force_consensus(BIGINT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION host_force_consensus(BIGINT, TEXT, TEXT) TO authenticated, service_role;

-- (g) Update delete_consensus to also clear category
CREATE OR REPLACE FUNCTION delete_consensus(p_cycle_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_chat_id BIGINT;
  v_is_host BOOLEAN;
  v_latest_completed_cycle_id BIGINT;
  v_was_latest BOOLEAN := FALSE;
  v_new_round_id BIGINT;
  v_restarted BOOLEAN := FALSE;
BEGIN
  -- Verify caller is authenticated
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Get cycle's chat_id
  SELECT chat_id INTO v_chat_id
  FROM cycles
  WHERE id = p_cycle_id;

  IF v_chat_id IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  -- Verify caller is host
  SELECT is_host INTO v_is_host
  FROM participants
  WHERE chat_id = v_chat_id
    AND user_id = v_caller_id
    AND status = 'active';

  IF v_is_host IS NOT TRUE THEN
    RAISE EXCEPTION 'Only the host can delete a consensus';
  END IF;

  -- Check if this is the latest completed cycle BEFORE clearing it
  SELECT id INTO v_latest_completed_cycle_id
  FROM cycles
  WHERE chat_id = v_chat_id
    AND completed_at IS NOT NULL
  ORDER BY completed_at DESC
  LIMIT 1;

  -- Only allow deleting the latest completed cycle
  IF v_latest_completed_cycle_id IS NULL OR v_latest_completed_cycle_id != p_cycle_id THEN
    RAISE EXCEPTION 'Only the latest consensus can be deleted';
  END IF;

  v_was_latest := TRUE;

  -- Clear the cycle's winning proposition, completion, task_result, and category
  UPDATE cycles
  SET winning_proposition_id = NULL,
      completed_at = NULL,
      task_result = NULL,
      category = NULL
  WHERE id = p_cycle_id;

  -- Delete all rounds in this cycle (CASCADE handles propositions, grid_rankings,
  -- round_winners, round_skips, rating_skips)
  DELETE FROM rounds WHERE cycle_id = p_cycle_id;

  -- Clean up subsequent incomplete cycles and restart
  DELETE FROM rounds WHERE cycle_id IN (
    SELECT id FROM cycles
    WHERE chat_id = v_chat_id AND id > p_cycle_id AND completed_at IS NULL
  );
  DELETE FROM cycles
  WHERE chat_id = v_chat_id AND id > p_cycle_id AND completed_at IS NULL;

  -- Create a fresh round for this cycle
  v_new_round_id := create_round_for_cycle(p_cycle_id, v_chat_id, 1);
  v_restarted := TRUE;

  RETURN jsonb_build_object(
    'restarted', v_restarted,
    'new_round_id', v_new_round_id
  );
END;
$$;

COMMENT ON FUNCTION delete_consensus(BIGINT) IS
  'Deletes the latest consensus by clearing cycle winner, task_result, category, and removing all rounds. '
  'Only the latest completed cycle can be deleted. Cleans up subsequent incomplete '
  'cycles and restarts with a fresh round.';
