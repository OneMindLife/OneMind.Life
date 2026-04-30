-- Test: propositions.content UPDATE invalidates stale translations.
--
-- Covers the gap left by `translate_proposition_on_insert` — INSERTs spawn
-- translations, but UPDATEs (direct DB edit, future in-app edit feature)
-- used to leave stale translation rows, and get_propositions_with_translations
-- kept returning them. Added migration: trigger `translate_proposition_on_update`.
--
-- We don't exercise the pg_net HTTP call (that's out-of-process). We only
-- verify the deterministic DB-side behavior: stale translations are gone
-- after a content change, and left alone on no-op UPDATEs.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(9);

-- =============================================================================
-- Function + trigger exist
-- =============================================================================
SELECT has_function(
  'public', 'trigger_translate_proposition_on_update',
  'trigger function exists'
);

SELECT has_trigger(
  'propositions', 'translate_proposition_on_update',
  'UPDATE trigger exists on propositions'
);

SELECT trigger_is(
  'propositions', 'translate_proposition_on_update',
  'trigger_translate_proposition_on_update',
  'trigger wires to the new function'
);

-- =============================================================================
-- Fixture
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Prop Translate Update Test', 'Q', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant_a INT;
  v_participant_b INT;
  v_participant_root INT;
  v_prop_a INT;
  v_prop_b INT;
  v_original_prop INT;
  v_carried_prop INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Prop Translate Update Test';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  -- Use 'rating' so early-advance triggers don't complete the round before
  -- we finish seeding propositions.
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  -- One participant per proposition — propositions have a unique constraint
  -- on (round_id, participant_id) for carried_from_id IS NULL rows.
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Tester A', TRUE, 'active')
  RETURNING id INTO v_participant_a;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Tester B', FALSE, 'active')
  RETURNING id INTO v_participant_b;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Tester Root', FALSE, 'active')
  RETURNING id INTO v_participant_root;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_a, 'Original A')
  RETURNING id INTO v_prop_a;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_b, 'Original B')
  RETURNING id INTO v_prop_b;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_root, 'Root proposition')
  RETURNING id INTO v_original_prop;

  -- Carried-forward rows don't collide with the unique index
  -- (it filters on carried_from_id IS NULL), so participant reuse is fine.
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round_id, v_participant_root, 'Root proposition', v_original_prop)
  RETURNING id INTO v_carried_prop;

  -- Seed translations manually (trigger-driven inserts fire pg_net, which
  -- we can't rely on in tests).
  INSERT INTO translations (proposition_id, field_name, language_code, translated_text)
  VALUES
    (v_prop_a, 'content', 'en', 'Original A'),
    (v_prop_a, 'content', 'es', 'Original A (es)'),
    (v_prop_b, 'content', 'en', 'Original B'),
    (v_prop_b, 'content', 'es', 'Original B (es)'),
    (v_original_prop, 'content', 'en', 'Root proposition'),
    (v_original_prop, 'content', 'es', 'Raíz');

  PERFORM set_config('test.prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.prop_b', v_prop_b::TEXT, TRUE);
  PERFORM set_config('test.original_prop', v_original_prop::TEXT, TRUE);
  PERFORM set_config('test.carried_prop', v_carried_prop::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 4: Changing content deletes the proposition's stale translations
-- =============================================================================
UPDATE propositions SET content = 'Edited A'
WHERE id = current_setting('test.prop_a')::BIGINT;

SELECT is(
  (SELECT COUNT(*)::INT FROM translations
   WHERE proposition_id = current_setting('test.prop_a')::BIGINT
     AND field_name = 'content'),
  0,
  'translations deleted after content change'
);

-- =============================================================================
-- Test 5: Other propositions are unaffected
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM translations
   WHERE proposition_id = current_setting('test.prop_b')::BIGINT
     AND field_name = 'content'),
  2,
  'untouched proposition retains its translations'
);

-- =============================================================================
-- Test 6: No-op UPDATE (same content) does NOT delete translations
-- =============================================================================
UPDATE propositions SET content = 'Original B'
WHERE id = current_setting('test.prop_b')::BIGINT;

SELECT is(
  (SELECT COUNT(*)::INT FROM translations
   WHERE proposition_id = current_setting('test.prop_b')::BIGINT
     AND field_name = 'content'),
  2,
  'same-content UPDATE leaves translations alone'
);

-- =============================================================================
-- Test 7: UPDATE of unrelated column does NOT delete translations
-- =============================================================================
UPDATE propositions SET category = 'thought'
WHERE id = current_setting('test.prop_b')::BIGINT;

SELECT is(
  (SELECT COUNT(*)::INT FROM translations
   WHERE proposition_id = current_setting('test.prop_b')::BIGINT
     AND field_name = 'content'),
  2,
  'non-content column UPDATE leaves translations alone'
);

-- =============================================================================
-- Test 8: Updating a carried-forward prop does NOT delete the original's
-- translations (those are keyed on the original's id, not the carried row).
-- =============================================================================
UPDATE propositions SET content = 'Edited carried copy'
WHERE id = current_setting('test.carried_prop')::BIGINT;

SELECT is(
  (SELECT COUNT(*)::INT FROM translations
   WHERE proposition_id = current_setting('test.original_prop')::BIGINT
     AND field_name = 'content'),
  2,
  'editing a carried-forward row preserves the original prop''s translations'
);

-- =============================================================================
-- Test 9: Proposition with no existing translations — UPDATE is safe (no error).
-- =============================================================================
DO $$
DECLARE
  v_chat_id INT;
  v_round_id INT;
  v_participant_id INT;
  v_prop_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Prop Translate Update Test';
  SELECT r.id INTO v_round_id
  FROM rounds r JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = v_chat_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Tester NoTrans', FALSE, 'active')
  RETURNING id INTO v_participant_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_id, 'No translations yet')
  RETURNING id INTO v_prop_id;

  PERFORM set_config('test.no_trans_prop', v_prop_id::TEXT, TRUE);
END $$;

SELECT lives_ok(
  $$UPDATE propositions SET content = 'Still no translations'
    WHERE id = current_setting('test.no_trans_prop')::BIGINT$$,
  'UPDATE on prop with no translations does not error'
);

SELECT * FROM finish();
ROLLBACK;
