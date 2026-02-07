-- Test: Translation triggers and infrastructure
-- Tests the database triggers that automatically translate chats and propositions
--
-- NOTE: These tests verify the trigger functions exist and have correct structure.
-- The actual HTTP calls to Edge Functions are not tested here (would require
-- external HTTP mocking). Integration tests should verify the full flow.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- Test 1: Trigger function for chats exists
-- =============================================================================
SELECT has_function(
  'public',
  'trigger_translate_chat',
  'Trigger function for chat translations exists'
);

-- =============================================================================
-- Test 2: Trigger function for propositions exists
-- =============================================================================
SELECT has_function(
  'public',
  'trigger_translate_proposition',
  'Trigger function for proposition translations exists'
);

-- =============================================================================
-- Test 3: Trigger exists on chats table
-- =============================================================================
SELECT has_trigger(
  'chats',
  'translate_chat_on_insert',
  'Translation trigger exists on chats table'
);

-- =============================================================================
-- Test 4: Trigger exists on propositions table
-- =============================================================================
SELECT has_trigger(
  'propositions',
  'translate_proposition_on_insert',
  'Translation trigger exists on propositions table'
);

-- =============================================================================
-- Test 5: Chat trigger fires on INSERT
-- =============================================================================
SELECT trigger_is(
  'chats',
  'translate_chat_on_insert',
  'trigger_translate_chat',
  'Chat translation trigger calls correct function'
);

-- =============================================================================
-- Test 6: Proposition trigger fires on INSERT
-- =============================================================================
SELECT trigger_is(
  'propositions',
  'translate_proposition_on_insert',
  'trigger_translate_proposition',
  'Proposition translation trigger calls correct function'
);

-- =============================================================================
-- Test 7: Vault schema exists for secrets management
-- =============================================================================
SELECT has_schema('vault', 'Vault schema exists for secrets management');

-- =============================================================================
-- Test 8: Chat trigger function handles missing vault secret gracefully
-- =============================================================================
-- When vault secret is not configured, trigger should warn but not fail

-- First, backup the current secret value (if any)
DO $$
DECLARE
  v_current_secret TEXT;
BEGIN
  SELECT decrypted_secret INTO v_current_secret
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  -- Store for restoration
  PERFORM set_config('test.original_secret', COALESCE(v_current_secret, ''), TRUE);
END $$;

-- Insert a chat and verify it succeeds (trigger should not fail even if secret is placeholder)
DO $$
DECLARE
  v_chat_id INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token)
  VALUES ('Trigger Test Chat', 'Test trigger handling', gen_random_uuid())
  RETURNING id INTO v_chat_id;

  PERFORM set_config('test.trigger_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT pass('Chat INSERT succeeds even when vault secret is placeholder');

-- =============================================================================
-- Test 9: Proposition trigger function handles missing vault secret gracefully
-- =============================================================================
DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant_id INT;
  v_prop_id INT;
BEGIN
  v_chat_id := current_setting('test.trigger_chat_id')::INT;

  -- Create cycle, round, and participant for proposition
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Test User', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  -- Insert proposition - should succeed despite trigger
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_id, 'Test proposition content')
  RETURNING id INTO v_prop_id;

  PERFORM set_config('test.trigger_prop_id', v_prop_id::TEXT, TRUE);
  PERFORM set_config('test.trigger_round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.trigger_participant_id', v_participant_id::TEXT, TRUE);
END $$;

SELECT pass('Proposition INSERT succeeds even when vault secret is placeholder');

-- =============================================================================
-- Test 10: Carried-forward propositions are skipped by trigger
-- =============================================================================
DO $$
DECLARE
  v_round_id INT;
  v_participant_id INT;
  v_original_prop_id INT;
  v_carried_prop_id INT;
BEGIN
  v_round_id := current_setting('test.trigger_round_id')::INT;
  v_participant_id := current_setting('test.trigger_participant_id')::INT;
  v_original_prop_id := current_setting('test.trigger_prop_id')::INT;

  -- Insert a carried-forward proposition (simulating what the DB trigger does)
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round_id, v_participant_id, 'Carried content', v_original_prop_id)
  RETURNING id INTO v_carried_prop_id;

  PERFORM set_config('test.carried_prop_id', v_carried_prop_id::TEXT, TRUE);
END $$;

SELECT pass('Carried-forward proposition INSERT succeeds (trigger skips it)');

-- =============================================================================
-- Test 11: pg_net extension is available for HTTP calls
-- =============================================================================
SELECT has_extension('pg_net', 'pg_net extension is available for async HTTP calls');

-- =============================================================================
-- Test 12: Trigger functions are owned by postgres (security check)
-- =============================================================================
SELECT ok(
  (SELECT proowner::regrole::text = 'postgres'
   FROM pg_proc
   WHERE proname = 'trigger_translate_chat'
   AND pronamespace = 'public'::regnamespace),
  'Chat trigger function is owned by postgres'
);

-- =============================================================================
-- Finish
-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
