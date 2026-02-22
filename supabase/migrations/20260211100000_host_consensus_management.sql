-- =============================================================================
-- MIGRATION: Host Consensus Management
-- =============================================================================
-- Allows chat hosts to:
-- 1. Delete consensus messages (reopens cycle, optionally restarts with fresh round)
-- 2. Edit the initial message (re-triggers translations)
-- 3. Delete the initial message
-- When the latest consensus/initial message is deleted, the current cycle is
-- restarted: all rounds are deleted, a fresh round is created, and agents are
-- re-triggered automatically via existing triggers.
-- =============================================================================

-- =============================================================================
-- STEP 1: RPC — delete_consensus(p_cycle_id BIGINT)
-- =============================================================================

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

  -- Clear the cycle's winning proposition and completion
  UPDATE cycles
  SET winning_proposition_id = NULL,
      completed_at = NULL
  WHERE id = p_cycle_id;

  -- Delete all rounds in this cycle (CASCADE handles propositions, grid_rankings,
  -- round_winners, round_skips, rating_skips)
  DELETE FROM rounds WHERE cycle_id = p_cycle_id;

  -- Check if this was the latest completed cycle
  SELECT id INTO v_latest_completed_cycle_id
  FROM cycles
  WHERE chat_id = v_chat_id
    AND completed_at IS NOT NULL
  ORDER BY completed_at DESC
  LIMIT 1;

  -- If no newer completed cycles exist, this was the latest — restart
  IF v_latest_completed_cycle_id IS NULL OR v_latest_completed_cycle_id = p_cycle_id THEN
    -- Create a fresh round (in proposing or waiting phase depending on auto-start)
    v_new_round_id := create_round_for_cycle(p_cycle_id, v_chat_id, 1);
    v_restarted := TRUE;
  END IF;

  RETURN jsonb_build_object(
    'restarted', v_restarted,
    'new_round_id', v_new_round_id
  );
END;
$$;

COMMENT ON FUNCTION delete_consensus(BIGINT) IS
  'Deletes a consensus by clearing cycle winner and removing all rounds. '
  'If this was the latest completed cycle, restarts with a fresh round.';

-- =============================================================================
-- STEP 2: RPC — update_initial_message(p_chat_id BIGINT, p_new_message TEXT)
-- =============================================================================

CREATE OR REPLACE FUNCTION update_initial_message(p_chat_id BIGINT, p_new_message TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_is_host BOOLEAN;
  v_has_completed_cycles BOOLEAN;
  v_current_cycle_id BIGINT;
  v_new_round_id BIGINT;
  v_restarted BOOLEAN := FALSE;
BEGIN
  -- Verify caller is authenticated
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Verify caller is host
  SELECT is_host INTO v_is_host
  FROM participants
  WHERE chat_id = p_chat_id
    AND user_id = v_caller_id
    AND status = 'active';

  IF v_is_host IS NOT TRUE THEN
    RAISE EXCEPTION 'Only the host can update the initial message';
  END IF;

  -- Update the initial message (triggers translate_chat_on_update if changed)
  UPDATE chats
  SET initial_message = p_new_message
  WHERE id = p_chat_id;

  -- Check if any completed cycles exist
  SELECT EXISTS(
    SELECT 1 FROM cycles
    WHERE chat_id = p_chat_id AND completed_at IS NOT NULL
  ) INTO v_has_completed_cycles;

  -- If no completed cycles, initial message IS the latest — restart current cycle
  IF NOT v_has_completed_cycles THEN
    SELECT id INTO v_current_cycle_id
    FROM cycles
    WHERE chat_id = p_chat_id
      AND completed_at IS NULL
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_current_cycle_id IS NOT NULL THEN
      -- Delete all rounds in current cycle
      DELETE FROM rounds WHERE cycle_id = v_current_cycle_id;

      -- Create a fresh round
      v_new_round_id := create_round_for_cycle(v_current_cycle_id, p_chat_id, 1);
      v_restarted := TRUE;
    END IF;
  END IF;

  RETURN jsonb_build_object('restarted', v_restarted);
END;
$$;

COMMENT ON FUNCTION update_initial_message(BIGINT, TEXT) IS
  'Updates the initial message for a chat (host only). '
  'Re-triggers translation. Restarts current cycle if no consensus exists yet.';

-- =============================================================================
-- STEP 3: RPC — delete_initial_message(p_chat_id BIGINT)
-- =============================================================================

CREATE OR REPLACE FUNCTION delete_initial_message(p_chat_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_is_host BOOLEAN;
  v_has_completed_cycles BOOLEAN;
  v_current_cycle_id BIGINT;
  v_new_round_id BIGINT;
  v_restarted BOOLEAN := FALSE;
BEGIN
  -- Verify caller is authenticated
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Verify caller is host
  SELECT is_host INTO v_is_host
  FROM participants
  WHERE chat_id = p_chat_id
    AND user_id = v_caller_id
    AND status = 'active';

  IF v_is_host IS NOT TRUE THEN
    RAISE EXCEPTION 'Only the host can delete the initial message';
  END IF;

  -- Set initial_message to NULL
  UPDATE chats
  SET initial_message = NULL
  WHERE id = p_chat_id;

  -- Delete translations for initial_message
  DELETE FROM translations
  WHERE chat_id = p_chat_id
    AND field_name = 'initial_message';

  -- Check if any completed cycles exist
  SELECT EXISTS(
    SELECT 1 FROM cycles
    WHERE chat_id = p_chat_id AND completed_at IS NOT NULL
  ) INTO v_has_completed_cycles;

  -- If no completed cycles, restart current cycle
  IF NOT v_has_completed_cycles THEN
    SELECT id INTO v_current_cycle_id
    FROM cycles
    WHERE chat_id = p_chat_id
      AND completed_at IS NULL
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_current_cycle_id IS NOT NULL THEN
      DELETE FROM rounds WHERE cycle_id = v_current_cycle_id;
      v_new_round_id := create_round_for_cycle(v_current_cycle_id, p_chat_id, 1);
      v_restarted := TRUE;
    END IF;
  END IF;

  RETURN jsonb_build_object('restarted', v_restarted);
END;
$$;

COMMENT ON FUNCTION delete_initial_message(BIGINT) IS
  'Deletes the initial message for a chat (host only). '
  'Removes translations and restarts current cycle if no consensus exists yet.';

-- =============================================================================
-- STEP 4: Trigger function — translate on initial_message UPDATE
-- =============================================================================

CREATE OR REPLACE FUNCTION trigger_translate_chat_on_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
BEGIN
  -- Only fire when initial_message actually changed
  IF OLD.initial_message IS NOT DISTINCT FROM NEW.initial_message THEN
    RETURN NEW;
  END IF;

  -- Delete stale translations for initial_message
  DELETE FROM translations
  WHERE chat_id = NEW.id
    AND field_name = 'initial_message';

  -- If new message is NULL or empty, nothing to translate
  IF NEW.initial_message IS NULL OR NEW.initial_message = '' THEN
    RETURN NEW;
  END IF;

  -- Get service role key from vault
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'Translation skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  -- Build Edge Function URL using vault-based helper
  v_url := get_edge_function_url('translate');

  -- Build request body — only translate the changed initial_message
  v_body := jsonb_build_object(
    'chat_id', NEW.id,
    'texts', jsonb_build_array(
      jsonb_build_object('text', NEW.initial_message, 'field_name', 'initial_message')
    )
  );

  -- Call Edge Function via pg_net (async, non-blocking)
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body
  ) INTO v_request_id;

  RAISE LOG 'Translation requested for chat % initial_message update (request_id: %)', NEW.id, v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Translation trigger error for chat % on update: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trigger_translate_chat_on_update() IS
  'Trigger function that re-translates the initial_message when it is updated. '
  'Deletes stale translations before requesting new ones via the translate Edge Function.';

-- Attach trigger to chats table
DROP TRIGGER IF EXISTS translate_chat_on_update ON chats;

CREATE TRIGGER translate_chat_on_update
  AFTER UPDATE OF initial_message ON chats
  FOR EACH ROW
  EXECUTE FUNCTION trigger_translate_chat_on_update();

-- =============================================================================
-- STEP 5: Security — restrict function access
-- =============================================================================

REVOKE EXECUTE ON FUNCTION delete_consensus(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_consensus(BIGINT) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION update_initial_message(BIGINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_initial_message(BIGINT, TEXT) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION delete_initial_message(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_initial_message(BIGINT) TO authenticated, service_role;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
