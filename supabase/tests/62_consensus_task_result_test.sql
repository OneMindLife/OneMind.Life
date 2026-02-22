BEGIN;
SELECT plan(4);

-- Test 1: task_result column exists on cycles
SELECT has_column('public', 'cycles', 'task_result',
  'cycles table should have task_result column');

-- Test 2: Column is nullable (no NOT NULL constraint)
SELECT col_is_null('public', 'cycles', 'task_result',
  'task_result should be nullable');

-- Test 3: Column type is text
SELECT col_type_is('public', 'cycles', 'task_result', 'text',
  'task_result should be type text');

-- Test 4: Can store and retrieve text values
-- Create a chat and cycle to test with
DO $$
DECLARE
  v_user_id uuid;
  v_chat_id int;
  v_cycle_id int;
  v_result text;
BEGIN
  -- Create a test user
  INSERT INTO auth.users (id, email, role, aud, instance_id)
  VALUES (gen_random_uuid(), 'task_result_test@test.com', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  RETURNING id INTO v_user_id;

  -- Create a chat
  INSERT INTO chats (name, creator_id, access_method)
  VALUES ('Task Result Test Chat', v_user_id, 'code')
  RETURNING id INTO v_chat_id;

  -- Create a cycle with task_result
  INSERT INTO cycles (chat_id, task_result)
  VALUES (v_chat_id, 'Summary: Found 5 DAOs with public emails...')
  RETURNING id INTO v_cycle_id;

  -- Verify we can read it back
  SELECT task_result INTO v_result FROM cycles WHERE id = v_cycle_id;

  -- Use PERFORM with a DO block can't use SELECT for tap, so we store for later
  IF v_result IS DISTINCT FROM 'Summary: Found 5 DAOs with public emails...' THEN
    RAISE EXCEPTION 'task_result value mismatch: got %', v_result;
  END IF;
END;
$$;

SELECT pass('Can store and retrieve task_result text values');

SELECT * FROM finish();
ROLLBACK;
