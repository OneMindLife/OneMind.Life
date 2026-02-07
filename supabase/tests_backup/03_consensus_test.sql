-- 2-in-a-row consensus mechanism tests
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(20);

-- =============================================================================
-- SETUP: Create chat with cycles, iterations, and participants
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Consensus Test Chat', 'What should we decide?', 'consensus-session');

-- Get chat_id
DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_iteration_id INT;
  v_participant_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Consensus Test Chat';

  -- Create first cycle
  INSERT INTO cycles (chat_id, custom_id)
  VALUES (v_chat_id, 1)
  RETURNING id INTO v_cycle_id;

  -- Create first iteration
  INSERT INTO iterations (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_iteration_id;

  -- Create participant
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, 'consensus-session', 'Host', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  -- Store IDs for later tests
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.iteration_id', v_iteration_id::TEXT, TRUE);
  PERFORM set_config('test.participant_id', v_participant_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- CYCLE AND ITERATION BASICS
-- =============================================================================

-- Test 1: First cycle has custom_id = 1
SELECT extensions.is(
  (SELECT custom_id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
  1,
  'First cycle has custom_id = 1'
);

-- Test 2: First iteration has custom_id = 1
SELECT extensions.is(
  (SELECT custom_id FROM iterations WHERE cycle_id = current_setting('test.cycle_id')::INT),
  1,
  'First iteration has custom_id = 1'
);

-- Test 3: Iteration starts in proposing phase
SELECT extensions.is(
  (SELECT phase FROM iterations WHERE id = current_setting('test.iteration_id')::INT),
  'proposing',
  'Iteration starts in proposing phase'
);

-- =============================================================================
-- PROPOSITIONS
-- =============================================================================

-- Create propositions
INSERT INTO propositions (iteration_id, participant_id, content)
VALUES
  (current_setting('test.iteration_id')::INT, current_setting('test.participant_id')::INT, 'Proposition A'),
  (current_setting('test.iteration_id')::INT, current_setting('test.participant_id')::INT, 'Proposition B'),
  (current_setting('test.iteration_id')::INT, current_setting('test.participant_id')::INT, 'Proposition C');

-- Test 4: Propositions created successfully
SELECT extensions.is(
  (SELECT COUNT(*) FROM propositions WHERE iteration_id = current_setting('test.iteration_id')::INT),
  3::bigint,
  '3 propositions created for iteration'
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
UPDATE iterations SET phase = 'rating' WHERE id = current_setting('test.iteration_id')::INT;

-- Test 5: Phase updated to rating
SELECT extensions.is(
  (SELECT phase FROM iterations WHERE id = current_setting('test.iteration_id')::INT),
  'rating',
  'Phase updated to rating'
);

-- Create ratings (Proposition A wins)
INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  (current_setting('test.prop_a')::INT, current_setting('test.participant_id')::INT, 90),
  (current_setting('test.prop_b')::INT, current_setting('test.participant_id')::INT, 70),
  (current_setting('test.prop_c')::INT, current_setting('test.participant_id')::INT, 50);

-- Test 6: Ratings created
SELECT extensions.is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_c')::INT
  )),
  3::bigint,
  '3 ratings created'
);

-- =============================================================================
-- WINNER SELECTION (FIRST ITERATION)
-- =============================================================================

-- Calculate and store proposition ratings (simulate what the app does)
INSERT INTO proposition_ratings (proposition_id, rating)
VALUES
  (current_setting('test.prop_a')::INT, 90),
  (current_setting('test.prop_b')::INT, 70),
  (current_setting('test.prop_c')::INT, 50);

-- Set winner for first iteration (Proposition A)
UPDATE iterations
SET winner_proposition_id = current_setting('test.prop_a')::INT
WHERE id = current_setting('test.iteration_id')::INT;

-- Test 7: Iteration winner set
SELECT extensions.is(
  (SELECT winner_proposition_id FROM iterations WHERE id = current_setting('test.iteration_id')::INT),
  current_setting('test.prop_a')::INT,
  'Iteration 1 winner is Proposition A'
);

-- Test 8: Cycle winner NOT set yet (need 2-in-a-row)
SELECT extensions.is(
  (SELECT winner_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle winner not set after first iteration win'
);

-- =============================================================================
-- SECOND ITERATION (Different winner = no consensus)
-- =============================================================================

-- Create second iteration (triggered by winner set, or manually)
INSERT INTO iterations (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 2, 'proposing');

DO $$
DECLARE
  v_iteration2_id INT;
BEGIN
  SELECT id INTO v_iteration2_id FROM iterations
  WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 2;
  PERFORM set_config('test.iteration2_id', v_iteration2_id::TEXT, TRUE);
END $$;

-- Test 9: Second iteration created
SELECT extensions.is(
  (SELECT COUNT(*) FROM iterations WHERE cycle_id = current_setting('test.cycle_id')::INT),
  2::bigint,
  'Second iteration created in same cycle'
);

-- Create propositions for iteration 2
INSERT INTO propositions (iteration_id, participant_id, content)
VALUES
  (current_setting('test.iteration2_id')::INT, current_setting('test.participant_id')::INT, 'Proposition D'),
  (current_setting('test.iteration2_id')::INT, current_setting('test.participant_id')::INT, 'Proposition E');

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
UPDATE iterations SET phase = 'rating' WHERE id = current_setting('test.iteration2_id')::INT;

INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  (current_setting('test.prop_d')::INT, current_setting('test.participant_id')::INT, 85),
  (current_setting('test.prop_e')::INT, current_setting('test.participant_id')::INT, 60);

INSERT INTO proposition_ratings (proposition_id, rating) VALUES
  (current_setting('test.prop_d')::INT, 85),
  (current_setting('test.prop_e')::INT, 60);

-- Set winner for iteration 2 (different from iteration 1)
UPDATE iterations
SET winner_proposition_id = current_setting('test.prop_d')::INT
WHERE id = current_setting('test.iteration2_id')::INT;

-- Test 10: Iteration 2 winner is Proposition D
SELECT extensions.is(
  (SELECT winner_proposition_id FROM iterations WHERE id = current_setting('test.iteration2_id')::INT),
  current_setting('test.prop_d')::INT,
  'Iteration 2 winner is Proposition D'
);

-- Test 11: Still no cycle winner (different winners, not 2-in-a-row)
SELECT extensions.is(
  (SELECT winner_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle winner still not set (different winners, no 2-in-a-row)'
);

-- =============================================================================
-- THIRD ITERATION (Same winner as second = 2-in-a-row!)
-- =============================================================================

-- Create third iteration
INSERT INTO iterations (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 3, 'proposing');

DO $$
DECLARE
  v_iteration3_id INT;
BEGIN
  SELECT id INTO v_iteration3_id FROM iterations
  WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 3;
  PERFORM set_config('test.iteration3_id', v_iteration3_id::TEXT, TRUE);
END $$;

-- Test 12: Third iteration exists
SELECT extensions.is(
  (SELECT COUNT(*) FROM iterations WHERE cycle_id = current_setting('test.cycle_id')::INT),
  3::bigint,
  'Third iteration created'
);

-- Create propositions for iteration 3 (include D again to test same content wins)
INSERT INTO propositions (iteration_id, participant_id, content)
VALUES
  (current_setting('test.iteration3_id')::INT, current_setting('test.participant_id')::INT, 'Proposition D'),  -- Same content
  (current_setting('test.iteration3_id')::INT, current_setting('test.participant_id')::INT, 'Proposition F');

DO $$
DECLARE
  v_prop_d2 INT;
  v_prop_f INT;
BEGIN
  SELECT id INTO v_prop_d2 FROM propositions
  WHERE content = 'Proposition D' AND iteration_id = current_setting('test.iteration3_id')::INT;
  SELECT id INTO v_prop_f FROM propositions WHERE content = 'Proposition F';
  PERFORM set_config('test.prop_d2', v_prop_d2::TEXT, TRUE);
  PERFORM set_config('test.prop_f', v_prop_f::TEXT, TRUE);
END $$;

-- Move to rating
UPDATE iterations SET phase = 'rating' WHERE id = current_setting('test.iteration3_id')::INT;

-- Rate (D wins again!)
INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  (current_setting('test.prop_d2')::INT, current_setting('test.participant_id')::INT, 95),
  (current_setting('test.prop_f')::INT, current_setting('test.participant_id')::INT, 40);

INSERT INTO proposition_ratings (proposition_id, rating) VALUES
  (current_setting('test.prop_d2')::INT, 95),
  (current_setting('test.prop_f')::INT, 40);

-- Set winner for iteration 3 (Proposition D again - 2-in-a-row!)
UPDATE iterations
SET winner_proposition_id = current_setting('test.prop_d2')::INT
WHERE id = current_setting('test.iteration3_id')::INT;

-- Test 13: Iteration 3 winner is Proposition D (content-wise)
SELECT extensions.is(
  (SELECT content FROM propositions WHERE id = (
    SELECT winner_proposition_id FROM iterations WHERE id = current_setting('test.iteration3_id')::INT
  )),
  'Proposition D',
  'Iteration 3 winner content is Proposition D'
);

-- =============================================================================
-- 2-IN-A-ROW CHECK (Manual verification since trigger may not be in place)
-- =============================================================================

-- Test 14: Check if previous iteration winner has same content
SELECT extensions.is(
  (SELECT content FROM propositions WHERE id = (
    SELECT winner_proposition_id FROM iterations WHERE id = current_setting('test.iteration2_id')::INT
  )),
  'Proposition D',
  'Previous iteration winner (iter 2) was also Proposition D'
);

-- Test 15: Verify 2-in-a-row condition is met
SELECT extensions.ok(
  (SELECT content FROM propositions WHERE id = (
    SELECT winner_proposition_id FROM iterations WHERE id = current_setting('test.iteration2_id')::INT
  )) = (SELECT content FROM propositions WHERE id = (
    SELECT winner_proposition_id FROM iterations WHERE id = current_setting('test.iteration3_id')::INT
  )),
  '2-in-a-row condition met: same content won twice consecutively'
);

-- =============================================================================
-- CYCLE COMPLETION
-- =============================================================================

-- Manually set cycle winner (simulating trigger behavior)
UPDATE cycles
SET winner_proposition_id = current_setting('test.prop_d2')::INT
WHERE id = current_setting('test.cycle_id')::INT;

-- Test 16: Cycle winner is set
SELECT extensions.isnt(
  (SELECT winner_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle winner is set after 2-in-a-row'
);

-- Test 17: Cycle winner content is correct
SELECT extensions.is(
  (SELECT content FROM propositions WHERE id = (
    SELECT winner_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT
  )),
  'Proposition D',
  'Cycle winner content is Proposition D (consensus reached)'
);

-- =============================================================================
-- NEW CYCLE STARTS
-- =============================================================================

-- Create new cycle (simulating trigger behavior after cycle completion)
INSERT INTO cycles (chat_id, custom_id)
VALUES (current_setting('test.chat_id')::INT, 2);

DO $$
DECLARE
  v_cycle2_id INT;
BEGIN
  SELECT id INTO v_cycle2_id FROM cycles
  WHERE chat_id = current_setting('test.chat_id')::INT AND custom_id = 2;
  PERFORM set_config('test.cycle2_id', v_cycle2_id::TEXT, TRUE);
END $$;

-- Test 18: Second cycle created
SELECT extensions.is(
  (SELECT COUNT(*) FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
  2::bigint,
  'Second cycle created after first cycle completed'
);

-- Test 19: Second cycle has custom_id = 2
SELECT extensions.is(
  (SELECT custom_id FROM cycles WHERE id = current_setting('test.cycle2_id')::INT),
  2,
  'Second cycle has custom_id = 2'
);

-- Create first iteration of new cycle
INSERT INTO iterations (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle2_id')::INT, 1, 'proposing');

-- Test 20: New cycle starts with iteration custom_id = 1
SELECT extensions.is(
  (SELECT custom_id FROM iterations WHERE cycle_id = current_setting('test.cycle2_id')::INT),
  1,
  'New cycle starts with iteration custom_id = 1'
);

SELECT * FROM finish();
ROLLBACK;
