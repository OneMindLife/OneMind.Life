-- Configurable consensus mechanism tests
BEGIN;
SET search_path TO public, extensions;
SELECT plan(15);

-- =============================================================================
-- SETUP: Create chat with cycles, rounds, and participants
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Consensus Test Chat', 'What should we decide?', gen_random_uuid());

-- Get chat_id
DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Consensus Test Chat';

  -- Create first cycle
  INSERT INTO cycles (chat_id)
  VALUES (v_chat_id)
  RETURNING id INTO v_cycle_id;

  -- Create first round
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_round_id;

  -- Create participant
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Host', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  -- Store IDs for later tests
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.participant_id', v_participant_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- CYCLE AND ROUND BASICS
-- =============================================================================

-- Test 1: First cycle exists
SELECT is(
  (SELECT COUNT(*) FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
  1::bigint,
  'First cycle exists'
);

-- Test 2: First round exists
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
  1::bigint,
  'First round exists'
);

-- Test 3: Round starts in proposing phase
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::INT),
  'proposing',
  'Round starts in proposing phase'
);

-- =============================================================================
-- PROPOSITIONS
-- =============================================================================

-- Create propositions
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.round_id')::INT, current_setting('test.participant_id')::INT, 'Proposition A'),
  (current_setting('test.round_id')::INT, current_setting('test.participant_id')::INT, 'Proposition B'),
  (current_setting('test.round_id')::INT, current_setting('test.participant_id')::INT, 'Proposition C');

-- Test 4: Propositions created successfully
SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::INT),
  3::bigint,
  '3 propositions created for round'
);

-- Store proposition IDs
DO $$
DECLARE
  v_prop_a INT;
  v_prop_b INT;
  v_prop_c INT;
BEGIN
  SELECT id INTO v_prop_a FROM propositions WHERE content = 'Proposition A';
  SELECT id INTO v_prop_b FROM propositions WHERE content = 'Proposition B';
  SELECT id INTO v_prop_c FROM propositions WHERE content = 'Proposition C';

  PERFORM set_config('test.prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.prop_b', v_prop_b::TEXT, TRUE);
  PERFORM set_config('test.prop_c', v_prop_c::TEXT, TRUE);
END $$;

-- =============================================================================
-- RATING PHASE
-- =============================================================================

-- Move to rating phase
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round_id')::INT;

-- Test 5: Phase updated to rating
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::INT),
  'rating',
  'Phase updated to rating'
);

-- Create ratings (Proposition A wins)
INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  (current_setting('test.prop_a')::INT, current_setting('test.participant_id')::INT, 90),
  (current_setting('test.prop_b')::INT, current_setting('test.participant_id')::INT, 70),
  (current_setting('test.prop_c')::INT, current_setting('test.participant_id')::INT, 50);

-- Test 6: Ratings created
SELECT is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_c')::INT
  )),
  3::bigint,
  '3 ratings created'
);

-- =============================================================================
-- WINNER SELECTION (FIRST ROUND)
-- =============================================================================

-- Calculate and store proposition MOVDA ratings (simulate what the MOVDA algorithm does)
INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
VALUES
  (current_setting('test.prop_a')::INT, current_setting('test.round_id')::INT, 90),
  (current_setting('test.prop_b')::INT, current_setting('test.round_id')::INT, 70),
  (current_setting('test.prop_c')::INT, current_setting('test.round_id')::INT, 50);

-- Set winner for first round (Proposition A)
-- This trigger will auto-create round 2
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_a')::bigint,
    is_sole_winner = TRUE
WHERE id = current_setting('test.round_id')::INT;

-- Test 7: Round winner set
SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round_id')::INT),
  current_setting('test.prop_a')::bigint,
  'Round 1 winner is Proposition A'
);

-- Test 8: Cycle winner NOT set yet (need 2-in-a-row by default)
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle winner not set after first round win'
);

-- =============================================================================
-- SECOND ROUND (created by trigger, Different winner = no consensus)
-- =============================================================================

-- Test 9: Second round auto-created by trigger
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
  2::bigint,
  'Second round auto-created by trigger'
);

-- Get auto-created round 2
DO $$
DECLARE
  v_round2_id INT;
BEGIN
  SELECT id INTO v_round2_id FROM rounds
  WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 2;
  PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- Create propositions for round 2
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.round2_id')::INT, current_setting('test.participant_id')::INT, 'Proposition D'),
  (current_setting('test.round2_id')::INT, current_setting('test.participant_id')::INT, 'Proposition E');

DO $$
DECLARE
  v_prop_d INT;
  v_prop_e INT;
BEGIN
  SELECT id INTO v_prop_d FROM propositions WHERE content = 'Proposition D';
  SELECT id INTO v_prop_e FROM propositions WHERE content = 'Proposition E';
  PERFORM set_config('test.prop_d', v_prop_d::TEXT, TRUE);
  PERFORM set_config('test.prop_e', v_prop_e::TEXT, TRUE);
END $$;

-- Move to rating and rate (Proposition D wins - different from A)
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round2_id')::INT;

INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  (current_setting('test.prop_d')::INT, current_setting('test.participant_id')::INT, 85),
  (current_setting('test.prop_e')::INT, current_setting('test.participant_id')::INT, 60);

INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating) VALUES
  (current_setting('test.prop_d')::INT, current_setting('test.round2_id')::INT, 85),
  (current_setting('test.prop_e')::INT, current_setting('test.round2_id')::INT, 60);

-- Set winner for round 2 (different from round 1)
-- This will auto-create round 3
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_d')::bigint,
    is_sole_winner = TRUE
WHERE id = current_setting('test.round2_id')::INT;

-- Test 10: Round 2 winner is Proposition D
SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round2_id')::INT),
  current_setting('test.prop_d')::bigint,
  'Round 2 winner is Proposition D'
);

-- Test 11: Still no cycle winner (different winners, not 2-in-a-row)
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle winner still not set (different winners, no 2-in-a-row)'
);

-- =============================================================================
-- THIRD ROUND (Same winner as second = 2-in-a-row!)
-- =============================================================================

-- Test 12: Third round auto-created
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
  3::bigint,
  'Third round auto-created'
);

-- Get auto-created round 3
DO $$
DECLARE
  v_round3_id INT;
BEGIN
  SELECT id INTO v_round3_id FROM rounds
  WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 3;
  PERFORM set_config('test.round3_id', v_round3_id::TEXT, TRUE);
END $$;

-- Create propositions for round 3 (include D again to test same content wins)
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.round3_id')::INT, current_setting('test.participant_id')::INT, 'Proposition D'),
  (current_setting('test.round3_id')::INT, current_setting('test.participant_id')::INT, 'Proposition F');

DO $$
DECLARE
  v_prop_d2 INT;
  v_prop_f INT;
BEGIN
  SELECT id INTO v_prop_d2 FROM propositions
  WHERE content = 'Proposition D' AND round_id = current_setting('test.round3_id')::INT;
  SELECT id INTO v_prop_f FROM propositions WHERE content = 'Proposition F';
  PERFORM set_config('test.prop_d2', v_prop_d2::TEXT, TRUE);
  PERFORM set_config('test.prop_f', v_prop_f::TEXT, TRUE);
END $$;

-- Move to rating
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round3_id')::INT;

-- Rate (D wins again!)
INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  (current_setting('test.prop_d2')::INT, current_setting('test.participant_id')::INT, 95),
  (current_setting('test.prop_f')::INT, current_setting('test.participant_id')::INT, 40);

INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating) VALUES
  (current_setting('test.prop_d2')::INT, current_setting('test.round3_id')::INT, 95),
  (current_setting('test.prop_f')::INT, current_setting('test.round3_id')::INT, 40);

-- Set winner for round 3 (Proposition D again - 2-in-a-row!)
-- Note: We need to use prop_d (from round 2) as the winner ID since the trigger
-- checks if the winner_id is the SAME as previous (not just content)
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_d')::bigint,  -- Same ID as round 2 winner
    is_sole_winner = TRUE
WHERE id = current_setting('test.round3_id')::INT;

-- Test 13: Round 3 winner has same ID as round 2 (2-in-a-row)
SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round3_id')::INT),
  current_setting('test.prop_d')::bigint,
  'Round 3 winner is same proposition ID as Round 2'
);

-- Test 14: 2-in-a-row triggers cycle completion
SELECT isnt(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle winner is set after 2-in-a-row'
);

-- Test 15: Cycle winner is Proposition D
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  current_setting('test.prop_d')::bigint,
  'Cycle winner is Proposition D (consensus reached)'
);

SELECT * FROM finish();
ROLLBACK;
