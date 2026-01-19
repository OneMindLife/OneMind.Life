-- =============================================================================
-- TEST: Approve Join Request Function
-- =============================================================================
-- Tests for the approve_join_request RPC function that allows hosts to
-- approve join requests while bypassing RLS.
-- Updated to use auth.uid() instead of session tokens.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

-- Create test auth users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'host@test.com', 'pass', NOW(), NOW(), NOW()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'requester1@test.com', 'pass', NOW(), NOW(), NOW()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID, 'requester2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd'::UUID, 'nonhost@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
  v_chat_id INT;
  v_host_id INT;
  v_host_user_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_requester1_user_id UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
BEGIN
  -- Create test chat with require_approval (using creator_session_token for compatibility)
  INSERT INTO chats (name, initial_message, creator_session_token, require_approval)
  VALUES ('Approval Test Chat', 'Testing approval', v_host_user_id, TRUE)
  RETURNING id INTO v_chat_id;

  -- Create host participant with user_id
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, v_host_user_id, 'Host', TRUE, 'active')
  RETURNING id INTO v_host_id;

  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.host_id', v_host_id::TEXT, TRUE);
  PERFORM set_config('test.host_user_id', v_host_user_id::TEXT, TRUE);
  PERFORM set_config('test.requester1_user_id', v_requester1_user_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST: Function exists
-- =============================================================================

-- Test 1: approve_join_request function exists
SELECT has_function('public', 'approve_join_request',
    'approve_join_request function should exist');

-- =============================================================================
-- TEST: Successful approval flow
-- =============================================================================

-- Create a pending join request with user_id
INSERT INTO join_requests (chat_id, user_id, display_name, is_authenticated, status)
VALUES (current_setting('test.chat_id')::INT, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'Requester1', TRUE, 'pending');

DO $$
DECLARE
  v_request_id INT;
BEGIN
  SELECT id INTO v_request_id FROM join_requests
  WHERE display_name = 'Requester1' AND status = 'pending';
  PERFORM set_config('test.request_id', v_request_id::TEXT, TRUE);
END $$;

-- Test 2: Join request exists before approval
SELECT is(
  (SELECT COUNT(*) FROM join_requests WHERE id = current_setting('test.request_id')::INT AND status = 'pending'),
  1::BIGINT,
  'Join request should exist with pending status'
);

-- Test 3: No participant exists before approval
SELECT is(
  (SELECT COUNT(*) FROM participants WHERE user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID AND NOT is_host),
  0::BIGINT,
  'No participant should exist before approval'
);

-- Set auth context to host user (simulates auth.uid() returning host)
SELECT set_config('request.jwt.claims', '{"sub": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', TRUE);

-- Test 4: Approve function succeeds
SELECT lives_ok(
  format('SELECT approve_join_request(%s)', current_setting('test.request_id')::INT),
  'approve_join_request should succeed for host'
);

-- Test 5: Join request status updated to approved
SELECT is(
  (SELECT status FROM join_requests WHERE id = current_setting('test.request_id')::INT),
  'approved',
  'Join request status should be approved'
);

-- Test 6: resolved_at is set
SELECT isnt(
  (SELECT resolved_at FROM join_requests WHERE id = current_setting('test.request_id')::INT),
  NULL,
  'resolved_at should be set after approval'
);

-- Test 7: Participant created
SELECT is(
  (SELECT COUNT(*) FROM participants WHERE user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID AND status = 'active' AND NOT is_host),
  1::BIGINT,
  'Participant should be created with active status'
);

-- Test 8: Participant has correct display_name
SELECT is(
  (SELECT display_name FROM participants WHERE user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID AND NOT is_host),
  'Requester1',
  'Participant should have correct display_name'
);

-- Test 9: Participant is not host
SELECT is(
  (SELECT is_host FROM participants WHERE user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID AND NOT is_host),
  FALSE,
  'Approved participant should not be host'
);

-- =============================================================================
-- TEST: Error cases
-- =============================================================================

-- Test 10: Cannot approve already approved request
SELECT throws_ok(
  format('SELECT approve_join_request(%s)', current_setting('test.request_id')::INT),
  'Join request not found or already processed',
  'Should fail to approve already approved request'
);

-- Create another pending request for non-host test
INSERT INTO join_requests (chat_id, user_id, display_name, is_authenticated, status)
VALUES (current_setting('test.chat_id')::INT, 'cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID, 'Requester2', TRUE, 'pending');

DO $$
DECLARE
  v_request_id INT;
BEGIN
  SELECT id INTO v_request_id FROM join_requests
  WHERE display_name = 'Requester2' AND status = 'pending';
  PERFORM set_config('test.request2_id', v_request_id::TEXT, TRUE);
END $$;

-- Switch to non-host auth context
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', TRUE);

-- Test 11: Non-host cannot approve
SELECT throws_ok(
  format('SELECT approve_join_request(%s)', current_setting('test.request2_id')::INT),
  'Only the host can approve join requests',
  'Non-host should not be able to approve requests'
);

-- Test 12: Cannot approve non-existent request
SELECT throws_ok(
  'SELECT approve_join_request(99999)',
  'Join request not found or already processed',
  'Should fail for non-existent request'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
