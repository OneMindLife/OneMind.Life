-- Rating start mode tests
-- Tests for the rating_start_mode feature which allows decoupling when rating
-- starts from when proposing ends. When rating_start_mode='manual', the round
-- goes to a 'waiting' state (with propositions) instead of directly to rating.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(11);

-- =============================================================================
-- SETUP: Create test chats with different rating_start_mode settings
-- =============================================================================

-- Chat with rating_start_mode = 'auto' (default behavior)
INSERT INTO chats (
  name,
  initial_message,
  creator_session_token,
  proposing_duration_seconds,
  rating_duration_seconds,
  proposing_minimum,
  rating_minimum,
  rating_start_mode,
  proposing_threshold_count  -- Need threshold for early advance tests
)
VALUES (
  'Auto Rating Mode Chat',
  'Testing auto rating start',
  gen_random_uuid(),
  300, 300, 3, 2,
  'auto',
  3  -- Advance when 3 propositions submitted
);

-- Chat with rating_start_mode = 'manual'
INSERT INTO chats (
  name,
  initial_message,
  creator_session_token,
  proposing_duration_seconds,
  rating_duration_seconds,
  proposing_minimum,
  rating_minimum,
  rating_start_mode,
  proposing_threshold_count
)
VALUES (
  'Manual Rating Mode Chat',
  'Testing manual rating start',
  gen_random_uuid(),
  300, 300, 3, 2,
  'manual',
  3
);

DO $$
DECLARE
  v_auto_chat_id INT;
  v_manual_chat_id INT;
BEGIN
  SELECT id INTO v_auto_chat_id FROM chats WHERE name = 'Auto Rating Mode Chat';
  SELECT id INTO v_manual_chat_id FROM chats WHERE name = 'Manual Rating Mode Chat';
  PERFORM set_config('test.auto_chat_id', v_auto_chat_id::TEXT, TRUE);
  PERFORM set_config('test.manual_chat_id', v_manual_chat_id::TEXT, TRUE);
END $$;

-- Create cycles for both chats
INSERT INTO cycles (chat_id) VALUES (current_setting('test.auto_chat_id')::INT);
INSERT INTO cycles (chat_id) VALUES (current_setting('test.manual_chat_id')::INT);

DO $$
DECLARE
  v_auto_cycle_id INT;
  v_manual_cycle_id INT;
BEGIN
  SELECT id INTO v_auto_cycle_id FROM cycles WHERE chat_id = current_setting('test.auto_chat_id')::INT;
  SELECT id INTO v_manual_cycle_id FROM cycles WHERE chat_id = current_setting('test.manual_chat_id')::INT;
  PERFORM set_config('test.auto_cycle_id', v_auto_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.manual_cycle_id', v_manual_cycle_id::TEXT, TRUE);
END $$;

-- Create participants for auto chat
DO $$
DECLARE
  v_p1 INT; v_p2 INT; v_p3 INT;
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.auto_chat_id')::INT, gen_random_uuid(), 'Auto User 1', TRUE, 'active')
  RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.auto_chat_id')::INT, gen_random_uuid(), 'Auto User 2', FALSE, 'active')
  RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.auto_chat_id')::INT, gen_random_uuid(), 'Auto User 3', FALSE, 'active')
  RETURNING id INTO v_p3;
  PERFORM set_config('test.auto_p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.auto_p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.auto_p3', v_p3::TEXT, TRUE);
END $$;

-- Create participants for manual chat
DO $$
DECLARE
  v_p1 INT; v_p2 INT; v_p3 INT;
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.manual_chat_id')::INT, gen_random_uuid(), 'Manual User 1', TRUE, 'active')
  RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.manual_chat_id')::INT, gen_random_uuid(), 'Manual User 2', FALSE, 'active')
  RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.manual_chat_id')::INT, gen_random_uuid(), 'Manual User 3', FALSE, 'active')
  RETURNING id INTO v_p3;
  PERFORM set_config('test.manual_p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.manual_p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.manual_p3', v_p3::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST: is_round_waiting_for_rating() function
-- =============================================================================

-- Create a round in waiting phase WITHOUT propositions (waiting for proposing)
INSERT INTO rounds (cycle_id, custom_id, phase)
VALUES (current_setting('test.manual_cycle_id')::INT, 1, 'waiting');

DO $$
DECLARE
  v_round_id INT;
BEGIN
  SELECT id INTO v_round_id FROM rounds
  WHERE cycle_id = current_setting('test.manual_cycle_id')::INT AND custom_id = 1;
  PERFORM set_config('test.waiting_round_id', v_round_id::TEXT, TRUE);
END $$;

SELECT is(
  is_round_waiting_for_rating(current_setting('test.waiting_round_id')::INT),
  FALSE,
  'is_round_waiting_for_rating returns FALSE for waiting phase without propositions'
);

-- Add propositions to make it "waiting for rating"
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.waiting_round_id')::INT, current_setting('test.manual_p1')::INT, 'Prop 1'),
  (current_setting('test.waiting_round_id')::INT, current_setting('test.manual_p2')::INT, 'Prop 2');

SELECT is(
  is_round_waiting_for_rating(current_setting('test.waiting_round_id')::INT),
  TRUE,
  'is_round_waiting_for_rating returns TRUE for waiting phase WITH propositions'
);

-- Test with a round in proposing phase (should return FALSE)
UPDATE rounds SET phase = 'proposing', phase_started_at = NOW(), phase_ends_at = NOW() + INTERVAL '5 minutes'
WHERE id = current_setting('test.waiting_round_id')::INT;

SELECT is(
  is_round_waiting_for_rating(current_setting('test.waiting_round_id')::INT),
  FALSE,
  'is_round_waiting_for_rating returns FALSE for proposing phase'
);

-- Test with a round in rating phase (should return FALSE)
UPDATE rounds SET phase = 'rating'
WHERE id = current_setting('test.waiting_round_id')::INT;

SELECT is(
  is_round_waiting_for_rating(current_setting('test.waiting_round_id')::INT),
  FALSE,
  'is_round_waiting_for_rating returns FALSE for rating phase'
);

-- =============================================================================
-- TEST: advance_proposing_to_waiting() function
-- =============================================================================

-- Reset round to proposing for this test
UPDATE rounds SET phase = 'proposing', phase_started_at = NOW(), phase_ends_at = NOW() + INTERVAL '5 minutes'
WHERE id = current_setting('test.waiting_round_id')::INT;

-- Should work for manual mode chat
SELECT lives_ok(
  format('SELECT advance_proposing_to_waiting(%s)', current_setting('test.waiting_round_id')::INT),
  'advance_proposing_to_waiting succeeds for manual rating_start_mode'
);

-- Verify the round is now in waiting phase
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.waiting_round_id')::INT),
  'waiting',
  'advance_proposing_to_waiting sets phase to waiting'
);

SELECT is(
  (SELECT phase_started_at FROM rounds WHERE id = current_setting('test.waiting_round_id')::INT),
  NULL,
  'advance_proposing_to_waiting clears phase_started_at'
);

SELECT is(
  (SELECT phase_ends_at FROM rounds WHERE id = current_setting('test.waiting_round_id')::INT),
  NULL,
  'advance_proposing_to_waiting clears phase_ends_at'
);

-- =============================================================================
-- TEST: Early advance trigger with rating_start_mode='auto'
-- =============================================================================

-- Create round for auto chat in proposing phase
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
VALUES (
  current_setting('test.auto_cycle_id')::INT,
  1,
  'proposing',
  NOW(),
  NOW() + INTERVAL '5 minutes'
);

DO $$
DECLARE
  v_round_id INT;
BEGIN
  SELECT id INTO v_round_id FROM rounds
  WHERE cycle_id = current_setting('test.auto_cycle_id')::INT AND custom_id = 1;
  PERFORM set_config('test.auto_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Submit 3 propositions (meeting threshold) - should auto-advance to RATING
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.auto_round_id')::INT, current_setting('test.auto_p1')::INT, 'Auto Prop 1'),
  (current_setting('test.auto_round_id')::INT, current_setting('test.auto_p2')::INT, 'Auto Prop 2'),
  (current_setting('test.auto_round_id')::INT, current_setting('test.auto_p3')::INT, 'Auto Prop 3');

SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.auto_round_id')::INT),
  'rating',
  'With rating_start_mode=auto, meeting threshold advances directly to rating phase'
);

-- =============================================================================
-- TEST: Early advance trigger with rating_start_mode='manual'
-- =============================================================================

-- Create another round for manual chat in proposing phase
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
VALUES (
  current_setting('test.manual_cycle_id')::INT,
  2,
  'proposing',
  NOW(),
  NOW() + INTERVAL '5 minutes'
);

DO $$
DECLARE
  v_round_id INT;
BEGIN
  SELECT id INTO v_round_id FROM rounds
  WHERE cycle_id = current_setting('test.manual_cycle_id')::INT AND custom_id = 2;
  PERFORM set_config('test.manual_round_2_id', v_round_id::TEXT, TRUE);
END $$;

-- Submit 3 propositions (meeting threshold) - should advance to WAITING (not rating)
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.manual_round_2_id')::INT, current_setting('test.manual_p1')::INT, 'Manual Prop 1'),
  (current_setting('test.manual_round_2_id')::INT, current_setting('test.manual_p2')::INT, 'Manual Prop 2'),
  (current_setting('test.manual_round_2_id')::INT, current_setting('test.manual_p3')::INT, 'Manual Prop 3');

SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.manual_round_2_id')::INT),
  'waiting',
  'With rating_start_mode=manual, meeting threshold advances to waiting phase (not rating)'
);

-- And it should be detected as waiting for rating
SELECT is(
  is_round_waiting_for_rating(current_setting('test.manual_round_2_id')::INT),
  TRUE,
  'After early advance with manual mode, is_round_waiting_for_rating returns TRUE'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
