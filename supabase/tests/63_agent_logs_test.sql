BEGIN;
SELECT plan(12);

-- =============================================================================
-- Test 1-7: Table and column existence
-- =============================================================================

SELECT has_table('public', 'agent_logs', 'agent_logs table should exist');

SELECT has_column('public', 'agent_logs', 'id', 'should have id column');
SELECT has_column('public', 'agent_logs', 'created_at', 'should have created_at column');
SELECT has_column('public', 'agent_logs', 'chat_id', 'should have chat_id column');
SELECT has_column('public', 'agent_logs', 'event_type', 'should have event_type column');
SELECT has_column('public', 'agent_logs', 'level', 'should have level column');
SELECT has_column('public', 'agent_logs', 'metadata', 'should have metadata column');

-- =============================================================================
-- Test 8: RLS is enabled (no policies = service_role only)
-- =============================================================================

SELECT is(
  (SELECT rowsecurity FROM pg_tables WHERE tablename = 'agent_logs' AND schemaname = 'public'),
  true,
  'RLS should be enabled on agent_logs'
);

-- =============================================================================
-- Test 9: Level column check constraint
-- =============================================================================

SELECT col_has_check('public', 'agent_logs', 'level',
  'level column should have CHECK constraint');

-- =============================================================================
-- Test 10: cleanup_agent_logs function exists
-- =============================================================================

SELECT has_function('public', 'cleanup_agent_logs', ARRAY['integer'],
  'cleanup_agent_logs(integer) function should exist');

-- =============================================================================
-- Test 11: Can insert and query logs (as service role in test context)
-- =============================================================================

DO $$
DECLARE
  v_log_id bigint;
  v_event_type text;
BEGIN
  INSERT INTO agent_logs (event_type, level, message, metadata)
  VALUES ('test_event', 'info', 'pgTAP test log entry', '{"test": true}'::jsonb)
  RETURNING id INTO v_log_id;

  SELECT event_type INTO v_event_type FROM agent_logs WHERE id = v_log_id;

  IF v_event_type IS DISTINCT FROM 'test_event' THEN
    RAISE EXCEPTION 'Log entry mismatch: got %', v_event_type;
  END IF;
END;
$$;

SELECT pass('Can insert and query agent_logs entries');

-- =============================================================================
-- Test 12: Can insert log with all scope columns
-- =============================================================================

DO $$
DECLARE
  v_user_id uuid;
  v_chat_id bigint;
  v_cycle_id bigint;
  v_round_id bigint;
  v_log_id bigint;
  v_msg text;
BEGIN
  -- Create test data
  INSERT INTO auth.users (id, email, role, aud, instance_id)
  VALUES (gen_random_uuid(), 'agent_log_test@test.com', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  RETURNING id INTO v_user_id;

  INSERT INTO chats (name, creator_id, access_method)
  VALUES ('Agent Log Test Chat', v_user_id, 'code')
  RETURNING id INTO v_chat_id;

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'waiting') RETURNING id INTO v_round_id;

  -- Insert a fully-scoped log entry
  INSERT INTO agent_logs (chat_id, cycle_id, round_id, persona_name, event_type, level, phase, message, duration_ms, metadata)
  VALUES (v_chat_id, v_cycle_id, v_round_id, 'the_executor', 'propose', 'info', 'proposing', 'Test propose log', 1234, '{"content_length": 150}'::jsonb)
  RETURNING id INTO v_log_id;

  SELECT message INTO v_msg FROM agent_logs WHERE id = v_log_id;

  IF v_msg IS DISTINCT FROM 'Test propose log' THEN
    RAISE EXCEPTION 'Scoped log entry mismatch: got %', v_msg;
  END IF;
END;
$$;

SELECT pass('Can insert fully-scoped agent log entry');

SELECT * FROM finish();
ROLLBACK;
