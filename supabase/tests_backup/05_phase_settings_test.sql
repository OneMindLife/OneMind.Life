-- Phase advancement and timer settings tests
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(30);

-- =============================================================================
-- SETUP
-- =============================================================================

INSERT INTO users (id, email, display_name)
VALUES ('44444444-4444-4444-4444-444444444444', 'phasehost@example.com', 'Phase Host');

-- =============================================================================
-- DEFAULT TIMER SETTINGS
-- =============================================================================

-- Create chat with defaults
INSERT INTO chats (name, initial_message, creator_id)
VALUES ('Default Settings Chat', 'Testing defaults', '44444444-4444-4444-4444-444444444444');

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Default Settings Chat';
  PERFORM set_config('test.default_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 1: Default proposing_duration_seconds is 86400 (1 day)
SELECT extensions.is(
  (SELECT proposing_duration_seconds FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  86400,
  'Default proposing duration is 86400 seconds (1 day)'
);

-- Test 2: Default rating_duration_seconds is 86400 (1 day)
SELECT extensions.is(
  (SELECT rating_duration_seconds FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  86400,
  'Default rating duration is 86400 seconds (1 day)'
);

-- Test 3: Default proposing_minimum is 2
SELECT extensions.is(
  (SELECT proposing_minimum FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  2,
  'Default proposing minimum is 2'
);

-- Test 4: Default rating_minimum is 2
SELECT extensions.is(
  (SELECT rating_minimum FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  2,
  'Default rating minimum is 2'
);

-- Test 5: Default proposing_threshold_percent is NULL (disabled)
SELECT extensions.is(
  (SELECT proposing_threshold_percent FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  NULL,
  'Default proposing threshold percent is NULL (disabled)'
);

-- Test 6: Default rating_threshold_percent is NULL (disabled)
SELECT extensions.is(
  (SELECT rating_threshold_percent FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  NULL,
  'Default rating threshold percent is NULL (disabled)'
);

-- Test 7: Default start_mode is 'manual'
SELECT extensions.is(
  (SELECT start_mode FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  'manual',
  'Default start mode is manual'
);

-- Test 8: Default auto_start_participant_count is NULL
SELECT extensions.is(
  (SELECT auto_start_participant_count FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  NULL,
  'Default auto start count is NULL'
);

-- =============================================================================
-- CUSTOM TIMER SETTINGS
-- =============================================================================

-- Create chat with custom timers
INSERT INTO chats (
  name,
  initial_message,
  creator_id,
  proposing_duration_seconds,
  rating_duration_seconds
)
VALUES (
  'Custom Timer Chat',
  'Custom timers',
  '44444444-4444-4444-4444-444444444444',
  300,    -- 5 minutes
  1800    -- 30 minutes
);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Custom Timer Chat';
  PERFORM set_config('test.custom_timer_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 9: Custom proposing duration set
SELECT extensions.is(
  (SELECT proposing_duration_seconds FROM chats WHERE id = current_setting('test.custom_timer_chat_id')::INT),
  300,
  'Custom proposing duration is 300 seconds (5 min)'
);

-- Test 10: Custom rating duration set
SELECT extensions.is(
  (SELECT rating_duration_seconds FROM chats WHERE id = current_setting('test.custom_timer_chat_id')::INT),
  1800,
  'Custom rating duration is 1800 seconds (30 min)'
);

-- =============================================================================
-- MINIMUM SETTINGS
-- =============================================================================

-- Create chat with custom minimums
INSERT INTO chats (
  name,
  initial_message,
  creator_id,
  proposing_minimum,
  rating_minimum
)
VALUES (
  'Custom Minimum Chat',
  'Custom minimums',
  '44444444-4444-4444-4444-444444444444',
  5,
  10
);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Custom Minimum Chat';
  PERFORM set_config('test.custom_min_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 11: Custom proposing minimum
SELECT extensions.is(
  (SELECT proposing_minimum FROM chats WHERE id = current_setting('test.custom_min_chat_id')::INT),
  5,
  'Custom proposing minimum is 5'
);

-- Test 12: Custom rating minimum
SELECT extensions.is(
  (SELECT rating_minimum FROM chats WHERE id = current_setting('test.custom_min_chat_id')::INT),
  10,
  'Custom rating minimum is 10'
);

-- =============================================================================
-- AUTO-ADVANCE THRESHOLDS
-- =============================================================================

-- Create chat with auto-advance enabled
INSERT INTO chats (
  name,
  initial_message,
  creator_id,
  proposing_threshold_percent,
  proposing_threshold_count,
  rating_threshold_percent,
  rating_threshold_count
)
VALUES (
  'Auto Advance Chat',
  'With thresholds',
  '44444444-4444-4444-4444-444444444444',
  80,   -- 80%
  5,    -- minimum 5
  75,   -- 75%
  3     -- minimum 3
);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Auto Advance Chat';
  PERFORM set_config('test.auto_advance_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 13: Proposing threshold percent set
SELECT extensions.is(
  (SELECT proposing_threshold_percent FROM chats WHERE id = current_setting('test.auto_advance_chat_id')::INT),
  80,
  'Proposing threshold percent is 80'
);

-- Test 14: Proposing threshold count set
SELECT extensions.is(
  (SELECT proposing_threshold_count FROM chats WHERE id = current_setting('test.auto_advance_chat_id')::INT),
  5,
  'Proposing threshold count is 5'
);

-- Test 15: Rating threshold percent set
SELECT extensions.is(
  (SELECT rating_threshold_percent FROM chats WHERE id = current_setting('test.auto_advance_chat_id')::INT),
  75,
  'Rating threshold percent is 75'
);

-- Test 16: Rating threshold count set
SELECT extensions.is(
  (SELECT rating_threshold_count FROM chats WHERE id = current_setting('test.auto_advance_chat_id')::INT),
  3,
  'Rating threshold count is 3'
);

-- =============================================================================
-- START MODE SETTINGS
-- =============================================================================

-- Test 17: Manual start mode
SELECT extensions.is(
  (SELECT start_mode FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  'manual',
  'Start mode is manual'
);

-- Create chat with auto start
INSERT INTO chats (
  name,
  initial_message,
  creator_id,
  start_mode,
  auto_start_participant_count
)
VALUES (
  'Auto Start Chat',
  'Starts automatically',
  '44444444-4444-4444-4444-444444444444',
  'auto',
  10
);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Auto Start Chat';
  PERFORM set_config('test.auto_start_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 18: Auto start mode set
SELECT extensions.is(
  (SELECT start_mode FROM chats WHERE id = current_setting('test.auto_start_chat_id')::INT),
  'auto',
  'Start mode is auto'
);

-- Test 19: Auto start participant count set
SELECT extensions.is(
  (SELECT auto_start_participant_count FROM chats WHERE id = current_setting('test.auto_start_chat_id')::INT),
  10,
  'Auto start participant count is 10'
);

-- =============================================================================
-- AI PARTICIPANT SETTINGS
-- =============================================================================

-- Test 20: Default AI disabled
SELECT extensions.is(
  (SELECT enable_ai_participant FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  FALSE,
  'AI participant disabled by default'
);

-- Create chat with AI enabled
INSERT INTO chats (
  name,
  initial_message,
  creator_id,
  enable_ai_participant,
  ai_propositions_count
)
VALUES (
  'AI Chat',
  'With AI participant',
  '44444444-4444-4444-4444-444444444444',
  TRUE,
  5
);

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'AI Chat';
  PERFORM set_config('test.ai_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test 21: AI enabled
SELECT extensions.is(
  (SELECT enable_ai_participant FROM chats WHERE id = current_setting('test.ai_chat_id')::INT),
  TRUE,
  'AI participant enabled'
);

-- Test 22: AI propositions count set
SELECT extensions.is(
  (SELECT ai_propositions_count FROM chats WHERE id = current_setting('test.ai_chat_id')::INT),
  5,
  'AI propositions count is 5'
);

-- =============================================================================
-- ITERATION PHASE TRACKING
-- =============================================================================

-- Setup cycle and iteration
INSERT INTO cycles (chat_id, custom_id)
VALUES (current_setting('test.default_chat_id')::INT, 1);

DO $$
DECLARE
  v_cycle_id INT;
BEGIN
  SELECT id INTO v_cycle_id FROM cycles WHERE chat_id = current_setting('test.default_chat_id')::INT;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
END $$;

INSERT INTO iterations (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 1, 'proposing');

DO $$
DECLARE
  v_iter_id INT;
BEGIN
  SELECT id INTO v_iter_id FROM iterations WHERE cycle_id = current_setting('test.cycle_id')::INT;
  PERFORM set_config('test.iteration_id', v_iter_id::TEXT, TRUE);
END $$;

-- Test 23: Iteration starts in waiting/proposing phase
SELECT extensions.is(
  (SELECT phase FROM iterations WHERE id = current_setting('test.iteration_id')::INT),
  'proposing',
  'Iteration starts in proposing phase'
);

-- Test 24: Can transition to rating phase
UPDATE iterations SET phase = 'rating' WHERE id = current_setting('test.iteration_id')::INT;

SELECT extensions.is(
  (SELECT phase FROM iterations WHERE id = current_setting('test.iteration_id')::INT),
  'rating',
  'Iteration transitioned to rating phase'
);

-- Test 25: phase_started_at can be set
UPDATE iterations
SET phase_started_at = NOW()
WHERE id = current_setting('test.iteration_id')::INT;

SELECT extensions.isnt(
  (SELECT phase_started_at FROM iterations WHERE id = current_setting('test.iteration_id')::INT),
  NULL,
  'phase_started_at can be set'
);

-- =============================================================================
-- TIMER PRESET VALUES
-- =============================================================================

-- Test 26: 5 minute preset (300 seconds)
INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
VALUES ('5min Chat', 'Topic', 'session-5min', 300);

SELECT extensions.is(
  (SELECT proposing_duration_seconds FROM chats WHERE name = '5min Chat'),
  300,
  '5 minute preset = 300 seconds'
);

-- Test 27: 30 minute preset (1800 seconds)
INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
VALUES ('30min Chat', 'Topic', 'session-30min', 1800);

SELECT extensions.is(
  (SELECT proposing_duration_seconds FROM chats WHERE name = '30min Chat'),
  1800,
  '30 minute preset = 1800 seconds'
);

-- Test 28: 1 hour preset (3600 seconds)
INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
VALUES ('1hour Chat', 'Topic', 'session-1hour', 3600);

SELECT extensions.is(
  (SELECT proposing_duration_seconds FROM chats WHERE name = '1hour Chat'),
  3600,
  '1 hour preset = 3600 seconds'
);

-- Test 29: 1 day preset (86400 seconds)
SELECT extensions.is(
  (SELECT proposing_duration_seconds FROM chats WHERE id = current_setting('test.default_chat_id')::INT),
  86400,
  '1 day preset = 86400 seconds'
);

-- Test 30: 7 day preset (604800 seconds)
INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
VALUES ('7day Chat', 'Topic', 'session-7day', 604800);

SELECT extensions.is(
  (SELECT proposing_duration_seconds FROM chats WHERE name = '7day Chat'),
  604800,
  '7 day preset = 604800 seconds'
);

SELECT * FROM finish();
ROLLBACK;
