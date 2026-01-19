-- Invite code generation tests
BEGIN;
SET search_path TO public, extensions;
SELECT plan(17);

-- =============================================================================
-- INVITE CODE GENERATION BY ACCESS METHOD
-- =============================================================================

-- Test 1: Public chat gets auto-generated invite code (convenience shortcut)
INSERT INTO chats (name, initial_message, access_method, creator_session_token)
VALUES ('Public Chat', 'Public topic', 'public', gen_random_uuid());

SELECT isnt(
  (SELECT invite_code FROM chats WHERE name = 'Public Chat'),
  NULL,
  'Public chat gets invite code (convenience shortcut)'
);

-- Test 2: Code-based chat gets auto-generated invite code (required)
INSERT INTO chats (name, initial_message, access_method, creator_session_token)
VALUES ('Code Chat', 'Code topic', 'code', gen_random_uuid());

SELECT isnt(
  (SELECT invite_code FROM chats WHERE name = 'Code Chat'),
  NULL,
  'Code-based chat gets invite code (required)'
);

-- Test 3: Email invite-only chat does NOT get invite code
INSERT INTO chats (name, initial_message, access_method, creator_session_token)
VALUES ('Email Chat', 'Email topic', 'invite_only', gen_random_uuid());

SELECT is(
  (SELECT invite_code FROM chats WHERE name = 'Email Chat'),
  NULL,
  'Email invite-only chat does NOT get invite code'
);

-- =============================================================================
-- INVITE CODE FORMAT
-- =============================================================================

-- Test 4: Invite code is 6 characters
SELECT is(
  LENGTH((SELECT invite_code FROM chats WHERE name = 'Public Chat')),
  6,
  'Invite code is exactly 6 characters'
);

-- Test 5: Invite code only contains valid characters (no I, 1, O, 0)
SELECT ok(
  (SELECT invite_code FROM chats WHERE name = 'Public Chat') ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$',
  'Invite code only contains valid characters (no I/1/O/0 confusion)'
);

-- Test 6: Invite code is uppercase
SELECT ok(
  (SELECT invite_code FROM chats WHERE name = 'Code Chat') = UPPER((SELECT invite_code FROM chats WHERE name = 'Code Chat')),
  'Invite code is uppercase'
);

-- =============================================================================
-- INVITE CODE UNIQUENESS
-- =============================================================================

-- Test 7: Multiple chats get unique invite codes
INSERT INTO chats (name, initial_message, access_method, creator_session_token)
VALUES
  ('Chat A', 'Topic A', 'public', gen_random_uuid()),
  ('Chat B', 'Topic B', 'code', gen_random_uuid()),
  ('Chat C', 'Topic C', 'public', gen_random_uuid());

SELECT is(
  (SELECT COUNT(DISTINCT invite_code) FROM chats WHERE name IN ('Chat A', 'Chat B', 'Chat C')),
  3::bigint,
  'Multiple chats get unique invite codes'
);

-- Test 8: Invite code has unique constraint
SELECT has_index(
  'public',
  'chats',
  'chats_invite_code_key',
  'Invite code has unique index'
);

-- =============================================================================
-- INVITE CODE LOOKUP
-- =============================================================================

-- Test 9: Can find chat by invite code
SELECT is(
  (SELECT name FROM chats WHERE invite_code = (SELECT invite_code FROM chats WHERE name = 'Public Chat')),
  'Public Chat',
  'Can find chat by invite code'
);

-- Test 10: Public and code chats are findable by code, email-only is not
SELECT is(
  (SELECT COUNT(*) FROM chats WHERE invite_code IS NOT NULL AND access_method IN ('public', 'code')),
  (SELECT COUNT(*) FROM chats WHERE access_method IN ('public', 'code')),
  'All public and code chats have invite codes'
);

-- =============================================================================
-- ACCESS METHOD DEFAULTS
-- =============================================================================

-- Test 11: Default access_method is 'public'
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Default Chat', 'Default topic', gen_random_uuid());

SELECT is(
  (SELECT access_method FROM chats WHERE name = 'Default Chat'),
  'public',
  'Default access_method is public'
);

-- Test 12: Default chat also gets invite code
SELECT isnt(
  (SELECT invite_code FROM chats WHERE name = 'Default Chat'),
  NULL,
  'Default (public) chat also gets invite code'
);

-- Test 13: require_auth defaults to false
SELECT is(
  (SELECT require_auth FROM chats WHERE name = 'Default Chat'),
  FALSE,
  'require_auth defaults to false'
);

-- Test 14: require_approval defaults to false
SELECT is(
  (SELECT require_approval FROM chats WHERE name = 'Default Chat'),
  FALSE,
  'require_approval defaults to false'
);

-- Test 15: is_active defaults to true
SELECT is(
  (SELECT is_active FROM chats WHERE name = 'Default Chat'),
  TRUE,
  'is_active defaults to true'
);

-- Test 16: is_official defaults to false
SELECT is(
  (SELECT is_official FROM chats WHERE name = 'Default Chat'),
  FALSE,
  'is_official defaults to false'
);

-- =============================================================================
-- EDGE CASE: Manually setting invite_code
-- =============================================================================

-- Test 17: Can manually set invite code (bypasses trigger)
INSERT INTO chats (name, initial_message, access_method, invite_code, creator_session_token)
VALUES ('Manual Code Chat', 'Manual topic', 'code', 'ABC123', gen_random_uuid());

SELECT is(
  (SELECT invite_code FROM chats WHERE name = 'Manual Code Chat'),
  'ABC123',
  'Can manually set invite code'
);

SELECT * FROM finish();
ROLLBACK;
