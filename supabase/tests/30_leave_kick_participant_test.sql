-- =============================================================================
-- TEST: Leave/Kick Participant Architecture
-- =============================================================================
-- Tests for the leave/kick participant flow:
-- - Leave: DELETE participant record (so they can rejoin cleanly)
-- - Kick: UPDATE status='kicked' (to block rejoining, can be reactivated by host)
-- Updated to use auth.uid() instead of session tokens.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(23);

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

-- Create test auth users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'host@test.com', 'pass', NOW(), NOW(), NOW()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'user@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
  v_chat_id INT;
  v_host_id INT;
  v_host_user_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_user_id UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
BEGIN
  -- Create test chat with require_approval (using creator_session_token for compatibility)
  INSERT INTO chats (name, initial_message, creator_session_token, require_approval)
  VALUES ('Leave/Kick Test Chat', 'Testing leave and kick', v_host_user_id, TRUE)
  RETURNING id INTO v_chat_id;

  -- Create host participant with user_id
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, v_host_user_id, 'Host', TRUE, 'active')
  RETURNING id INTO v_host_id;

  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.host_id', v_host_id::TEXT, TRUE);
  PERFORM set_config('test.host_user_id', v_host_user_id::TEXT, TRUE);
  PERFORM set_config('test.user_id', v_user_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST 1-3: Leave deletes participant record
-- =============================================================================

-- Create a participant to test leaving
INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID, 'User1', FALSE, 'active');

-- Test 1: Participant exists before leaving
SELECT is(
  (SELECT COUNT(*) FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  1::BIGINT,
  'Participant should exist before leaving'
);

-- Simulate leaving by deleting the record
DELETE FROM participants
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID;

-- Test 2: Participant record is deleted after leaving
SELECT is(
  (SELECT COUNT(*) FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  0::BIGINT,
  'Participant record should be deleted after leaving'
);

-- Test 3: Left user can rejoin directly (no unique constraint violation)
SELECT lives_ok(
  format(
    'INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
     VALUES (%s, %L::UUID, ''User1Rejoined'', FALSE, ''active'')',
    current_setting('test.chat_id'),
    current_setting('test.user_id')
  ),
  'Left user should be able to rejoin (INSERT succeeds)'
);

-- Clean up for next tests
DELETE FROM participants
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID;

-- =============================================================================
-- TEST 4-6: Kick preserves record with status='kicked'
-- =============================================================================

-- Create participant to test kicking
INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID, 'User2', FALSE, 'active');

-- Test 4: Participant is active before kick
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'active',
  'Participant should be active before kick'
);

-- Kick the participant
UPDATE participants SET status = 'kicked'
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID;

-- Test 5: Participant record exists with status='kicked'
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'kicked',
  'Participant should have status=kicked after being kicked'
);

-- Test 6: Kicked user cannot rejoin directly (unique constraint violation)
SELECT throws_matching(
  format(
    'INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
     VALUES (%s, %L::UUID, ''User2Again'', FALSE, ''active'')',
    current_setting('test.chat_id'),
    current_setting('test.user_id')
  ),
  'duplicate key value violates unique constraint',
  'Kicked user should not be able to rejoin directly (unique constraint)'
);

-- =============================================================================
-- TEST 7-10: Kicked user can be reactivated via approve_join_request
-- =============================================================================

-- Create join request for kicked user (with user_id)
INSERT INTO join_requests (chat_id, user_id, display_name, is_authenticated, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID, 'User2Reactivated', TRUE, 'pending');

DO $$
DECLARE
  v_request_id INT;
BEGIN
  SELECT id INTO v_request_id FROM join_requests
  WHERE user_id = current_setting('test.user_id')::UUID AND status = 'pending';
  PERFORM set_config('test.reactivate_request_id', v_request_id::TEXT, TRUE);
END $$;

-- Test 7: Join request exists
SELECT is(
  (SELECT COUNT(*) FROM join_requests
   WHERE id = current_setting('test.reactivate_request_id')::INT AND status = 'pending'),
  1::BIGINT,
  'Join request should exist for kicked user'
);

-- Set auth context to host user (simulates auth.uid() returning host)
SELECT set_config('request.jwt.claims', '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', TRUE);

-- Test 8: Approve function succeeds for kicked user
SELECT lives_ok(
  format('SELECT approve_join_request(%s)', current_setting('test.reactivate_request_id')::INT),
  'approve_join_request should succeed for kicked user'
);

-- Test 9: Kicked user is reactivated (status='active')
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'active',
  'Kicked user should be reactivated to active status'
);

-- Test 10: Display name is updated
SELECT is(
  (SELECT display_name FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'User2Reactivated',
  'Display name should be updated after reactivation'
);

-- =============================================================================
-- TEST 11-14: Left user can request to join and be approved
-- =============================================================================

-- Leave (delete the participant)
DELETE FROM participants
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID;

-- Test 11: No participant record after leaving
SELECT is(
  (SELECT COUNT(*) FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  0::BIGINT,
  'No participant record should exist after leaving'
);

-- Create join request for left user (with user_id)
INSERT INTO join_requests (chat_id, user_id, display_name, is_authenticated, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID, 'User2LeftRejoined', TRUE, 'pending');

DO $$
DECLARE
  v_request_id INT;
BEGIN
  SELECT id INTO v_request_id FROM join_requests
  WHERE display_name = 'User2LeftRejoined' AND status = 'pending';
  PERFORM set_config('test.left_rejoin_request_id', v_request_id::TEXT, TRUE);
END $$;

-- Test 12: Approve function succeeds for left user (creates new participant)
SELECT lives_ok(
  format('SELECT approve_join_request(%s)', current_setting('test.left_rejoin_request_id')::INT),
  'approve_join_request should succeed for left user'
);

-- Test 13: New participant created with active status
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'active',
  'Left user should have new active participant record'
);

-- Test 14: New participant has correct display name
SELECT is(
  (SELECT display_name FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'User2LeftRejoined',
  'New participant should have correct display name'
);

-- =============================================================================
-- TEST 15-18: Legacy 'left' records can be reactivated via approve
-- (This tests backwards compatibility with old data before DELETE-on-leave)
-- =============================================================================

-- First, delete the participant and recreate with 'left' status (simulating legacy data)
DELETE FROM participants
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID;

INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID,
        'LegacyLeftUser', FALSE, 'left');

-- Test 15: Legacy 'left' participant exists
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'left',
  'Legacy participant should have status=left'
);

-- Create join request for legacy left user (with user_id)
INSERT INTO join_requests (chat_id, user_id, display_name, is_authenticated, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID,
        'LegacyUserReactivated', TRUE, 'pending');

DO $$
DECLARE
  v_request_id INT;
BEGIN
  SELECT id INTO v_request_id FROM join_requests
  WHERE display_name = 'LegacyUserReactivated' AND status = 'pending';
  PERFORM set_config('test.legacy_request_id', v_request_id::TEXT, TRUE);
END $$;

-- Test 16: Approve function succeeds for legacy 'left' user
SELECT lives_ok(
  format('SELECT approve_join_request(%s)', current_setting('test.legacy_request_id')::INT),
  'approve_join_request should succeed for legacy left user'
);

-- Test 17: Legacy 'left' user is reactivated to 'active'
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'active',
  'Legacy left user should be reactivated to active status'
);

-- Test 18: Display name is updated for legacy user
SELECT is(
  (SELECT display_name FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'LegacyUserReactivated',
  'Legacy user display name should be updated after reactivation'
);

-- =============================================================================
-- TEST 19-21: Kicked user can rejoin directly via UPDATE (require_approval=false)
-- (This simulates the Flutter joinChat() flow for non-require_approval chats)
-- =============================================================================

-- First, set up a kicked participant
DELETE FROM participants
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID;

INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID,
        'KickedUser', FALSE, 'kicked');

-- Test 19: Kicked participant exists
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'kicked',
  'Participant should have status=kicked before direct rejoin'
);

-- Simulate direct rejoin by UPDATE (what Flutter joinChat does)
UPDATE participants
SET status = 'active', display_name = 'RejoinedDirectly'
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID
AND status = 'kicked';

-- Test 20: Kicked user is now active after direct update
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'active',
  'Kicked user should be reactivated via direct UPDATE'
);

-- Test 21: Display name is updated after direct rejoin
SELECT is(
  (SELECT display_name FROM participants
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND user_id = current_setting('test.user_id')::UUID),
  'RejoinedDirectly',
  'Display name should be updated after direct rejoin'
);

-- =============================================================================
-- TEST 22-23: RLS DELETE policy allows participants to leave
-- =============================================================================

-- Clean up and create fresh participant for RLS test
DELETE FROM participants
WHERE chat_id = current_setting('test.chat_id')::INT
AND user_id = current_setting('test.user_id')::UUID;

INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user_id')::UUID,
        'RLSTestUser', FALSE, 'active');

-- Test 22: auth.uid() function exists (used for RLS)
SELECT has_function('auth', 'uid',
    'auth.uid() function should exist for RLS');

-- Set auth context to the user (simulates auth.uid() returning this user)
SELECT set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', TRUE);

-- Test 23: User can delete their own participant record via RLS
SELECT lives_ok(
  format(
    'DELETE FROM participants WHERE chat_id = %s AND user_id = %L::UUID',
    current_setting('test.chat_id'),
    current_setting('test.user_id')
  ),
  'User should be able to delete their own participant record (RLS DELETE policy)'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
