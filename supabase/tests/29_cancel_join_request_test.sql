-- =============================================================================
-- TEST: Cancel Join Request Function
-- =============================================================================
-- Tests for the cancel_join_request RPC function that allows requesters to
-- cancel their own pending join requests.
-- Updated to use auth.uid() instead of session tokens.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

-- Create test auth users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'host@test.com', 'pass', NOW(), NOW(), NOW()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'requester@test.com', 'pass', NOW(), NOW(), NOW()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID, 'other@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
  v_chat_id INT;
  v_host_id INT;
  v_host_user_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_requester_user_id UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_other_user_id UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
BEGIN
  -- Create test chat with require_approval (using session_token for compatibility)
  INSERT INTO chats (name, initial_message, creator_session_token, require_approval)
  VALUES ('Cancel Test Chat', 'Testing cancel functionality', v_host_user_id, TRUE)
  RETURNING id INTO v_chat_id;

  -- Create host participant with user_id
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, v_host_user_id, 'Host', TRUE, 'active')
  RETURNING id INTO v_host_id;

  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.host_id', v_host_id::TEXT, TRUE);
  PERFORM set_config('test.host_user_id', v_host_user_id::TEXT, TRUE);
  PERFORM set_config('test.requester_user_id', v_requester_user_id::TEXT, TRUE);
  PERFORM set_config('test.other_user_id', v_other_user_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST: Function exists
-- =============================================================================

-- Test 1: cancel_join_request function exists
SELECT has_function('public', 'cancel_join_request',
    'cancel_join_request function should exist');

-- =============================================================================
-- TEST: Successful cancellation flow
-- =============================================================================

-- Create a pending join request with user_id
INSERT INTO join_requests (chat_id, user_id, display_name, is_authenticated, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.requester_user_id')::UUID,
        'Requester1', TRUE, 'pending');

DO $$
DECLARE
  v_request_id INT;
BEGIN
  SELECT id INTO v_request_id FROM join_requests
  WHERE display_name = 'Requester1' AND status = 'pending';
  PERFORM set_config('test.request_id', v_request_id::TEXT, TRUE);
END $$;

-- Test 2: Join request exists before cancellation
SELECT is(
  (SELECT COUNT(*) FROM join_requests WHERE id = current_setting('test.request_id')::INT AND status = 'pending'),
  1::BIGINT,
  'Join request should exist with pending status'
);

-- Set auth context to requester user (simulates auth.uid() returning this user)
SELECT set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', TRUE);

-- Test 3: Cancel function succeeds for own request
SELECT lives_ok(
  format('SELECT cancel_join_request(%s)', current_setting('test.request_id')::INT),
  'Requester should be able to cancel own request'
);

-- Test 4: Join request status updated to cancelled
SELECT is(
  (SELECT status FROM join_requests WHERE id = current_setting('test.request_id')::INT),
  'cancelled',
  'Join request status should be cancelled'
);

-- Test 5: resolved_at is set
SELECT isnt(
  (SELECT resolved_at FROM join_requests WHERE id = current_setting('test.request_id')::INT),
  NULL,
  'resolved_at should be set after cancellation'
);

-- =============================================================================
-- TEST: Error cases
-- =============================================================================

-- Test 6: Cannot cancel already cancelled request
SELECT throws_ok(
  format('SELECT cancel_join_request(%s)', current_setting('test.request_id')::INT),
  'Join request not found or already processed',
  'Should fail to cancel already cancelled request'
);

-- Create another pending request by a different user
INSERT INTO join_requests (chat_id, user_id, display_name, is_authenticated, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.other_user_id')::UUID,
        'OtherRequester', TRUE, 'pending');

DO $$
DECLARE
  v_request_id INT;
BEGIN
  SELECT id INTO v_request_id FROM join_requests
  WHERE display_name = 'OtherRequester' AND status = 'pending';
  PERFORM set_config('test.other_request_id', v_request_id::TEXT, TRUE);
END $$;

-- Test 7: Cannot cancel another user's request (still authenticated as requester)
SELECT throws_ok(
  format('SELECT cancel_join_request(%s)', current_setting('test.other_request_id')::INT),
  'You can only cancel your own join requests',
  'Should not be able to cancel another user''s request'
);

-- Test 8: Cannot cancel non-existent request
SELECT throws_ok(
  'SELECT cancel_join_request(99999)',
  'Join request not found or already processed',
  'Should fail for non-existent request'
);

-- =============================================================================
-- TEST: Status constraint
-- =============================================================================

-- Test 9: Cancelled status is valid in constraint (scoped to test chat)
SELECT is(
  (SELECT COUNT(*) FROM join_requests
   WHERE chat_id = current_setting('test.chat_id')::INT AND status = 'cancelled'),
  1::BIGINT,
  'Cancelled status should be valid'
);

-- Test 10: All expected statuses work (scoped to test chat)
SELECT is(
  (SELECT array_agg(DISTINCT status ORDER BY status) FROM join_requests
   WHERE chat_id = current_setting('test.chat_id')::INT),
  ARRAY['cancelled', 'pending']::TEXT[],
  'Both cancelled and pending statuses should work'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
