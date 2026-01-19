-- Participants and join flow tests
BEGIN;
SET search_path TO public, extensions;
SELECT plan(20);

-- =============================================================================
-- SETUP (Anonymous chats only - no users table dependency)
-- =============================================================================

-- Create chats with various settings using session tokens (anonymous creator)
INSERT INTO chats (name, initial_message, creator_session_token, require_approval)
VALUES ('Approval Chat', 'Need approval to join', gen_random_uuid(), TRUE);

INSERT INTO chats (name, initial_message, creator_session_token, require_approval)
VALUES ('Open Chat', 'Join freely', gen_random_uuid(), FALSE);

INSERT INTO chats (name, initial_message, creator_session_token, require_auth)
VALUES ('Auth Required Chat', 'Must be signed in', gen_random_uuid(), TRUE);

-- Store chat IDs
DO $$
DECLARE
  v_approval_chat INT;
  v_open_chat INT;
  v_auth_chat INT;
BEGIN
  SELECT id INTO v_approval_chat FROM chats WHERE name = 'Approval Chat';
  SELECT id INTO v_open_chat FROM chats WHERE name = 'Open Chat';
  SELECT id INTO v_auth_chat FROM chats WHERE name = 'Auth Required Chat';

  PERFORM set_config('test.approval_chat_id', v_approval_chat::TEXT, TRUE);
  PERFORM set_config('test.open_chat_id', v_open_chat::TEXT, TRUE);
  PERFORM set_config('test.auth_chat_id', v_auth_chat::TEXT, TRUE);
END $$;

-- =============================================================================
-- PARTICIPANT CREATION
-- =============================================================================

-- Test 1: Host joins as anonymous participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.open_chat_id')::INT,
  gen_random_uuid(),
  'Host User',
  TRUE,
  FALSE,
  'active'
);

SELECT is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.open_chat_id')::INT),
  1::bigint,
  'Host participant created'
);

-- Test 2: Host has is_host = TRUE
SELECT is(
  (SELECT is_host FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Host User'),
  TRUE,
  'Host has is_host = TRUE'
);

-- Test 3: Anonymous user joins open chat
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.open_chat_id')::INT,
  gen_random_uuid(),
  'Anonymous Joiner',
  FALSE,
  FALSE,
  'active'
);

SELECT is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.open_chat_id')::INT),
  2::bigint,
  'Anonymous participant joined open chat'
);

-- Test 4: Anonymous has session_token set
SELECT isnt(
  (SELECT session_token FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  NULL,
  'Anonymous participant has session_token'
);

-- Test 5: Anonymous has user_id NULL
SELECT is(
  (SELECT user_id FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  NULL,
  'Anonymous participant has user_id NULL'
);

-- =============================================================================
-- PARTICIPANT STATUS
-- =============================================================================

-- Test 6: Default status is 'active'
SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  'active',
  'Participant status defaults to active'
);

-- Test 7: Can kick participant
UPDATE participants
SET status = 'kicked'
WHERE chat_id = current_setting('test.open_chat_id')::INT
AND display_name = 'Anonymous Joiner';

SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  'kicked',
  'Participant can be kicked'
);

-- Test 8: Participant can leave
UPDATE participants
SET status = 'left'
WHERE chat_id = current_setting('test.open_chat_id')::INT
AND display_name = 'Anonymous Joiner';

SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  'left',
  'Participant can leave'
);

-- =============================================================================
-- JOIN REQUESTS (require_approval = TRUE)
-- =============================================================================

-- Setup host for approval chat
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  gen_random_uuid(),
  'Host User',
  TRUE,
  FALSE,
  'active'
);

-- Test 9: Create join request for approval chat
INSERT INTO join_requests (chat_id, session_token, display_name, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  gen_random_uuid(),
  'Requester',
  'pending'
);

SELECT is(
  (SELECT COUNT(*) FROM join_requests WHERE chat_id = current_setting('test.approval_chat_id')::INT),
  1::bigint,
  'Join request created'
);

-- Store the session token for later tests
DO $$
DECLARE
  v_token UUID;
BEGIN
  SELECT session_token INTO v_token FROM join_requests WHERE display_name = 'Requester';
  PERFORM set_config('test.requester_token', v_token::TEXT, TRUE);
END $$;

-- Test 10: Join request has pending status
SELECT is(
  (SELECT status FROM join_requests
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND session_token = current_setting('test.requester_token')::UUID),
  'pending',
  'Join request status is pending'
);

-- Test 11: Approve join request
UPDATE join_requests
SET status = 'approved'
WHERE chat_id = current_setting('test.approval_chat_id')::INT
AND session_token = current_setting('test.requester_token')::UUID;

SELECT is(
  (SELECT status FROM join_requests
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND session_token = current_setting('test.requester_token')::UUID),
  'approved',
  'Join request can be approved'
);

-- Test 12: After approval, create participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  current_setting('test.requester_token')::UUID,
  'Requester',
  FALSE,
  FALSE,
  'active'
);

SELECT is(
  (SELECT COUNT(*) FROM participants
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND status = 'active'),
  2::bigint,
  'Approved requester becomes participant'
);

-- Test 13: Deny join request
INSERT INTO join_requests (chat_id, session_token, display_name, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  gen_random_uuid(),
  'Denied User',
  'pending'
);

DO $$
DECLARE
  v_token UUID;
BEGIN
  SELECT session_token INTO v_token FROM join_requests WHERE display_name = 'Denied User';
  PERFORM set_config('test.denied_token', v_token::TEXT, TRUE);
END $$;

UPDATE join_requests
SET status = 'denied'
WHERE chat_id = current_setting('test.approval_chat_id')::INT
AND session_token = current_setting('test.denied_token')::UUID;

SELECT is(
  (SELECT status FROM join_requests
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND session_token = current_setting('test.denied_token')::UUID),
  'denied',
  'Join request can be denied'
);

-- =============================================================================
-- INVITE-ONLY MODE
-- =============================================================================

-- Create invite-only chat
INSERT INTO chats (name, initial_message, creator_session_token, access_method)
VALUES ('Invite Only Chat', 'Email invite required', gen_random_uuid(), 'invite_only');

DO $$
DECLARE
  v_invite_chat INT;
BEGIN
  SELECT id INTO v_invite_chat FROM chats WHERE name = 'Invite Only Chat';
  PERFORM set_config('test.invite_chat_id', v_invite_chat::TEXT, TRUE);
END $$;

-- Add host
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.invite_chat_id')::INT,
  gen_random_uuid(),
  'Host',
  TRUE,
  FALSE,
  'active'
);

DO $$
DECLARE
  v_host_participant INT;
BEGIN
  SELECT id INTO v_host_participant FROM participants
  WHERE chat_id = current_setting('test.invite_chat_id')::INT AND is_host = TRUE;
  PERFORM set_config('test.host_participant_id', v_host_participant::TEXT, TRUE);
END $$;

-- Store a known UUID for the invite token
DO $$
BEGIN
  PERFORM set_config('test.invite_token', '11111111-1111-1111-1111-111111111111', TRUE);
END $$;

-- Test 14: Create email invite
INSERT INTO invites (chat_id, email, invite_token, invited_by, status, expires_at)
VALUES (
  current_setting('test.invite_chat_id')::INT,
  'invitee@example.com',
  current_setting('test.invite_token')::UUID,
  current_setting('test.host_participant_id')::INT,
  'pending',
  NOW() + INTERVAL '7 days'
);

SELECT is(
  (SELECT COUNT(*) FROM invites WHERE chat_id = current_setting('test.invite_chat_id')::INT),
  1::bigint,
  'Email invite created'
);

-- Test 15: Invite has token
SELECT isnt(
  (SELECT invite_token FROM invites WHERE email = 'invitee@example.com'),
  NULL,
  'Invite has token'
);

-- Test 16: Invite expires in future
SELECT ok(
  (SELECT expires_at FROM invites WHERE email = 'invitee@example.com') > NOW(),
  'Invite expires in the future'
);

-- Test 17: Accept invite
UPDATE invites
SET status = 'accepted'
WHERE invite_token = current_setting('test.invite_token')::UUID;

SELECT is(
  (SELECT status FROM invites WHERE invite_token = current_setting('test.invite_token')::UUID),
  'accepted',
  'Invite can be accepted'
);

-- Store another UUID for the expired token
DO $$
BEGIN
  PERFORM set_config('test.expired_token', '22222222-2222-2222-2222-222222222222', TRUE);
END $$;

-- Test 18: Create expired invite
INSERT INTO invites (chat_id, email, invite_token, invited_by, status, expires_at)
VALUES (
  current_setting('test.invite_chat_id')::INT,
  'expired@example.com',
  current_setting('test.expired_token')::UUID,
  current_setting('test.host_participant_id')::INT,
  'pending',
  NOW() - INTERVAL '1 day'
);

SELECT ok(
  (SELECT expires_at FROM invites WHERE invite_token = current_setting('test.expired_token')::UUID) < NOW(),
  'Expired invite has past expiration'
);

-- Test 19: Mark expired invite
UPDATE invites
SET status = 'expired'
WHERE invite_token = current_setting('test.expired_token')::UUID;

SELECT is(
  (SELECT status FROM invites WHERE invite_token = current_setting('test.expired_token')::UUID),
  'expired',
  'Invite can be marked expired'
);

-- =============================================================================
-- MULTIPLE CHATS PER PARTICIPANT (Same session)
-- =============================================================================

-- Store a session token for multi-chat test
DO $$
DECLARE
  v_session UUID := gen_random_uuid();
BEGIN
  PERFORM set_config('test.multi_session', v_session::TEXT, TRUE);
END $$;

-- Test 20: Same session can join multiple chats
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.open_chat_id')::INT,
  current_setting('test.multi_session')::UUID,
  'Multi-chat User',
  FALSE,
  FALSE,
  'active'
);

INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  current_setting('test.multi_session')::UUID,
  'Multi-chat User',
  FALSE,
  FALSE,
  'active'
);

SELECT is(
  (SELECT COUNT(*) FROM participants
   WHERE session_token = current_setting('test.multi_session')::UUID),
  2::bigint,
  'Same session can join multiple chats'
);

SELECT * FROM finish();
ROLLBACK;
