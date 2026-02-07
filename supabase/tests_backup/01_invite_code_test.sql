-- Invite code generation tests
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(12);

-- =============================================================================
-- INVITE CODE GENERATION
-- =============================================================================

-- Test 1: Chat gets auto-generated invite code on insert
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Test Chat', 'What should we discuss?', 'test-session-123');

SELECT extensions.isnt(
  (SELECT invite_code FROM chats WHERE name = 'Test Chat'),
  NULL,
  'Invite code is auto-generated on chat creation'
);

-- Test 2: Invite code is 6 characters
SELECT extensions.is(
  LENGTH((SELECT invite_code FROM chats WHERE name = 'Test Chat')),
  6,
  'Invite code is exactly 6 characters'
);

-- Test 3: Invite code only contains valid characters (no I, 1, O, 0)
SELECT extensions.ok(
  (SELECT invite_code FROM chats WHERE name = 'Test Chat') ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$',
  'Invite code only contains valid characters (no I/1/O/0 confusion)'
);

-- Test 4: Multiple chats get unique invite codes
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES
  ('Chat A', 'Topic A', 'session-a'),
  ('Chat B', 'Topic B', 'session-b'),
  ('Chat C', 'Topic C', 'session-c');

SELECT extensions.is(
  (SELECT COUNT(DISTINCT invite_code) FROM chats WHERE name IN ('Chat A', 'Chat B', 'Chat C')),
  3::bigint,
  'Multiple chats get unique invite codes'
);

-- Test 5: Invite code is uppercase
SELECT extensions.ok(
  (SELECT invite_code FROM chats WHERE name = 'Test Chat') = UPPER((SELECT invite_code FROM chats WHERE name = 'Test Chat')),
  'Invite code is uppercase'
);

-- =============================================================================
-- INVITE CODE LOOKUP
-- =============================================================================

-- Test 6: Can find chat by invite code
SELECT extensions.is(
  (SELECT name FROM chats WHERE invite_code = (SELECT invite_code FROM chats WHERE name = 'Test Chat')),
  'Test Chat',
  'Can find chat by invite code'
);

-- Test 7: Invite code is unique constraint
SELECT extensions.has_index(
  'public',
  'chats',
  'chats_invite_code_key',
  'Invite code has unique index'
);

-- =============================================================================
-- ACCESS METHOD DEFAULTS
-- =============================================================================

-- Test 8: Default access_method is 'code'
SELECT extensions.is(
  (SELECT access_method FROM chats WHERE name = 'Test Chat'),
  'code',
  'Default access_method is code'
);

-- Test 9: require_auth defaults to false
SELECT extensions.is(
  (SELECT require_auth FROM chats WHERE name = 'Test Chat'),
  FALSE,
  'require_auth defaults to false'
);

-- Test 10: require_approval defaults to false
SELECT extensions.is(
  (SELECT require_approval FROM chats WHERE name = 'Test Chat'),
  FALSE,
  'require_approval defaults to false'
);

-- Test 11: is_active defaults to true
SELECT extensions.is(
  (SELECT is_active FROM chats WHERE name = 'Test Chat'),
  TRUE,
  'is_active defaults to true'
);

-- Test 12: is_official defaults to false
SELECT extensions.is(
  (SELECT is_official FROM chats WHERE name = 'Test Chat'),
  FALSE,
  'is_official defaults to false'
);

SELECT * FROM finish();
ROLLBACK;
