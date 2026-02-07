-- Participants and join flow tests
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(25);

-- =============================================================================
-- SETUP
-- =============================================================================

-- Create authenticated user
INSERT INTO users (id, email, display_name)
VALUES ('22222222-2222-2222-2222-222222222222', 'host@example.com', 'Host User');

-- Create chat with various settings
INSERT INTO chats (name, initial_message, creator_id, require_approval)
VALUES ('Approval Chat', 'Need approval to join', '22222222-2222-2222-2222-222222222222', TRUE);

INSERT INTO chats (name, initial_message, creator_id, require_approval)
VALUES ('Open Chat', 'Join freely', '22222222-2222-2222-2222-222222222222', FALSE);

INSERT INTO chats (name, initial_message, creator_id, require_auth)
VALUES ('Auth Required Chat', 'Must be signed in', '22222222-2222-2222-2222-222222222222', TRUE);

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

-- Test 1: Host joins as authenticated participant
INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.open_chat_id')::INT,
  '22222222-2222-2222-2222-222222222222',
  'Host User',
  TRUE,
  TRUE,
  'active'
);

SELECT extensions.is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.open_chat_id')::INT),
  1::bigint,
  'Host participant created'
);

-- Test 2: Host has is_host = TRUE
SELECT extensions.is(
  (SELECT is_host FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND user_id = '22222222-2222-2222-2222-222222222222'),
  TRUE,
  'Host has is_host = TRUE'
);

-- Test 3: Host has is_authenticated = TRUE
SELECT extensions.is(
  (SELECT is_authenticated FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND user_id = '22222222-2222-2222-2222-222222222222'),
  TRUE,
  'Host has is_authenticated = TRUE'
);

-- Test 4: Anonymous user joins open chat
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.open_chat_id')::INT,
  'anon-joiner-session',
  'Anonymous Joiner',
  FALSE,
  FALSE,
  'active'
);

SELECT extensions.is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.open_chat_id')::INT),
  2::bigint,
  'Anonymous participant joined open chat'
);

-- Test 5: Anonymous has session_token set
SELECT extensions.isnt(
  (SELECT session_token FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  NULL,
  'Anonymous participant has session_token'
);

-- Test 6: Anonymous has user_id NULL
SELECT extensions.is(
  (SELECT user_id FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  NULL,
  'Anonymous participant has user_id NULL'
);

-- =============================================================================
-- PARTICIPANT STATUS
-- =============================================================================

-- Test 7: Default status is 'active'
SELECT extensions.is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  'active',
  'Participant status defaults to active'
);

-- Test 8: Can kick participant
UPDATE participants
SET status = 'kicked'
WHERE chat_id = current_setting('test.open_chat_id')::INT
AND display_name = 'Anonymous Joiner';

SELECT extensions.is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.open_chat_id')::INT
   AND display_name = 'Anonymous Joiner'),
  'kicked',
  'Participant can be kicked'
);

-- Test 9: Participant can leave
UPDATE participants
SET status = 'left'
WHERE chat_id = current_setting('test.open_chat_id')::INT
AND display_name = 'Anonymous Joiner';

SELECT extensions.is(
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
INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  '22222222-2222-2222-2222-222222222222',
  'Host User',
  TRUE,
  TRUE,
  'active'
);

-- Test 10: Create join request for approval chat
INSERT INTO join_requests (chat_id, session_token, display_name, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  'requester-session',
  'Requester',
  'pending'
);

SELECT extensions.is(
  (SELECT COUNT(*) FROM join_requests WHERE chat_id = current_setting('test.approval_chat_id')::INT),
  1::bigint,
  'Join request created'
);

-- Test 11: Join request has pending status
SELECT extensions.is(
  (SELECT status FROM join_requests
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND session_token = 'requester-session'),
  'pending',
  'Join request status is pending'
);

-- Test 12: Approve join request
UPDATE join_requests
SET status = 'approved'
WHERE chat_id = current_setting('test.approval_chat_id')::INT
AND session_token = 'requester-session';

SELECT extensions.is(
  (SELECT status FROM join_requests
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND session_token = 'requester-session'),
  'approved',
  'Join request can be approved'
);

-- Test 13: After approval, create participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  'requester-session',
  'Requester',
  FALSE,
  FALSE,
  'active'
);

SELECT extensions.is(
  (SELECT COUNT(*) FROM participants
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND status = 'active'),
  2::bigint,  -- Host + approved requester
  'Approved requester becomes participant'
);

-- Test 14: Deny join request
INSERT INTO join_requests (chat_id, session_token, display_name, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  'denied-session',
  'Denied User',
  'pending'
);

UPDATE join_requests
SET status = 'denied'
WHERE chat_id = current_setting('test.approval_chat_id')::INT
AND session_token = 'denied-session';

SELECT extensions.is(
  (SELECT status FROM join_requests
   WHERE chat_id = current_setting('test.approval_chat_id')::INT
   AND session_token = 'denied-session'),
  'denied',
  'Join request can be denied'
);

-- =============================================================================
-- INVITE-ONLY MODE
-- =============================================================================

-- Create invite-only chat
INSERT INTO chats (name, initial_message, creator_id, access_method)
VALUES ('Invite Only Chat', 'Email invite required', '22222222-2222-2222-2222-222222222222', 'invite_only');

DO $$
DECLARE
  v_invite_chat INT;
BEGIN
  SELECT id INTO v_invite_chat FROM chats WHERE name = 'Invite Only Chat';
  PERFORM set_config('test.invite_chat_id', v_invite_chat::TEXT, TRUE);
END $$;

-- Add host
INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.invite_chat_id')::INT,
  '22222222-2222-2222-2222-222222222222',
  'Host',
  TRUE,
  TRUE,
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

-- Test 15: Create email invite
INSERT INTO invites (chat_id, email, invite_token, invited_by, status, expires_at)
VALUES (
  current_setting('test.invite_chat_id')::INT,
  'invitee@example.com',
  'unique-invite-token-123',
  current_setting('test.host_participant_id')::INT,
  'pending',
  NOW() + INTERVAL '7 days'
);

SELECT extensions.is(
  (SELECT COUNT(*) FROM invites WHERE chat_id = current_setting('test.invite_chat_id')::INT),
  1::bigint,
  'Email invite created'
);

-- Test 16: Invite has unique token
SELECT extensions.is(
  (SELECT invite_token FROM invites WHERE email = 'invitee@example.com'),
  'unique-invite-token-123',
  'Invite has unique token'
);

-- Test 17: Invite expires in future
SELECT extensions.ok(
  (SELECT expires_at FROM invites WHERE email = 'invitee@example.com') > NOW(),
  'Invite expires in the future'
);

-- Test 18: Accept invite
UPDATE invites
SET status = 'accepted'
WHERE invite_token = 'unique-invite-token-123';

SELECT extensions.is(
  (SELECT status FROM invites WHERE invite_token = 'unique-invite-token-123'),
  'accepted',
  'Invite can be accepted'
);

-- Test 19: Create expired invite
INSERT INTO invites (chat_id, email, invite_token, invited_by, status, expires_at)
VALUES (
  current_setting('test.invite_chat_id')::INT,
  'expired@example.com',
  'expired-token',
  current_setting('test.host_participant_id')::INT,
  'pending',
  NOW() - INTERVAL '1 day'
);

SELECT extensions.ok(
  (SELECT expires_at FROM invites WHERE invite_token = 'expired-token') < NOW(),
  'Expired invite has past expiration'
);

-- Test 20: Mark expired invite
UPDATE invites
SET status = 'expired'
WHERE invite_token = 'expired-token';

SELECT extensions.is(
  (SELECT status FROM invites WHERE invite_token = 'expired-token'),
  'expired',
  'Invite can be marked expired'
);

-- =============================================================================
-- ANONYMOUS TO AUTHENTICATED UPGRADE
-- =============================================================================

-- Create new user for upgrade test
INSERT INTO users (id, email, display_name)
VALUES ('33333333-3333-3333-3333-333333333333', 'upgraded@example.com', 'Upgraded User');

-- Create anonymous participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.open_chat_id')::INT,
  'upgrade-session',
  'Soon Upgraded',
  FALSE,
  FALSE,
  'active'
);

-- Test 21: Anonymous participant exists
SELECT extensions.is(
  (SELECT is_authenticated FROM participants
   WHERE session_token = 'upgrade-session'),
  FALSE,
  'Anonymous participant exists before upgrade'
);

-- Test 22: Upgrade anonymous to authenticated
UPDATE participants
SET
  user_id = '33333333-3333-3333-3333-333333333333',
  is_authenticated = TRUE
WHERE session_token = 'upgrade-session';

SELECT extensions.is(
  (SELECT is_authenticated FROM participants
   WHERE session_token = 'upgrade-session'),
  TRUE,
  'Participant upgraded to authenticated'
);

-- Test 23: Session token preserved after upgrade
SELECT extensions.isnt(
  (SELECT session_token FROM participants
   WHERE user_id = '33333333-3333-3333-3333-333333333333'
   AND chat_id = current_setting('test.open_chat_id')::INT),
  NULL,
  'Session token preserved after upgrade'
);

-- Test 24: User ID set after upgrade
SELECT extensions.is(
  (SELECT user_id FROM participants
   WHERE session_token = 'upgrade-session'),
  '33333333-3333-3333-3333-333333333333'::UUID,
  'User ID set after upgrade'
);

-- =============================================================================
-- MULTIPLE CHATS PER PARTICIPANT
-- =============================================================================

-- Test 25: Same user can join multiple chats
INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.approval_chat_id')::INT,
  '33333333-3333-3333-3333-333333333333',
  'Multi-chat User',
  FALSE,
  TRUE,
  'active'
);

SELECT extensions.is(
  (SELECT COUNT(*) FROM participants
   WHERE user_id = '33333333-3333-3333-3333-333333333333'),
  2::bigint,  -- open_chat + approval_chat
  'Same user can join multiple chats'
);

SELECT * FROM finish();
ROLLBACK;
