-- Test: Translation support for propositions
-- Tests the get_propositions_with_translations RPC function

BEGIN;
SET search_path TO public, extensions;
SELECT plan(11);

-- =============================================================================
-- SETUP: Create chat structure for translation testing
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Translation Test Chat', 'Test message', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant1_id INT;
  v_participant2_id INT;
  v_prop1_id INT;
  v_prop2_id INT;
  v_prop3_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Translation Test Chat';

  -- Create cycle and round
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  -- Create participants
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Host User', TRUE, 'active')
  RETURNING id INTO v_participant1_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Test User', FALSE, 'active')
  RETURNING id INTO v_participant2_id;

  -- Insert test propositions (let IDs be auto-generated)
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant1_id, 'Message 1')
  RETURNING id INTO v_prop1_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant2_id, 'Message 2')
  RETURNING id INTO v_prop2_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant1_id, 'Message 3 no translation')
  RETURNING id INTO v_prop3_id;

  -- Insert Spanish translations (only for props 1 and 2)
  INSERT INTO translations (proposition_id, field_name, language_code, translated_text)
  VALUES
    (v_prop1_id, 'content', 'es', 'Mensaje 1'),
    (v_prop2_id, 'content', 'es', 'Mensaje 2');

  -- Insert global scores for propositions (simulating MOVDA calculation results)
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score)
  VALUES
    (v_round_id, v_prop1_id, 100.0),
    (v_round_id, v_prop2_id, 50.0),
    (v_round_id, v_prop3_id, 0.0);

  -- Store IDs for tests
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.prop1_id', v_prop1_id::TEXT, TRUE);
  PERFORM set_config('test.prop2_id', v_prop2_id::TEXT, TRUE);
  PERFORM set_config('test.prop3_id', v_prop3_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: Function returns all propositions
-- =============================================================================
SELECT is(
  (SELECT COUNT(*) FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')),
  3::bigint,
  'Returns all propositions for the round'
);

-- =============================================================================
-- Test 2: Spanish translations are returned correctly
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop1_id')::BIGINT),
  'Mensaje 1',
  'Returns Spanish translation for proposition 1'
);

SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop2_id')::BIGINT),
  'Mensaje 2',
  'Returns Spanish translation for proposition 2'
);

-- =============================================================================
-- Test 3: Missing translation falls back to original content
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop3_id')::BIGINT),
  'Message 3 no translation',
  'Falls back to original content when translation is missing'
);

-- =============================================================================
-- Test 4: English returns original content (no translation needed)
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'en')
   WHERE id = current_setting('test.prop1_id')::BIGINT),
  'Message 1',
  'Returns original content for English request'
);

-- =============================================================================
-- Test 5: Language code is correct
-- =============================================================================
SELECT is(
  (SELECT language_code FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop1_id')::BIGINT),
  'es',
  'Returns correct language code for translated content'
);

-- =============================================================================
-- Test 6: Function preserves all proposition metadata
-- =============================================================================
SELECT ok(
  (SELECT participant_id FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop1_id')::BIGINT) IS NOT NULL,
  'Preserves participant_id in results'
);

-- =============================================================================
-- Test 7: Function returns global_score (BUG FIX - issue #1)
-- This was missing before, causing all results to display at position 50
-- =============================================================================
SELECT ok(
  (SELECT proposition_global_scores FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop1_id')::BIGINT) IS NOT NULL,
  'Returns proposition_global_scores in results (BUG FIX: was missing before)'
);

-- =============================================================================
-- Test 8: Global score value is correct for first proposition
-- =============================================================================
SELECT is(
  (SELECT (proposition_global_scores->>'global_score')::REAL
   FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop1_id')::BIGINT),
  100.0::REAL,
  'Returns correct global_score (100) for proposition 1'
);

-- =============================================================================
-- Test 9: Global score value is correct for second proposition
-- =============================================================================
SELECT is(
  (SELECT (proposition_global_scores->>'global_score')::REAL
   FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'en')
   WHERE id = current_setting('test.prop2_id')::BIGINT),
  50.0::REAL,
  'Returns correct global_score (50) for proposition 2'
);

-- =============================================================================
-- Test 10: Global score value is correct for third proposition
-- =============================================================================
SELECT is(
  (SELECT (proposition_global_scores->>'global_score')::REAL
   FROM get_propositions_with_translations(current_setting('test.round_id')::BIGINT, 'es')
   WHERE id = current_setting('test.prop3_id')::BIGINT),
  0.0::REAL,
  'Returns correct global_score (0) for proposition 3'
);

SELECT * FROM finish();
ROLLBACK;
