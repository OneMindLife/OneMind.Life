-- Test starting a chat by creating initial cycle and round
-- This mimics what the Dart startChat method does
BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- SETUP: Create a new chat without any cycle/round
-- =============================================================================

DO $$
BEGIN
  PERFORM set_config('test.host_token', gen_random_uuid()::TEXT, TRUE);
END $$;

-- Create a chat with manual start mode
INSERT INTO chats (
  name,
  initial_message,
  creator_session_token,
  start_mode,
  proposing_duration_seconds,
  rating_duration_seconds,
  proposing_minimum,
  rating_minimum
)
VALUES (
  'Start Chat Test',
  'Testing initial start',
  current_setting('test.host_token')::UUID,
  'manual',
  300,  -- 5 min proposing
  600,  -- 10 min rating
  3,    -- proposing_minimum (>=3 because users can't rate their own)
  2
);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Start Chat Test';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Create host participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (
  current_setting('test.chat_id')::INT,
  current_setting('test.host_token')::UUID,
  'Host User',
  TRUE,
  'active'
);

-- =============================================================================
-- TEST: Verify chat has no cycle or round initially
-- =============================================================================

-- Test 1: No cycle exists initially
SELECT is(
  (SELECT COUNT(*) FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
  0::bigint,
  'New chat has no cycles initially'
);

-- Test 2: No round exists initially (no cycles means no rounds)
SELECT is(
  (SELECT COUNT(*) FROM rounds r
   JOIN cycles c ON r.cycle_id = c.id
   WHERE c.chat_id = current_setting('test.chat_id')::INT),
  0::bigint,
  'New chat has no rounds initially'
);

-- =============================================================================
-- TEST: Create initial cycle (what startChat does)
-- =============================================================================

-- Insert cycle like startChat does
INSERT INTO cycles (chat_id)
VALUES (current_setting('test.chat_id')::INT);

DO $$
DECLARE
  v_cycle_id INT;
BEGIN
  SELECT id INTO v_cycle_id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
END $$;

-- Test 3: Cycle was created
SELECT is(
  (SELECT COUNT(*) FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
  1::bigint,
  'Cycle was created for chat'
);

-- Test 4: Cycle has no winner initially
SELECT is(
  (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL::bigint,
  'New cycle has no winner initially'
);

-- Test 5: Cycle is not completed
SELECT is(
  (SELECT completed_at FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
  NULL::timestamp with time zone,
  'New cycle is not completed'
);

-- =============================================================================
-- TEST: Create initial round in proposing phase (what startChat does)
-- =============================================================================

-- Insert round like startChat does - directly in proposing phase
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
VALUES (
  current_setting('test.cycle_id')::INT,
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
  WHERE cycle_id = current_setting('test.cycle_id')::INT AND custom_id = 1;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 6: Round was created
SELECT is(
  (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
  1::bigint,
  'Round was created for cycle'
);

-- Test 7: Round is in proposing phase (not waiting)
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::INT),
  'proposing',
  'Round starts directly in proposing phase'
);

-- Test 8: Round has phase_started_at set
SELECT ok(
  (SELECT phase_started_at FROM rounds WHERE id = current_setting('test.round_id')::INT) IS NOT NULL,
  'Round has phase_started_at set'
);

-- Test 9: Round has phase_ends_at set
SELECT ok(
  (SELECT phase_ends_at FROM rounds WHERE id = current_setting('test.round_id')::INT) IS NOT NULL,
  'Round has phase_ends_at set'
);

-- Test 10: Phase ends after phase starts
SELECT ok(
  (SELECT phase_ends_at > phase_started_at FROM rounds WHERE id = current_setting('test.round_id')::INT),
  'phase_ends_at is after phase_started_at'
);

-- Test 11: Round custom_id is 1
SELECT is(
  (SELECT custom_id FROM rounds WHERE id = current_setting('test.round_id')::INT),
  1,
  'First round has custom_id = 1'
);

-- =============================================================================
-- TEST: Verify we can now submit propositions
-- =============================================================================

-- Create a participant to submit proposition
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (
  current_setting('test.chat_id')::INT,
  gen_random_uuid(),
  'Test User',
  FALSE,
  'active'
);

DO $$
DECLARE
  v_participant_id INT;
BEGIN
  SELECT id INTO v_participant_id FROM participants
  WHERE chat_id = current_setting('test.chat_id')::INT AND display_name = 'Test User';
  PERFORM set_config('test.participant_id', v_participant_id::TEXT, TRUE);
END $$;

-- Submit a proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.round_id')::INT,
  current_setting('test.participant_id')::INT,
  'Test proposition after start'
);

-- Test 12: Proposition was inserted successfully
SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::INT),
  1::bigint,
  'Proposition can be submitted after chat is started'
);

SELECT * FROM finish();
ROLLBACK;
