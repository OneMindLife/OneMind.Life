-- Constraints and foreign key tests
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(20);

-- =============================================================================
-- SETUP
-- =============================================================================

INSERT INTO users (id, email, display_name)
VALUES ('66666666-6666-6666-6666-666666666666', 'constraint@example.com', 'Constraint User');

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - CHATS
-- =============================================================================

-- Test 1: Chat can reference valid user
INSERT INTO chats (name, initial_message, creator_id)
VALUES ('FK Test Chat', 'Testing foreign keys', '66666666-6666-6666-6666-666666666666');

SELECT extensions.is(
  (SELECT creator_id FROM chats WHERE name = 'FK Test Chat'),
  '66666666-6666-6666-6666-666666666666'::UUID,
  'Chat creator_id references valid user'
);

-- Test 2: Chat cannot reference invalid user
SELECT extensions.throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_id)
    VALUES ('Bad FK Chat', 'Invalid creator', '99999999-9999-9999-9999-999999999999')$$,
  '23503',  -- foreign_key_violation
  NULL,
  'Chat cannot reference non-existent user'
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

-- Test 3: Cycle references valid chat
INSERT INTO cycles (chat_id, custom_id)
VALUES (current_setting('test.chat_id')::INT, 1);

SELECT extensions.is(
  (SELECT COUNT(*) FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
  1::bigint,
  'Cycle created with valid chat_id'
);

-- Test 4: Cycle cannot reference invalid chat
SELECT extensions.throws_ok(
  $$INSERT INTO cycles (chat_id, custom_id) VALUES (999999, 1)$$,
  '23503',
  NULL,
  'Cycle cannot reference non-existent chat'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - ITERATIONS
-- =============================================================================

DO $$
DECLARE
  v_cycle_id INT;
BEGIN
  SELECT id INTO v_cycle_id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
END $$;

-- Test 5: Iteration references valid cycle
INSERT INTO iterations (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 1, 'proposing');

SELECT extensions.is(
  (SELECT COUNT(*) FROM iterations WHERE cycle_id = current_setting('test.cycle_id')::INT),
  1::bigint,
  'Iteration created with valid cycle_id'
);

-- Test 6: Iteration cannot reference invalid cycle
SELECT extensions.throws_ok(
  $$INSERT INTO iterations (cycle_id, custom_id, phase) VALUES (999999, 1, 'proposing')$$,
  '23503',
  NULL,
  'Iteration cannot reference non-existent cycle'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - PARTICIPANTS
-- =============================================================================

-- Test 7: Participant references valid chat
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, 'constraint-session', 'Tester', TRUE, 'active');

SELECT extensions.is(
  (SELECT COUNT(*) FROM participants WHERE chat_id = current_setting('test.chat_id')::INT),
  1::bigint,
  'Participant created with valid chat_id'
);

-- Test 8: Participant cannot reference invalid chat
SELECT extensions.throws_ok(
  $$INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (999999, 'bad-session', 'Bad', FALSE, 'active')$$,
  '23503',
  NULL,
  'Participant cannot reference non-existent chat'
);

-- Test 9: Participant can reference valid user
INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
VALUES (
  current_setting('test.chat_id')::INT,
  '66666666-6666-6666-6666-666666666666',
  'Auth Tester',
  FALSE,
  TRUE,
  'active'
);

SELECT extensions.is(
  (SELECT user_id FROM participants WHERE display_name = 'Auth Tester'),
  '66666666-6666-6666-6666-666666666666'::UUID,
  'Participant user_id references valid user'
);

-- =============================================================================
-- FOREIGN KEY CONSTRAINTS - PROPOSITIONS
-- =============================================================================

DO $$
DECLARE
  v_iter_id INT;
  v_part_id INT;
BEGIN
  SELECT id INTO v_iter_id FROM iterations WHERE cycle_id = current_setting('test.cycle_id')::INT;
  SELECT id INTO v_part_id FROM participants WHERE session_token = 'constraint-session';
  PERFORM set_config('test.iteration_id', v_iter_id::TEXT, TRUE);
  PERFORM set_config('test.participant_id', v_part_id::TEXT, TRUE);
END $$;

-- Test 10: Proposition references valid iteration and participant
INSERT INTO propositions (iteration_id, participant_id, content)
VALUES (current_setting('test.iteration_id')::INT, current_setting('test.participant_id')::INT, 'Test Prop');

SELECT extensions.is(
  (SELECT COUNT(*) FROM propositions WHERE iteration_id = current_setting('test.iteration_id')::INT),
  1::bigint,
  'Proposition created with valid references'
);

-- Test 11: Proposition cannot reference invalid iteration
SELECT extensions.throws_ok(
  $$INSERT INTO propositions (iteration_id, participant_id, content)
    VALUES (999999, $$ || current_setting('test.participant_id') || $$, 'Bad Prop')$$,
  '23503',
  NULL,
  'Proposition cannot reference non-existent iteration'
);

-- Test 12: Proposition cannot reference invalid participant
SELECT extensions.throws_ok(
  $$INSERT INTO propositions (iteration_id, participant_id, content)
    VALUES ($$ || current_setting('test.iteration_id') || $$, 999999, 'Bad Prop')$$,
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
UPDATE iterations SET phase = 'rating' WHERE id = current_setting('test.iteration_id')::INT;

-- Test 13: Rating references valid proposition and participant
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.proposition_id')::INT, current_setting('test.participant_id')::INT, 75);

SELECT extensions.is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.proposition_id')::INT),
  1::bigint,
  'Rating created with valid references'
);

-- Test 14: Rating cannot reference invalid proposition
SELECT extensions.throws_ok(
  $$INSERT INTO ratings (proposition_id, participant_id, rating)
    VALUES (999999, $$ || current_setting('test.participant_id') || $$, 50)$$,
  '23503',
  NULL,
  'Rating cannot reference non-existent proposition'
);

-- =============================================================================
-- UNIQUE CONSTRAINTS
-- =============================================================================

-- Test 15: Invite code is unique
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Unique Code Chat 1', 'Test', 'unique-session-1');

DO $$
DECLARE
  v_code TEXT;
BEGIN
  SELECT invite_code INTO v_code FROM chats WHERE name = 'Unique Code Chat 1';
  PERFORM set_config('test.invite_code', v_code, TRUE);
END $$;

SELECT extensions.throws_ok(
  $$UPDATE chats SET invite_code = '$$ || current_setting('test.invite_code') || $$' WHERE name = 'FK Test Chat'$$,
  '23505',  -- unique_violation
  NULL,
  'Invite code must be unique'
);

-- Test 16: User email is unique
SELECT extensions.throws_ok(
  $$INSERT INTO users (id, email, display_name)
    VALUES ('77777777-7777-7777-7777-777777777777', 'constraint@example.com', 'Duplicate')$$,
  '23505',
  NULL,
  'User email must be unique'
);

-- Test 17: Rating unique per proposition-participant
SELECT extensions.throws_ok(
  $$INSERT INTO ratings (proposition_id, participant_id, rating)
    VALUES ($$ || current_setting('test.proposition_id') || $$, $$ || current_setting('test.participant_id') || $$, 80)$$,
  '23505',
  NULL,
  'Same participant cannot rate same proposition twice'
);

-- =============================================================================
-- NOT NULL CONSTRAINTS
-- =============================================================================

-- Test 18: Chat name required
SELECT extensions.throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES (NULL, 'Message', 'session')$$,
  '23502',  -- not_null_violation
  NULL,
  'Chat name is required'
);

-- Test 19: Chat initial_message required
SELECT extensions.throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Name', NULL, 'session')$$,
  '23502',
  NULL,
  'Chat initial_message is required'
);

-- Test 20: Proposition content required
SELECT extensions.throws_ok(
  $$INSERT INTO propositions (iteration_id, participant_id, content)
    VALUES ($$ || current_setting('test.iteration_id') || $$, $$ || current_setting('test.participant_id') || $$, NULL)$$,
  '23502',
  NULL,
  'Proposition content is required'
);

SELECT * FROM finish();
ROLLBACK;
