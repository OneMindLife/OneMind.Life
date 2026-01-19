-- Phase transition and timer behavior tests
-- These tests verify the database-level behavior when phases advance
BEGIN;
SET search_path TO public, extensions;
SELECT plan(25);

-- =============================================================================
-- SETUP
-- =============================================================================

-- Create test chat
INSERT INTO chats (
  name,
  initial_message,
  creator_session_token,
  proposing_duration_seconds,
  rating_duration_seconds,
  proposing_minimum,
  rating_minimum
)
VALUES (
  'Phase Transition Test Chat',
  'Testing phase transitions',
  gen_random_uuid(),
  300,  -- 5 min proposing
  600,  -- 10 min rating
  3,    -- proposing_minimum (>=3 because users can't rate their own)
  2
);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Phase Transition Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Create cycle
INSERT INTO cycles (chat_id)
VALUES (current_setting('test.chat_id')::INT);

DO $$
DECLARE
  v_cycle_id INT;
BEGIN
  SELECT id INTO v_cycle_id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
END $$;

-- Create participants
DO $$
DECLARE
  v_p1 INT;
  v_p2 INT;
  v_p3 INT;
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, gen_random_uuid(), 'User 1', TRUE, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, gen_random_uuid(), 'User 2', FALSE, 'active')
  RETURNING id INTO v_p2;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, gen_random_uuid(), 'User 3', FALSE, 'active')
  RETURNING id INTO v_p3;

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);
END $$;

-- =============================================================================
-- PHASE TRANSITION BASICS
-- =============================================================================

-- Create first round in waiting phase
INSERT INTO rounds (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 1, 'waiting');

DO $$
DECLARE
  v_round_id INT;
BEGIN
  SELECT id INTO v_round_id FROM rounds
  WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 1;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 1: Round starts in waiting phase
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::INT),
  'waiting',
  'Round starts in waiting phase'
);

-- Test 2: phase_started_at is NULL in waiting
SELECT is(
  (SELECT phase_started_at FROM rounds WHERE id = current_setting('test.round_id')::INT),
  NULL,
  'phase_started_at is NULL in waiting phase'
);

-- Test 3: phase_ends_at is NULL in waiting
SELECT is(
  (SELECT phase_ends_at FROM rounds WHERE id = current_setting('test.round_id')::INT),
  NULL,
  'phase_ends_at is NULL in waiting phase'
);

-- =============================================================================
-- TRANSITION: WAITING -> PROPOSING
-- =============================================================================

-- Simulate host starting the phase
UPDATE rounds
SET
  phase = 'proposing',
  phase_started_at = NOW(),
  phase_ends_at = NOW() + INTERVAL '300 seconds'
WHERE id = current_setting('test.round_id')::INT;

-- Test 4: Phase changed to proposing
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::INT),
  'proposing',
  'Phase changed to proposing'
);

-- Test 5: phase_started_at is set
SELECT isnt(
  (SELECT phase_started_at FROM rounds WHERE id = current_setting('test.round_id')::INT),
  NULL,
  'phase_started_at is set after transition to proposing'
);

-- Test 6: phase_ends_at is in the future
SELECT ok(
  (SELECT phase_ends_at FROM rounds WHERE id = current_setting('test.round_id')::INT) > NOW(),
  'phase_ends_at is in the future'
);

-- Test 7: phase_ends_at is approximately 5 minutes from phase_started_at
SELECT ok(
  (SELECT EXTRACT(EPOCH FROM (phase_ends_at - phase_started_at))
   FROM rounds WHERE id = current_setting('test.round_id')::INT) BETWEEN 299 AND 301,
  'phase_ends_at is ~300 seconds after phase_started_at'
);

-- =============================================================================
-- PROPOSITIONS DURING PROPOSING PHASE
-- =============================================================================

-- Create propositions
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.round_id')::INT, current_setting('test.p1')::INT, 'Idea Alpha'),
  (current_setting('test.round_id')::INT, current_setting('test.p2')::INT, 'Idea Beta'),
  (current_setting('test.round_id')::INT, current_setting('test.p3')::INT, 'Idea Gamma');

DO $$
DECLARE
  v_prop_a INT;
  v_prop_b INT;
  v_prop_g INT;
BEGIN
  SELECT id INTO v_prop_a FROM propositions WHERE content = 'Idea Alpha';
  SELECT id INTO v_prop_b FROM propositions WHERE content = 'Idea Beta';
  SELECT id INTO v_prop_g FROM propositions WHERE content = 'Idea Gamma';

  PERFORM set_config('test.prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.prop_b', v_prop_b::TEXT, TRUE);
  PERFORM set_config('test.prop_g', v_prop_g::TEXT, TRUE);
END $$;

-- Test 8: Propositions created during proposing phase
SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::INT),
  3::bigint,
  '3 propositions created during proposing phase'
);

-- =============================================================================
-- TRANSITION: PROPOSING -> RATING
-- =============================================================================

-- Simulate phase advancement
UPDATE rounds
SET
  phase = 'rating',
  phase_started_at = NOW(),
  phase_ends_at = NOW() + INTERVAL '600 seconds'
WHERE id = current_setting('test.round_id')::INT;

-- Test 9: Phase changed to rating
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::INT),
  'rating',
  'Phase changed to rating'
);

-- Test 10: phase_ends_at updated for rating duration
SELECT ok(
  (SELECT EXTRACT(EPOCH FROM (phase_ends_at - phase_started_at))
   FROM rounds WHERE id = current_setting('test.round_id')::INT) BETWEEN 599 AND 601,
  'phase_ends_at is ~600 seconds after phase_started_at (rating duration)'
);

-- =============================================================================
-- RATINGS DURING RATING PHASE
-- =============================================================================

-- Create ratings
INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  -- User 1 rates all
  (current_setting('test.prop_a')::INT, current_setting('test.p1')::INT, 90),
  (current_setting('test.prop_b')::INT, current_setting('test.p1')::INT, 60),
  (current_setting('test.prop_g')::INT, current_setting('test.p1')::INT, 40),
  -- User 2 rates all
  (current_setting('test.prop_a')::INT, current_setting('test.p2')::INT, 80),
  (current_setting('test.prop_b')::INT, current_setting('test.p2')::INT, 70),
  (current_setting('test.prop_g')::INT, current_setting('test.p2')::INT, 50),
  -- User 3 rates all
  (current_setting('test.prop_a')::INT, current_setting('test.p3')::INT, 85),
  (current_setting('test.prop_b')::INT, current_setting('test.p3')::INT, 65),
  (current_setting('test.prop_g')::INT, current_setting('test.p3')::INT, 45);

-- Test 11: 9 ratings created (3 users x 3 propositions)
SELECT is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )),
  9::bigint,
  '9 ratings created (3 users x 3 propositions)'
);

-- Test 12: Average rating for Prop A = (90+80+85)/3 = 85
SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  85,
  'Average rating for Idea Alpha is 85'
);

-- Test 13: Average rating for Prop B = (60+70+65)/3 = 65
SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_b')::INT),
  65,
  'Average rating for Idea Beta is 65'
);

-- Test 14: Average rating for Prop G = (40+50+45)/3 = 45
SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_g')::INT),
  45,
  'Average rating for Idea Gamma is 45'
);

-- =============================================================================
-- WINNER CALCULATION
-- =============================================================================

-- Store proposition MOVDA ratings (normally done by MOVDA algorithm)
INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
SELECT proposition_id, current_setting('test.round_id')::INT, AVG(rating)
FROM ratings
WHERE proposition_id IN (
  current_setting('test.prop_a')::INT,
  current_setting('test.prop_b')::INT,
  current_setting('test.prop_g')::INT
)
GROUP BY proposition_id;

-- Test 15: proposition_movda_ratings calculated
SELECT is(
  (SELECT COUNT(*) FROM proposition_movda_ratings WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )),
  3::bigint,
  '3 proposition_movda_ratings calculated'
);

-- Test 16: Highest rated proposition is Idea Alpha
SELECT is(
  (SELECT proposition_id FROM proposition_movda_ratings
   WHERE proposition_id IN (
     current_setting('test.prop_a')::INT,
     current_setting('test.prop_b')::INT,
     current_setting('test.prop_g')::INT
   )
   ORDER BY rating DESC
   LIMIT 1),
  current_setting('test.prop_a')::bigint,
  'Highest rated proposition is Idea Alpha'
);

-- =============================================================================
-- ROUND COMPLETION
-- =============================================================================

-- Set winner (triggers auto-creation of next round)
UPDATE rounds
SET
  winning_proposition_id = current_setting('test.prop_a')::INT,
  completed_at = NOW()
WHERE id = current_setting('test.round_id')::INT;

-- Test 17: Round winner set
SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round_id')::INT),
  current_setting('test.prop_a')::bigint,
  'Round winner is Idea Alpha'
);

-- Test 18: Round marked as completed
SELECT isnt(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.round_id')::INT),
  NULL,
  'Round has completed_at timestamp'
);

-- Test 19: Next round auto-created (by trigger)
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
  2::bigint,
  'Second round auto-created by trigger'
);

-- Test 20: Second round starts in waiting phase (host must start it)
SELECT is(
  (SELECT phase FROM rounds
   WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 2),
  'waiting',
  'Second round starts in waiting phase'
);

-- =============================================================================
-- TIMER EXTENSION SCENARIO
-- =============================================================================

-- Get second round ID
DO $$
DECLARE
  v_round2_id INT;
BEGIN
  SELECT id INTO v_round2_id FROM rounds
  WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 2;
  PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- Simulate timer extension (edge function would do this)
UPDATE rounds
SET phase_ends_at = NOW() + INTERVAL '300 seconds'
WHERE id = current_setting('test.round2_id')::INT;

-- Test 21: Timer can be extended
SELECT ok(
  (SELECT phase_ends_at FROM rounds WHERE id = current_setting('test.round2_id')::INT) > NOW(),
  'Timer can be extended (phase_ends_at updated)'
);

-- =============================================================================
-- PHASE_ENDS_AT CONSTRAINTS
-- =============================================================================

-- Test 22: phase_ends_at can be NULL (waiting phase)
INSERT INTO rounds (cycle_id, custom_id, phase, phase_ends_at)
VALUES (current_setting('test.cycle_id')::INT, 99, 'waiting', NULL);

SELECT is(
  (SELECT phase_ends_at FROM rounds
   WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 99),
  NULL,
  'phase_ends_at can be NULL for waiting phase'
);

-- Clean up test round
DELETE FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 99;

-- Test 23: phase_ends_at can be in past (expired timer scenario)
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
VALUES (
  current_setting('test.cycle_id')::INT,
  98,
  'proposing',
  NOW() - INTERVAL '10 minutes',
  NOW() - INTERVAL '5 minutes'
);

SELECT ok(
  (SELECT phase_ends_at FROM rounds
   WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 98) < NOW(),
  'phase_ends_at can be in the past (expired timer)'
);

-- Clean up
DELETE FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 98;

-- =============================================================================
-- CYCLE NOT COMPLETE AFTER FIRST WIN
-- =============================================================================

-- Test 24: Cycle not complete after first round win
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle winner still NULL after first round (need 2-in-a-row)'
);

-- Test 25: Cycle not marked as completed
SELECT is(
  (SELECT completed_at FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL,
  'Cycle completed_at still NULL'
);

SELECT * FROM finish();
ROLLBACK;
