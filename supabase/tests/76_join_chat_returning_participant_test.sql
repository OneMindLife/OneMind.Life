-- Tests for join_chat_returning_participant RPC
-- This function bypasses per-row RLS evaluation for better concurrency.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

-- =============================================================================
-- SETUP
-- =============================================================================

-- Create test users in auth.users
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000c01'::uuid, 'authenticated', 'join_test1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000c02'::uuid, 'authenticated', 'join_test2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000c03'::uuid, 'authenticated', 'join_test3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

-- Create a public chat
INSERT INTO chats (name, initial_message, creator_session_token, access_method, is_active)
VALUES ('Join RPC Test Chat', 'Test join RPC', gen_random_uuid(), 'public', true);

-- Create an invite-only chat
INSERT INTO chats (name, initial_message, creator_session_token, access_method, is_active)
VALUES ('Private RPC Test Chat', 'Test private', gen_random_uuid(), 'invite_only', true);

-- Create an inactive chat
INSERT INTO chats (name, initial_message, creator_session_token, access_method, is_active)
VALUES ('Inactive RPC Test Chat', 'Test inactive', gen_random_uuid(), 'public', false);

DO $$
DECLARE
  v_public_chat_id INT;
  v_private_chat_id INT;
  v_inactive_chat_id INT;
BEGIN
  SELECT id INTO v_public_chat_id FROM chats WHERE name = 'Join RPC Test Chat';
  SELECT id INTO v_private_chat_id FROM chats WHERE name = 'Private RPC Test Chat';
  SELECT id INTO v_inactive_chat_id FROM chats WHERE name = 'Inactive RPC Test Chat';

  PERFORM set_config('test.public_chat_id', v_public_chat_id::TEXT, TRUE);
  PERFORM set_config('test.private_chat_id', v_private_chat_id::TEXT, TRUE);
  PERFORM set_config('test.inactive_chat_id', v_inactive_chat_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: Function exists
-- =============================================================================
SELECT has_function('public', 'join_chat_returning_participant', ARRAY['bigint', 'text'],
  'join_chat_returning_participant(bigint, text) function exists');

-- =============================================================================
-- Test 2: Function is SECURITY DEFINER
-- =============================================================================
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'join_chat_returning_participant'),
  TRUE,
  'join_chat_returning_participant is SECURITY DEFINER'
);

-- =============================================================================
-- Test 3: User 1 can join a public chat
-- =============================================================================
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000c01';

SELECT lives_ok(
  format(
    $$SELECT * FROM join_chat_returning_participant(%s::bigint, 'Test User 1')$$,
    current_setting('test.public_chat_id')
  ),
  'User 1 can join a public chat'
);

-- =============================================================================
-- Test 4: Returns correct participant data
-- =============================================================================
SELECT is(
  (SELECT display_name FROM join_chat_returning_participant(
    current_setting('test.public_chat_id')::bigint, 'Test User 1'
  )),
  'Test User 1',
  'Returns correct display_name'
);

-- =============================================================================
-- Test 5: Idempotent — calling again returns same participant
-- =============================================================================
SELECT is(
  (SELECT count(*)::int FROM join_chat_returning_participant(
    current_setting('test.public_chat_id')::bigint, 'Test User 1 Updated'
  )),
  1,
  'Idempotent: second call returns exactly one row'
);

-- =============================================================================
-- Test 6: Original display_name preserved on duplicate (ON CONFLICT DO NOTHING)
-- =============================================================================
SELECT is(
  (SELECT p.display_name FROM participants p
   WHERE p.chat_id = current_setting('test.public_chat_id')::bigint
     AND p.user_id = '00000000-0000-0000-0000-000000000c01'::uuid),
  'Test User 1',
  'Original display_name preserved on duplicate call'
);

-- =============================================================================
-- Test 7: User 2 can also join the same public chat
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000c02';

SELECT is(
  (SELECT status FROM join_chat_returning_participant(
    current_setting('test.public_chat_id')::bigint, 'Test User 2'
  )),
  'active',
  'User 2 joins with active status'
);

-- =============================================================================
-- Test 8: Cannot join invite-only chat
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000c03';

SELECT throws_ok(
  format(
    $$SELECT * FROM join_chat_returning_participant(%s::bigint, 'Test User 3')$$,
    current_setting('test.private_chat_id')
  ),
  'P0001',
  'Chat does not allow direct joining',
  'Cannot join invite-only chat'
);

-- =============================================================================
-- Test 9: Cannot join inactive chat
-- =============================================================================
SELECT throws_ok(
  format(
    $$SELECT * FROM join_chat_returning_participant(%s::bigint, 'Test User 3')$$,
    current_setting('test.inactive_chat_id')
  ),
  'P0001',
  'Chat does not allow direct joining',
  'Cannot join inactive chat'
);

-- =============================================================================
-- Test 10: Unauthenticated user cannot join
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '';

SELECT throws_ok(
  format(
    $$SELECT * FROM join_chat_returning_participant(%s::bigint, 'Anon User')$$,
    current_setting('test.public_chat_id')
  ),
  'P0001',
  'Not authenticated',
  'Unauthenticated user gets rejected'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
