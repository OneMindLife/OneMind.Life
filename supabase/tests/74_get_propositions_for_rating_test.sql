-- Tests for get_propositions_for_rating RPC
-- This function bypasses per-row RLS evaluation for better concurrency.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- =============================================================================
-- SETUP
-- =============================================================================

-- Create test users in auth.users
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000a01'::uuid, 'authenticated', 'rpc_test1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000a02'::uuid, 'authenticated', 'rpc_test2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000a03'::uuid, 'authenticated', 'rpc_test3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

-- Create chat
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('RPC Test Chat', 'Test propositions RPC', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1 INT;
  v_p2 INT;
  v_p3 INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'RPC Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

  -- Create cycle and round
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);

  -- Create participants (with user_id for auth.uid() matching)
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000a01'::uuid, 'User 1', FALSE, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000a02'::uuid, 'User 2', FALSE, 'active')
  RETURNING id INTO v_p2;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000a03'::uuid, 'User 3', FALSE, 'active')
  RETURNING id INTO v_p3;

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);

  -- Create propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES
    (v_round_id, v_p1, 'Proposition from user 1'),
    (v_round_id, v_p2, 'Proposition from user 2'),
    (v_round_id, v_p3, 'Proposition from user 3');
END $$;

-- =============================================================================
-- Test 1: Function exists
-- =============================================================================
SELECT has_function('public', 'get_propositions_for_rating', ARRAY['bigint', 'bigint'],
  'get_propositions_for_rating(bigint, bigint) function exists');

-- =============================================================================
-- Test 2: Function is SECURITY DEFINER
-- =============================================================================
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'get_propositions_for_rating'),
  TRUE,
  'get_propositions_for_rating is SECURITY DEFINER'
);

-- =============================================================================
-- Test 3: Returns propositions excluding caller's own (as user 1)
-- =============================================================================
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000a01';

SELECT is(
  (SELECT count(*)::int FROM get_propositions_for_rating(
    current_setting('test.round_id')::bigint,
    current_setting('test.p1')::bigint
  )),
  2,
  'User 1 sees 2 propositions (excludes own)'
);

-- =============================================================================
-- Test 4: Correct propositions returned (user 1 should NOT see own)
-- =============================================================================
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM get_propositions_for_rating(
      current_setting('test.round_id')::bigint,
      current_setting('test.p1')::bigint
    )
    WHERE participant_id = current_setting('test.p1')::bigint
  ),
  'User 1 does not see own proposition in results'
);

-- =============================================================================
-- Test 5: Returns propositions excluding caller's own (as user 2)
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000a02';

SELECT is(
  (SELECT count(*)::int FROM get_propositions_for_rating(
    current_setting('test.round_id')::bigint,
    current_setting('test.p2')::bigint
  )),
  2,
  'User 2 sees 2 propositions (excludes own)'
);

-- =============================================================================
-- Test 6: Non-participant cannot access propositions
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000999';

SELECT throws_ok(
  format(
    $$SELECT * FROM get_propositions_for_rating(%s::bigint, 9999::bigint)$$,
    current_setting('test.round_id')
  ),
  'P0001',
  'Not a participant in this chat',
  'Non-participant gets rejected'
);

-- =============================================================================
-- Test 7: Invalid round_id returns error
-- =============================================================================
SELECT throws_ok(
  $$SELECT * FROM get_propositions_for_rating(999999::bigint, 1::bigint)$$,
  'P0001',
  'Not a participant in this chat',
  'Invalid round_id raises exception'
);

-- =============================================================================
-- Test 8: Returns correct content
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000a01';

SELECT ok(
  EXISTS (
    SELECT 1 FROM get_propositions_for_rating(
      current_setting('test.round_id')::bigint,
      current_setting('test.p1')::bigint
    )
    WHERE content = 'Proposition from user 2'
  ),
  'Result includes proposition from user 2 with correct content'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
