-- Test: Carried proposition translations
-- Verifies that carried-forward propositions inherit translations from originals
-- via carried_from_id lookup in get_propositions_with_translations

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- =============================================================================
-- SETUP: Create chat with original and carried propositions
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Carried Translation Test', 'Test for carried proposition translations', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round1_id INT;
  v_round2_id INT;
  v_participant_id INT;
  v_original_prop_id INT;
  v_carried_prop_id INT;
  v_new_prop_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Carried Translation Test';

  -- Create cycle and two rounds
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round1_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 2, 'rating') RETURNING id INTO v_round2_id;

  -- Create participant
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Test User', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  -- Round 1: Create original proposition in Spanish
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round1_id, v_participant_id, 'Hola mundo, esta es mi idea')
  RETURNING id INTO v_original_prop_id;

  -- Add translations for the original proposition
  INSERT INTO translations (proposition_id, field_name, language_code, translated_text)
  VALUES
    (v_original_prop_id, 'content', 'en', 'Hello world, this is my idea'),
    (v_original_prop_id, 'content', 'es', 'Hola mundo, esta es mi idea');

  -- Round 2: Create carried-forward proposition (simulating winner carry)
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round2_id, v_participant_id, 'Hola mundo, esta es mi idea', v_original_prop_id)
  RETURNING id INTO v_carried_prop_id;

  -- Round 2: Also create a new proposition (not carried)
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round2_id, v_participant_id, 'Nueva idea sin traduccion')
  RETURNING id INTO v_new_prop_id;

  -- Store IDs for tests
  PERFORM set_config('test.round1_id', v_round1_id::TEXT, TRUE);
  PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
  PERFORM set_config('test.original_prop_id', v_original_prop_id::TEXT, TRUE);
  PERFORM set_config('test.carried_prop_id', v_carried_prop_id::TEXT, TRUE);
  PERFORM set_config('test.new_prop_id', v_new_prop_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: Original proposition has English translation
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(
    current_setting('test.round1_id')::BIGINT, 'en'
  ) WHERE id = current_setting('test.original_prop_id')::BIGINT),
  'Hello world, this is my idea',
  'Original proposition returns English translation'
);

-- =============================================================================
-- Test 2: Original proposition has Spanish translation
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(
    current_setting('test.round1_id')::BIGINT, 'es'
  ) WHERE id = current_setting('test.original_prop_id')::BIGINT),
  'Hola mundo, esta es mi idea',
  'Original proposition returns Spanish translation'
);

-- =============================================================================
-- Test 3: Carried proposition inherits English translation from original
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(
    current_setting('test.round2_id')::BIGINT, 'en'
  ) WHERE id = current_setting('test.carried_prop_id')::BIGINT),
  'Hello world, this is my idea',
  'Carried proposition inherits English translation from original'
);

-- =============================================================================
-- Test 4: Carried proposition inherits Spanish translation from original
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(
    current_setting('test.round2_id')::BIGINT, 'es'
  ) WHERE id = current_setting('test.carried_prop_id')::BIGINT),
  'Hola mundo, esta es mi idea',
  'Carried proposition inherits Spanish translation from original'
);

-- =============================================================================
-- Test 5: Carried proposition language_code shows source correctly
-- =============================================================================
SELECT is(
  (SELECT language_code FROM get_propositions_with_translations(
    current_setting('test.round2_id')::BIGINT, 'en'
  ) WHERE id = current_setting('test.carried_prop_id')::BIGINT),
  'en',
  'Carried proposition shows correct language_code for inherited translation'
);

-- =============================================================================
-- Test 6: Proposition without translation falls back to original content
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(
    current_setting('test.round2_id')::BIGINT, 'en'
  ) WHERE id = current_setting('test.new_prop_id')::BIGINT),
  'Nueva idea sin traduccion',
  'Proposition without translation falls back to original content'
);

-- =============================================================================
-- Test 7: Proposition without translation shows original language_code
-- =============================================================================
SELECT is(
  (SELECT language_code FROM get_propositions_with_translations(
    current_setting('test.round2_id')::BIGINT, 'en'
  ) WHERE id = current_setting('test.new_prop_id')::BIGINT),
  'original',
  'Proposition without translation shows "original" as language_code'
);

-- =============================================================================
-- Test 8: Carried proposition preserves carried_from_id in result
-- =============================================================================
SELECT is(
  (SELECT carried_from_id FROM get_propositions_with_translations(
    current_setting('test.round2_id')::BIGINT, 'en'
  ) WHERE id = current_setting('test.carried_prop_id')::BIGINT),
  current_setting('test.original_prop_id')::BIGINT,
  'Carried proposition result includes carried_from_id'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
