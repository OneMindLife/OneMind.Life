-- Test: Duplicate proposition detection via English translations
-- Tests the duplicate detection logic used by the submit-proposition Edge Function
--
-- The Edge Function:
-- 1. Translates content to English
-- 2. Normalizes: LOWER(TRIM(text))
-- 3. Checks for duplicates using normalized English translation
--
-- This test validates the SQL query pattern and normalization logic

BEGIN;
SET search_path TO public, extensions;
SELECT plan(15);

-- =============================================================================
-- SETUP: Create chat structure for duplicate detection testing
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Duplicate Detection Test Chat', 'Test message', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_round_id_2 INT;
  v_participant1_id INT;
  v_participant2_id INT;
  v_prop1_id INT;
  v_prop2_id INT;
  v_prop3_id INT;
  v_prop_carried_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Duplicate Detection Test Chat';

  -- Create cycle and two rounds
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 2, 'proposing') RETURNING id INTO v_round_id_2;

  -- Create participants
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Host User', TRUE, 'active')
  RETURNING id INTO v_participant1_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Test User', FALSE, 'active')
  RETURNING id INTO v_participant2_id;

  -- =============================================================================
  -- Create test propositions in Round 1
  -- =============================================================================

  -- Proposition 1: Normal case
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant1_id, 'We should improve our testing strategy')
  RETURNING id INTO v_prop1_id;

  -- Proposition 2: Different content
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant2_id, 'Let us add more unit tests')
  RETURNING id INTO v_prop2_id;

  -- Proposition 3: Unicode content
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant1_id, '我们应该改进测试策略')
  RETURNING id INTO v_prop3_id;

  -- =============================================================================
  -- Insert English translations (simulating what Edge Function does)
  -- =============================================================================

  -- English translations for propositions
  INSERT INTO translations (proposition_id, field_name, language_code, translated_text)
  VALUES
    (v_prop1_id, 'content', 'en', 'We should improve our testing strategy'),
    (v_prop1_id, 'content', 'es', 'Deberíamos mejorar nuestra estrategia de pruebas'),
    (v_prop2_id, 'content', 'en', 'Let us add more unit tests'),
    (v_prop2_id, 'content', 'es', 'Agreguemos más pruebas unitarias'),
    (v_prop3_id, 'content', 'en', 'We should improve our testing strategy'),
    (v_prop3_id, 'content', 'es', 'Deberíamos mejorar nuestra estrategia de pruebas');

  -- =============================================================================
  -- Create carried-forward proposition in Round 2
  -- =============================================================================

  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round_id_2, v_participant1_id, 'We should improve our testing strategy', v_prop1_id)
  RETURNING id INTO v_prop_carried_id;

  -- Add translation for carried proposition
  INSERT INTO translations (proposition_id, field_name, language_code, translated_text)
  VALUES (v_prop_carried_id, 'content', 'en', 'We should improve our testing strategy');

  -- Store IDs for tests
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.round_id_2', v_round_id_2::TEXT, TRUE);
  PERFORM set_config('test.prop1_id', v_prop1_id::TEXT, TRUE);
  PERFORM set_config('test.prop2_id', v_prop2_id::TEXT, TRUE);
  PERFORM set_config('test.prop3_id', v_prop3_id::TEXT, TRUE);
  PERFORM set_config('test.prop_carried_id', v_prop_carried_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: Exact match is detected
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We should improve our testing strategy'))),
  2,  -- prop1 and prop3 both have same English translation
  'Exact match: finds propositions with identical normalized English translation'
);

-- =============================================================================
-- Test 2: Case variation is detected (uppercase)
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('WE SHOULD IMPROVE OUR TESTING STRATEGY'))),
  2,
  'Case variation: uppercase submission matches existing lowercase'
);

-- =============================================================================
-- Test 3: Case variation is detected (mixed case)
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We Should Improve Our Testing Strategy'))),
  2,
  'Case variation: title case submission matches existing'
);

-- =============================================================================
-- Test 4: Leading whitespace is handled
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('   We should improve our testing strategy'))),
  2,
  'Whitespace: leading spaces are trimmed'
);

-- =============================================================================
-- Test 5: Trailing whitespace is handled
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We should improve our testing strategy   '))),
  2,
  'Whitespace: trailing spaces are trimmed'
);

-- =============================================================================
-- Test 6: Both leading and trailing whitespace handled
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('   We should improve our testing strategy   '))),
  2,
  'Whitespace: both leading and trailing spaces are trimmed'
);

-- =============================================================================
-- Test 7: Different content is NOT a duplicate
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('A completely different idea'))),
  0,
  'Different content: no match for new unique content'
);

-- =============================================================================
-- Test 8: Partial match is NOT a duplicate
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We should improve'))),
  0,
  'Partial match: substring does not match full proposition'
);

-- =============================================================================
-- Test 9: Different round = not duplicate (round isolation)
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id_2')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We should improve our testing strategy'))),
  1,  -- Only the carried proposition in round 2
  'Round isolation: same content in different round is separate'
);

-- =============================================================================
-- Test 10: Carried-forward propositions are included in duplicate check
-- =============================================================================
SELECT ok(
  (SELECT COUNT(*) > 0 FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id_2')::BIGINT
     AND p.carried_from_id IS NOT NULL
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We should improve our testing strategy'))),
  'Carried-forward: propositions with carried_from_id are included in duplicate check'
);

-- =============================================================================
-- Test 11: Query returns correct proposition ID for duplicate
-- =============================================================================
SELECT is(
  (SELECT p.id FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We should improve our testing strategy'))
   ORDER BY p.created_at
   LIMIT 1),
  current_setting('test.prop1_id')::BIGINT,
  'Duplicate query: returns first matching proposition ID'
);

-- =============================================================================
-- Test 12: Unicode content with same English translation is duplicate
-- =============================================================================
SELECT ok(
  (SELECT COUNT(*) >= 2 FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('We should improve our testing strategy'))),
  'Unicode: Chinese proposition with same English translation detected as duplicate'
);

-- =============================================================================
-- Test 13: Only English translations are checked (not Spanish)
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'es'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('Deberíamos mejorar nuestra estrategia de pruebas'))),
  2,
  'Language filter: Spanish translations exist but are not used for duplicate check'
);

-- =============================================================================
-- Test 14: Empty string after normalization doesn't crash
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations t
   INNER JOIN propositions p ON t.proposition_id = p.id
   WHERE p.round_id = current_setting('test.round_id')::BIGINT
     AND t.field_name = 'content'
     AND t.language_code = 'en'
     AND LOWER(TRIM(t.translated_text)) = LOWER(TRIM('   '))),
  0,
  'Edge case: whitespace-only string normalizes to empty and finds no match'
);

-- =============================================================================
-- Test 15: Translations table has correct unique constraint
-- (Ensures we don't accidentally insert duplicate translations)
-- =============================================================================
SELECT throws_ok(
  format(
    $$INSERT INTO translations (proposition_id, field_name, language_code, translated_text)
      VALUES (%s, 'content', 'en', 'Duplicate attempt')$$,
    current_setting('test.prop1_id')::BIGINT
  ),
  '23505',  -- unique_violation
  NULL,
  'Constraint: translations unique constraint prevents duplicates'
);

SELECT * FROM finish();
ROLLBACK;
