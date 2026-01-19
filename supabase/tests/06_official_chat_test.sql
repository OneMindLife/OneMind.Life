-- Official OneMind chat tests
BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- OFFICIAL CHAT FLAG
-- =============================================================================

-- Create regular chat first
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Regular Chat 1', 'Not official', gen_random_uuid());

-- Test 1: Regular chat has is_official = FALSE
SELECT is(
  (SELECT is_official FROM chats WHERE name = 'Regular Chat 1'),
  FALSE,
  'Regular chat has is_official = FALSE'
);

-- Test 2: Create official chat
INSERT INTO chats (name, initial_message, creator_session_token, is_official)
VALUES ('Official OneMind', 'Humanity''s public square', gen_random_uuid(), TRUE);

SELECT is(
  (SELECT is_official FROM chats WHERE name = 'Official OneMind'),
  TRUE,
  'Official chat has is_official = TRUE'
);

-- Test 3: Only one official chat can exist (unique partial index)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, is_official)
    VALUES ('Fake Official', 'Trying to be official', gen_random_uuid(), TRUE)$$,
  '23505',  -- unique_violation
  NULL,
  'Cannot create second official chat (unique constraint)'
);

-- Test 4: Can create multiple non-official chats
INSERT INTO chats (name, initial_message, creator_session_token, is_official)
VALUES ('Regular Chat 2', 'Also not official', gen_random_uuid(), FALSE);

-- Count chats created in THIS test (by name) to avoid interference from other data
SELECT is(
  (SELECT COUNT(*) FROM chats WHERE name IN ('Regular Chat 1', 'Regular Chat 2')),
  2::bigint,
  'Multiple non-official chats allowed'
);

-- Test 5: Official chat count is exactly 1
SELECT is(
  (SELECT COUNT(*) FROM chats WHERE is_official = TRUE),
  1::bigint,
  'Exactly one official chat exists'
);

-- =============================================================================
-- OFFICIAL CHAT PROPERTIES
-- =============================================================================

-- Test 6: Official chat should have specific name (application-level, not DB enforced)
SELECT is(
  (SELECT name FROM chats WHERE is_official = TRUE),
  'Official OneMind',
  'Official chat has expected name'
);

-- Test 7: Official chat is active
SELECT is(
  (SELECT is_active FROM chats WHERE is_official = TRUE),
  TRUE,
  'Official chat is active'
);

-- Test 8: Official chat has invite code (even if not used for access)
SELECT isnt(
  (SELECT invite_code FROM chats WHERE is_official = TRUE),
  NULL,
  'Official chat has invite code generated'
);

-- =============================================================================
-- OFFICIAL CHAT ACCESS
-- =============================================================================

-- Get official chat ID
DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE is_official = TRUE;
  PERFORM set_config('test.official_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 9: Anyone can view official chat (lurking) - create participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.official_chat_id')::INT,
  gen_random_uuid(),
  'Lurker',
  FALSE,
  FALSE,
  'active'
);

SELECT is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.official_chat_id')::INT),
  1::bigint,
  'Anonymous user can join official chat'
);

-- Test 10: Multiple anonymous users can join
INSERT INTO participants (chat_id, session_token, display_name, is_host, is_authenticated, status)
VALUES
  (current_setting('test.official_chat_id')::INT, gen_random_uuid(), 'User 1', FALSE, FALSE, 'active'),
  (current_setting('test.official_chat_id')::INT, gen_random_uuid(), 'User 2', FALSE, FALSE, 'active');

SELECT is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.official_chat_id')::INT),
  3::bigint,
  'Multiple anonymous users can join official chat'
);

-- =============================================================================
-- OFFICIAL CHAT CANNOT BE DELETED OR DEACTIVATED (Application-level)
-- =============================================================================

-- Test 11: Official chat can technically be deactivated (but shouldn't be in app)
UPDATE chats SET is_active = FALSE WHERE is_official = TRUE;

SELECT is(
  (SELECT is_active FROM chats WHERE is_official = TRUE),
  FALSE,
  'Official chat can be deactivated (DB level - app should prevent)'
);

-- Restore
UPDATE chats SET is_active = TRUE WHERE is_official = TRUE;

-- Test 12: Official chat is restored
SELECT is(
  (SELECT is_active FROM chats WHERE is_official = TRUE),
  TRUE,
  'Official chat restored to active'
);

SELECT * FROM finish();
ROLLBACK;
