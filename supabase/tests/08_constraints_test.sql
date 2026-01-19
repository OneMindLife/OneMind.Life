-- Constraints and foreign key tests
BEGIN;
SET search_path TO public, extensions;
SELECT plan(18);

-- =============================================================================
-- SETUP (Anonymous chats only - no users table dependency)
-- =============================================================================

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - CHATS
-- =============================================================================

-- Test 1: Chat can be created with session token (anonymous)
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('FK Test Chat', 'Testing foreign keys', gen_random_uuid());

SELECT isnt(
  (SELECT creator_session_token FROM chats WHERE name = 'FK Test Chat'),
  NULL,
  'Chat creator_session_token is set'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - CYCLES
-- =============================================================================

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'FK Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 2: Cycle references valid chat
INSERT INTO cycles (chat_id)
VALUES (current_setting('test.chat_id')::INT);

SELECT is(
  (SELECT COUNT(*) FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
  1::bigint,
  'Cycle created with valid chat_id'
);

-- Test 3: Cycle cannot reference invalid chat
SELECT throws_ok(
  $$INSERT INTO cycles (chat_id) VALUES (999999)$$,
  '23503',
  NULL,
  'Cycle cannot reference non-existent chat'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - ROUNDS
-- =============================================================================

DO $$
DECLARE
  v_cycle_id INT;
BEGIN
  SELECT id INTO v_cycle_id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
END $$;

-- Test 4: Round references valid cycle
INSERT INTO rounds (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 1, 'proposing');

SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
  1::bigint,
  'Round created with valid cycle_id'
);

-- Test 5: Round cannot reference invalid cycle
SELECT throws_ok(
  $$INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (999999, 1, 'proposing')$$,
  '23503',
  NULL,
  'Round cannot reference non-existent cycle'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - PARTICIPANTS
-- =============================================================================

-- Test 6: Participant references valid chat
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, gen_random_uuid(), 'Tester', TRUE, 'active');

SELECT is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.chat_id')::INT),
  1::bigint,
  'Participant created with valid chat_id'
);

-- Test 7: Participant cannot reference invalid chat
SELECT throws_ok(
  $$INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (999999, gen_random_uuid(), 'Bad', FALSE, 'active')$$,
  '23503',
  NULL,
  'Participant cannot reference non-existent chat'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - PROPOSITIONS
-- =============================================================================

DO $$
DECLARE
  v_iter_id INT;
  v_part_id INT;
BEGIN
  SELECT id INTO v_iter_id FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT;
  SELECT id INTO v_part_id FROM participants WHERE display_name = 'Tester';
  PERFORM set_config('test.round_id', v_iter_id::TEXT, TRUE);
  PERFORM set_config('test.participant_id', v_part_id::TEXT, TRUE);
END $$;

-- Test 8: Proposition references valid round and participant
INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.round_id')::INT, current_setting('test.participant_id')::INT, 'Test Prop');

SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::INT),
  1::bigint,
  'Proposition created with valid references'
);

-- Test 9: Proposition cannot reference invalid round
SELECT throws_ok(
  $$INSERT INTO propositions (round_id, participant_id, content)
    VALUES (999999, $$ || current_setting('test.participant_id') || $$, 'Bad Prop')$$,
  '23503',
  NULL,
  'Proposition cannot reference non-existent round'
);

-- Test 10: Proposition cannot reference invalid participant
SELECT throws_ok(
  $$INSERT INTO propositions (round_id, participant_id, content)
    VALUES ($$ || current_setting('test.round_id') || $$, 999999, 'Bad Prop')$$,
  '23503',
  NULL,
  'Proposition cannot reference non-existent participant'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - RATINGS
-- =============================================================================

DO $$
DECLARE
  v_prop_id INT;
BEGIN
  SELECT id INTO v_prop_id FROM propositions WHERE content = 'Test Prop';
  PERFORM set_config('test.proposition_id', v_prop_id::TEXT, TRUE);
END $$;

-- Move to rating phase
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round_id')::INT;

-- Test 11: Rating references valid proposition and participant
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.proposition_id')::INT, current_setting('test.participant_id')::INT, 75);

SELECT is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.proposition_id')::INT),
  1::bigint,
  'Rating created with valid references'
);

-- Test 12: Rating cannot reference invalid proposition
SELECT throws_ok(
  $$INSERT INTO ratings (proposition_id, participant_id, rating)
    VALUES (999999, $$ || current_setting('test.participant_id') || $$, 50)$$,
  '23503',
  NULL,
  'Rating cannot reference non-existent proposition'
);

-- =============================================================================
-- UNIQUE CONSTRAINTS
-- =============================================================================

-- Test 13: Invite code is unique
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Unique Code Chat 1', 'Test', gen_random_uuid());

DO $$
DECLARE
  v_code TEXT;
BEGIN
  SELECT invite_code INTO v_code FROM chats WHERE name = 'Unique Code Chat 1';
  PERFORM set_config('test.invite_code', v_code, TRUE);
END $$;

SELECT throws_ok(
  $$UPDATE chats SET invite_code = '$$ || current_setting('test.invite_code') || $$' WHERE name = 'FK Test Chat'$$,
  '23505',  -- unique_violation
  NULL,
  'Invite code must be unique'
);

-- Test 14: Rating unique per proposition-participant
SELECT throws_ok(
  $$INSERT INTO ratings (proposition_id, participant_id, rating)
    VALUES ($$ || current_setting('test.proposition_id') || $$, $$ || current_setting('test.participant_id') || $$, 80)$$,
  '23505',
  NULL,
  'Same participant cannot rate same proposition twice'
);

-- =============================================================================
-- NOT NULL CONSTRAINTS
-- =============================================================================

-- Test 15: Chat name required
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES (NULL, 'Message', gen_random_uuid())$$,
  '23502',  -- not_null_violation
  NULL,
  'Chat name is required'
);

-- Test 16: Chat initial_message required
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Name', NULL, gen_random_uuid())$$,
  '23502',
  NULL,
  'Chat initial_message is required'
);

-- Test 17: Proposition content required
SELECT throws_ok(
  $$INSERT INTO propositions (round_id, participant_id, content)
    VALUES ($$ || current_setting('test.round_id') || $$, $$ || current_setting('test.participant_id') || $$, NULL)$$,
  '23502',
  NULL,
  'Proposition content is required'
);

-- =============================================================================
-- SESSION TOKEN TYPE CONSTRAINT
-- =============================================================================

-- Test 18: Session token must be valid UUID
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Bad Session Chat', 'Test', 'not-a-valid-uuid')$$,
  '22P02',  -- invalid_text_representation
  NULL,
  'Session token must be valid UUID'
);

SELECT * FROM finish();
ROLLBACK;
