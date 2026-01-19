-- Configurable consensus tests
-- Tests for confirmation_rounds_required and show_previous_results settings
BEGIN;
SET search_path TO public, extensions;
SELECT plan(19);

-- =============================================================================
-- SETUP
-- =============================================================================

-- =============================================================================
-- DEFAULT VALUES
-- =============================================================================

-- Test 1: Default confirmation_rounds_required is 2
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Default Consensus Chat', 'Testing defaults', gen_random_uuid());

SELECT is(
  (SELECT confirmation_rounds_required FROM chats WHERE name = 'Default Consensus Chat'),
  2,
  'Default confirmation_rounds_required is 2'
);

-- Test 2: Default show_previous_results is FALSE
SELECT is(
  (SELECT show_previous_results FROM chats WHERE name = 'Default Consensus Chat'),
  FALSE,
  'Default show_previous_results is FALSE'
);

-- =============================================================================
-- CUSTOM VALUES
-- =============================================================================

-- Test 3: Can set confirmation_rounds_required to 1
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Instant Consensus Chat', 'One round wins', gen_random_uuid(), 1);

SELECT is(
  (SELECT confirmation_rounds_required FROM chats WHERE name = 'Instant Consensus Chat'),
  1,
  'confirmation_rounds_required can be set to 1'
);

-- Test 4: Can set confirmation_rounds_required to 2
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Double Consensus Chat', 'Two in a row', gen_random_uuid(), 2);

SELECT is(
  (SELECT confirmation_rounds_required FROM chats WHERE name = 'Double Consensus Chat'),
  2,
  'confirmation_rounds_required can be set to 2'
);

-- Test 5: Can set show_previous_results to TRUE
INSERT INTO chats (name, initial_message, creator_session_token, show_previous_results)
VALUES ('Show Results Chat', 'Show all results', gen_random_uuid(), TRUE);

SELECT is(
  (SELECT show_previous_results FROM chats WHERE name = 'Show Results Chat'),
  TRUE,
  'show_previous_results can be set to TRUE'
);

-- =============================================================================
-- CONSTRAINT: confirmation_rounds_required >= 1 AND <= 2
-- =============================================================================

-- Test 6: Cannot set confirmation_rounds_required to 0
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
    VALUES ('Bad Chat', 'Zero rounds', gen_random_uuid(), 0)$$,
  '23514',  -- check_violation
  NULL,
  'confirmation_rounds_required cannot be 0'
);

-- Test 7: Cannot set confirmation_rounds_required to negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
    VALUES ('Bad Chat', 'Negative rounds', gen_random_uuid(), -1)$$,
  '23514',
  NULL,
  'confirmation_rounds_required cannot be negative'
);

-- Test 8: Cannot set confirmation_rounds_required to 3 (max is 2)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
    VALUES ('Bad Chat', 'Three rounds', gen_random_uuid(), 3)$$,
  '23514',
  NULL,
  'confirmation_rounds_required cannot be 3 (max is 2)'
);

-- =============================================================================
-- CONSENSUS WITH confirmation_rounds_required = 1 (INSTANT CONSENSUS)
-- =============================================================================

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant_id INT;
  v_prop_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Instant Consensus Chat';

  -- Create cycle
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- Create round
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_round_id;

  -- Create participant
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Instant Tester', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  -- Create proposition
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_id, 'Instant Winner')
  RETURNING id INTO v_prop_id;

  PERFORM set_config('test.instant_chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.instant_cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.instant_round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.instant_prop_id', v_prop_id::TEXT, TRUE);
END $$;

-- Move to rating phase
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.instant_round_id')::INT;

-- Set winner (should trigger immediate consensus with confirmation_rounds_required = 1)
UPDATE rounds
SET winning_proposition_id = current_setting('test.instant_prop_id')::INT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.instant_round_id')::INT;

-- Test 9: After one win, cycle winner is set (confirmation_rounds_required = 1)
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.instant_cycle_id')::INT),
  current_setting('test.instant_prop_id')::bigint,
  'Cycle winner set after just 1 round win (confirmation_rounds_required = 1)'
);

-- Test 10: Cycle is completed
SELECT isnt(
  (SELECT completed_at FROM cycles WHERE id = current_setting('test.instant_cycle_id')::INT),
  NULL,
  'Cycle is marked as completed'
);

-- Test 11: No second round created (consensus reached)
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.instant_cycle_id')::INT),
  1::bigint,
  'No second round created - consensus reached after 1 round'
);

-- =============================================================================
-- CONSENSUS WITH confirmation_rounds_required = 2 (DOUBLE CONFIRMATION)
-- =============================================================================

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round1_id INT;
  v_participant_id INT;
  v_prop_a INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Double Consensus Chat';

  -- Create cycle
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- Create first round
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_round1_id;

  -- Create participant
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Double Tester', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  -- Create proposition
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round1_id, v_participant_id, 'Double Winner')
  RETURNING id INTO v_prop_a;

  PERFORM set_config('test.double_chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.double_cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.double_round1_id', v_round1_id::TEXT, TRUE);
  PERFORM set_config('test.double_prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.double_participant_id', v_participant_id::TEXT, TRUE);
END $$;

-- === ROUND 1 ===
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.double_round1_id')::INT;

UPDATE rounds
SET winning_proposition_id = current_setting('test.double_prop_a')::INT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.double_round1_id')::INT;

-- Test 12: After round 1, cycle winner still NULL (need 2-in-a-row)
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.double_cycle_id')::INT),
  NULL,
  'Cycle winner NULL after 1st win (need 2-in-a-row)'
);

-- Test 13: Second round auto-created
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.double_cycle_id')::INT),
  2::bigint,
  'Second round auto-created after 1st win'
);

-- === ROUND 2 ===
DO $$
DECLARE
  v_round2_id INT;
BEGIN
  SELECT id INTO v_round2_id FROM rounds
  WHERE cycle_id = current_setting('test.double_cycle_id')::INT AND custom_id = 2;
  PERFORM set_config('test.double_round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- Start round 2 in proposing, set same winner
UPDATE rounds SET phase = 'proposing' WHERE id = current_setting('test.double_round2_id')::INT;
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.double_round2_id')::INT;

UPDATE rounds
SET winning_proposition_id = current_setting('test.double_prop_a')::INT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.double_round2_id')::INT;

-- Test 14: After round 2, cycle winner IS SET (2-in-a-row achieved!)
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.double_cycle_id')::INT),
  current_setting('test.double_prop_a')::bigint,
  'Cycle winner set after 2nd consecutive win (confirmation_rounds_required = 2)'
);

-- Test 15: Cycle is completed
SELECT isnt(
  (SELECT completed_at FROM cycles WHERE id = current_setting('test.double_cycle_id')::INT),
  NULL,
  'Cycle is marked as completed after 2-in-a-row'
);

-- Test 16: No 3rd round created (consensus reached)
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.double_cycle_id')::INT),
  2::bigint,
  'No 3rd round created - consensus reached after 2 rounds'
);

-- =============================================================================
-- BROKEN CHAIN RESETS COUNT
-- =============================================================================

-- Create another chat with confirmation_rounds_required = 2
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Chain Break Chat', 'Test chain break', gen_random_uuid(), 2);

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round1_id INT;
  v_participant_id INT;
  v_prop_a INT;
  v_prop_b INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Chain Break Chat';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_round1_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Chain Tester', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round1_id, v_participant_id, 'Prop A')
  RETURNING id INTO v_prop_a;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round1_id, v_participant_id, 'Prop B')
  RETURNING id INTO v_prop_b;

  PERFORM set_config('test.chain_chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.chain_cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.chain_round1_id', v_round1_id::TEXT, TRUE);
  PERFORM set_config('test.chain_prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.chain_prop_b', v_prop_b::TEXT, TRUE);
END $$;

-- Round 1: Prop A wins
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.chain_round1_id')::INT;
UPDATE rounds
SET winning_proposition_id = current_setting('test.chain_prop_a')::INT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.chain_round1_id')::INT;

-- Round 2: Different prop (B) wins - breaks chain
DO $$
DECLARE
  v_round2_id INT;
BEGIN
  SELECT id INTO v_round2_id FROM rounds
  WHERE cycle_id = current_setting('test.chain_cycle_id')::INT AND custom_id = 2;
  PERFORM set_config('test.chain_round2_id', v_round2_id::TEXT, TRUE);
END $$;

UPDATE rounds SET phase = 'proposing' WHERE id = current_setting('test.chain_round2_id')::INT;
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.chain_round2_id')::INT;
UPDATE rounds
SET winning_proposition_id = current_setting('test.chain_prop_b')::INT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.chain_round2_id')::INT;

-- Test 17: Chain broken - cycle winner still NULL
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.chain_cycle_id')::INT),
  NULL,
  'Chain broken: different winner in round 2 resets count'
);

-- Test 18: Round 3 created to continue
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.chain_cycle_id')::INT),
  3::bigint,
  'Round 3 created after chain break'
);

-- Round 3: Prop B wins again - now 2-in-a-row for Prop B
DO $$
DECLARE
  v_round3_id INT;
BEGIN
  SELECT id INTO v_round3_id FROM rounds
  WHERE cycle_id = current_setting('test.chain_cycle_id')::INT AND custom_id = 3;
  PERFORM set_config('test.chain_round3_id', v_round3_id::TEXT, TRUE);
END $$;

UPDATE rounds SET phase = 'proposing' WHERE id = current_setting('test.chain_round3_id')::INT;
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.chain_round3_id')::INT;
UPDATE rounds
SET winning_proposition_id = current_setting('test.chain_prop_b')::INT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.chain_round3_id')::INT;

-- Test 19: After Prop B wins 2-in-a-row, consensus reached
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.chain_cycle_id')::INT),
  current_setting('test.chain_prop_b')::bigint,
  'Prop B reaches consensus after 2-in-a-row (after chain break)'
);

SELECT * FROM finish();
ROLLBACK;
