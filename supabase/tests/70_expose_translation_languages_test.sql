-- Test: RPCs expose translation_languages
-- Verifies that get_public_chats, get_public_chats_translated,
-- search_public_chats, search_public_chats_translated,
-- get_chat_translated, get_my_chats_translated,
-- get_chat_by_code_translated, and validate_invite_token
-- all return translation_languages.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- Setup: Create test user
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000e01', 'test-lang-rpc@test.com', 'authenticated', 'authenticated', now(), now());

-- Setup: Create a public chat with Spanish-only (let id auto-generate)
INSERT INTO chats (name, initial_message, access_method, creator_id, translation_languages, translations_enabled)
VALUES ('Lang RPC Test Chat', 'Hola mundo', 'public', '00000000-0000-0000-0000-000000000e01', '{es}', false);

-- Setup: Make creator a participant
INSERT INTO participants (chat_id, user_id, display_name, status)
VALUES (
  (SELECT id FROM chats WHERE name = 'Lang RPC Test Chat'),
  '00000000-0000-0000-0000-000000000e01',
  'Lang Tester',
  'active'
);

-- =============================================================================
-- Test 1: get_public_chats returns translation_languages
-- =============================================================================
SELECT is(
  (SELECT translation_languages FROM get_public_chats(20, 0, NULL)
   WHERE name = 'Lang RPC Test Chat'),
  ARRAY['es']::TEXT[],
  'get_public_chats returns translation_languages'
);

-- =============================================================================
-- Test 2: search_public_chats returns translation_languages
-- =============================================================================
SELECT is(
  (SELECT translation_languages FROM search_public_chats('Lang RPC', 20, 0, NULL)
   WHERE name = 'Lang RPC Test Chat'),
  ARRAY['es']::TEXT[],
  'search_public_chats returns translation_languages'
);

-- =============================================================================
-- Test 3: get_public_chats_translated returns translation_languages
-- =============================================================================
SELECT is(
  (SELECT translation_languages FROM get_public_chats_translated(20, 0, NULL, 'en')
   WHERE name = 'Lang RPC Test Chat'),
  ARRAY['es']::TEXT[],
  'get_public_chats_translated returns translation_languages'
);

-- =============================================================================
-- Test 4: search_public_chats_translated returns translation_languages
-- =============================================================================
SELECT is(
  (SELECT translation_languages FROM search_public_chats_translated('Lang RPC', 20, 0, NULL, 'en')
   WHERE name = 'Lang RPC Test Chat'),
  ARRAY['es']::TEXT[],
  'search_public_chats_translated returns translation_languages'
);

-- =============================================================================
-- Test 5: get_chat_translated returns translation_languages
-- =============================================================================
SELECT is(
  (SELECT translation_languages FROM get_chat_translated(
    (SELECT id FROM chats WHERE name = 'Lang RPC Test Chat'), 'en'
  )),
  ARRAY['es']::TEXT[],
  'get_chat_translated returns translation_languages'
);

-- =============================================================================
-- Test 6: get_my_chats_translated returns translation_languages
-- =============================================================================
SELECT is(
  (SELECT translation_languages FROM get_my_chats_translated(
    '00000000-0000-0000-0000-000000000e01', 'en'
  ) WHERE name = 'Lang RPC Test Chat'),
  ARRAY['es']::TEXT[],
  'get_my_chats_translated returns translation_languages'
);

-- =============================================================================
-- Test 7: get_chat_by_code_translated returns translation_languages
-- =============================================================================
SELECT is(
  (SELECT translation_languages FROM get_chat_by_code_translated(
    (SELECT invite_code FROM chats WHERE name = 'Lang RPC Test Chat')::TEXT, 'en'
  )),
  ARRAY['es']::TEXT[],
  'get_chat_by_code_translated returns translation_languages'
);

-- =============================================================================
-- Test 8: validate_invite_token returns translation_languages
-- =============================================================================
-- Setup: Create an invite for this chat
INSERT INTO invites (chat_id, email, invited_by, status)
VALUES (
  (SELECT id FROM chats WHERE name = 'Lang RPC Test Chat'),
  'invited-lang@test.com',
  (SELECT id FROM participants
   WHERE chat_id = (SELECT id FROM chats WHERE name = 'Lang RPC Test Chat')
   AND user_id = '00000000-0000-0000-0000-000000000e01'),
  'pending'
);

SELECT is(
  (SELECT translation_languages FROM validate_invite_token(
    (SELECT invite_token FROM invites WHERE email = 'invited-lang@test.com')::UUID
  )),
  ARRAY['es']::TEXT[],
  'validate_invite_token returns translation_languages'
);

SELECT * FROM finish();
ROLLBACK;
