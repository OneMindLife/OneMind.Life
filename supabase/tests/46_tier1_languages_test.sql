-- Test: Supported languages in translations table
-- Verifies that supported languages (en, es) can be stored and invalid codes are rejected

BEGIN;
SET search_path TO public, extensions;
SELECT plan(5);

-- =============================================================================
-- SETUP: Create a chat for testing translations
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token, enable_ai_participant)
VALUES ('Languages Test', 'Test message', gen_random_uuid(), FALSE);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Languages Test';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1-2: Supported language codes can be inserted
-- =============================================================================

-- Test English (en)
SELECT lives_ok(
  format(
    'INSERT INTO translations (chat_id, entity_type, field_name, language_code, translated_text)
     VALUES (%s, ''chat'', ''name'', ''en'', ''Test Chat'')',
    current_setting('test.chat_id')
  ),
  'English (en) language code accepted'
);

-- Test Spanish (es)
SELECT lives_ok(
  format(
    'INSERT INTO translations (chat_id, entity_type, field_name, language_code, translated_text)
     VALUES (%s, ''chat'', ''name'', ''es'', ''Chat de prueba'')',
    current_setting('test.chat_id')
  ),
  'Spanish (es) language code accepted'
);

-- =============================================================================
-- Test 3: Invalid language code is rejected
-- =============================================================================
SELECT throws_ok(
  format(
    'INSERT INTO translations (chat_id, entity_type, field_name, language_code, translated_text)
     VALUES (%s, ''chat'', ''name'', ''xx'', ''Invalid language'')',
    current_setting('test.chat_id')
  ),
  '23514', -- check_violation error code
  NULL,
  'Invalid language code (xx) is rejected by constraint'
);

-- =============================================================================
-- Test 4: Both translations were inserted successfully
-- =============================================================================
SELECT is(
  (SELECT COUNT(*) FROM translations WHERE chat_id = current_setting('test.chat_id')::INT),
  2::bigint,
  'Both supported language translations stored'
);

-- =============================================================================
-- Test 5: Verify translations can be retrieved
-- =============================================================================
SELECT is(
  (SELECT translated_text FROM translations
   WHERE chat_id = current_setting('test.chat_id')::INT
   AND language_code = 'es'),
  'Chat de prueba',
  'Spanish translation retrieved correctly'
);

-- =============================================================================
-- Finish
-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
