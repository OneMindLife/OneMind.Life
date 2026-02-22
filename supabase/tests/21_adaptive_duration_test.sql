-- Adaptive Duration Tests
-- Tests for automatic phase duration adjustment based on participation
-- Uses existing early advance thresholds instead of separate adaptive_threshold_count
BEGIN;
SET search_path TO public, extensions;
SELECT plan(21);

-- =============================================================================
-- DEFAULT VALUES
-- =============================================================================

-- Test 1: Default adaptive_duration_enabled is FALSE
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Default Duration Chat', 'Testing defaults', gen_random_uuid());

SELECT is(
  (SELECT adaptive_duration_enabled FROM chats WHERE name = 'Default Duration Chat'),
  FALSE,
  'Default adaptive_duration_enabled is FALSE'
);

-- Test 2: Default adaptive_adjustment_percent is 10
SELECT is(
  (SELECT adaptive_adjustment_percent FROM chats WHERE name = 'Default Duration Chat'),
  10,
  'Default adaptive_adjustment_percent is 10'
);

-- Test 3: Default min_phase_duration_seconds is 60
SELECT is(
  (SELECT min_phase_duration_seconds FROM chats WHERE name = 'Default Duration Chat'),
  60,
  'Default min_phase_duration_seconds is 60 (1 minute)'
);

-- Test 4: Default max_phase_duration_seconds is 86400
SELECT is(
  (SELECT max_phase_duration_seconds FROM chats WHERE name = 'Default Duration Chat'),
  86400,
  'Default max_phase_duration_seconds is 86400 (1 day)'
);

-- =============================================================================
-- CUSTOM VALUES
-- =============================================================================

-- Test 5: Can set custom adaptive settings with early advance thresholds
INSERT INTO chats (
  name, initial_message, creator_session_token,
  adaptive_duration_enabled, adaptive_adjustment_percent,
  min_phase_duration_seconds, max_phase_duration_seconds,
  proposing_threshold_count, rating_threshold_count
)
VALUES (
  'Custom Adaptive Chat', 'Custom settings', gen_random_uuid(),
  TRUE, 15, 120, 3600, 5, 5
);

SELECT is(
  (SELECT adaptive_duration_enabled FROM chats WHERE name = 'Custom Adaptive Chat'),
  TRUE,
  'adaptive_duration_enabled can be set to TRUE'
);

-- Test 6: Custom adjustment percent
SELECT is(
  (SELECT adaptive_adjustment_percent FROM chats WHERE name = 'Custom Adaptive Chat'),
  15,
  'adaptive_adjustment_percent can be set to 15'
);

-- =============================================================================
-- CONSTRAINTS
-- =============================================================================

-- Test 7: adaptive_adjustment_percent must be >= 1
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, adaptive_adjustment_percent)
    VALUES ('Bad Chat', 'Zero adjustment', gen_random_uuid(), 0)$$,
  '23514',
  NULL,
  'adaptive_adjustment_percent cannot be 0'
);

-- Test 8: adaptive_adjustment_percent must be <= 50
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, adaptive_adjustment_percent)
    VALUES ('Bad Chat', 'High adjustment', gen_random_uuid(), 51)$$,
  '23514',
  NULL,
  'adaptive_adjustment_percent cannot exceed 50'
);

-- Test 9: min_phase_duration_seconds must be >= 60 (cron granularity)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, min_phase_duration_seconds)
    VALUES ('Bad Chat', 'Low min', gen_random_uuid(), 59)$$,
  '23514',
  NULL,
  'min_phase_duration_seconds must be at least 60 (cron granularity)'
);

-- Test 10: max_phase_duration_seconds must be >= min_phase_duration_seconds
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, min_phase_duration_seconds, max_phase_duration_seconds)
    VALUES ('Bad Chat', 'Max less than min', gen_random_uuid(), 120, 60)$$,
  '23514',
  NULL,
  'max_phase_duration_seconds must be >= min_phase_duration_seconds'
);

-- =============================================================================
-- CALCULATE_ADAPTIVE_DURATION FUNCTION
-- =============================================================================

-- Test 11: Decrease duration when participation meets threshold (rounds to nearest minute)
-- 1000 * 0.9 = 900 → ROUND(900/60) = 15 → 900 (already aligned)
SELECT is(
  calculate_adaptive_duration(1000, 10, 10, 10, 60, 86400),
  900,
  'Duration decreased by 10% when participation (10) meets threshold (10)'
);

-- Test 12: Decrease duration when participation exceeds threshold
SELECT is(
  calculate_adaptive_duration(1000, 15, 10, 10, 60, 86400),
  900,
  'Duration decreased by 10% when participation (15) exceeds threshold (10)'
);

-- Test 13: Increase duration when participation below threshold (rounds to nearest minute)
-- 1000 * 1.1 = 1100 → ROUND(1100/60) = 18.33 → 18 → 1080
SELECT is(
  calculate_adaptive_duration(1000, 5, 10, 10, 60, 86400),
  1080,
  'Duration increased by 10% when participation below threshold (1100 → 1080 rounded)'
);

-- Test 14: Different adjustment percent (20%) - rounds to nearest minute
-- 1000 * 0.8 = 800 → ROUND(800/60) = 13.33 → 13 → 780
SELECT is(
  calculate_adaptive_duration(1000, 10, 10, 20, 60, 86400),
  780,
  'Duration decreased by 20% with 20% adjustment (800 → 780 rounded)'
);

-- Test 15: Floor is enforced
SELECT is(
  calculate_adaptive_duration(100, 10, 10, 50, 60, 86400),
  60,
  'Duration cannot go below min_phase_duration_seconds (60)'
);

-- Test 16: Ceiling is enforced
SELECT is(
  calculate_adaptive_duration(80000, 5, 10, 10, 60, 86400),
  86400,
  'Duration cannot exceed max_phase_duration_seconds (86400)'
);

-- =============================================================================
-- COUNT_ROUND_PARTICIPATION FUNCTION
-- =============================================================================

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1_id INT;
  v_p2_id INT;
  v_p3_id INT;
  v_prop1_id INT;
  v_prop2_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Custom Adaptive Chat';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_round_id;

  -- Create 3 participants
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active')
  RETURNING id INTO v_p1_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P2', FALSE, 'active')
  RETURNING id INTO v_p2_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P3', FALSE, 'active')
  RETURNING id INTO v_p3_id;

  -- P1 and P2 submit propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_p1_id, 'Prop from P1')
  RETURNING id INTO v_prop1_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_p2_id, 'Prop from P2')
  RETURNING id INTO v_prop2_id;

  PERFORM set_config('test.adaptive_round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.p1_id', v_p1_id::TEXT, TRUE);
  PERFORM set_config('test.p2_id', v_p2_id::TEXT, TRUE);
  PERFORM set_config('test.p3_id', v_p3_id::TEXT, TRUE);
  PERFORM set_config('test.prop1_id', v_prop1_id::TEXT, TRUE);
  PERFORM set_config('test.prop2_id', v_prop2_id::TEXT, TRUE);
END $$;

-- Test 17: Count proposing participants correctly (2 proposers)
SELECT is(
  (SELECT proposing_count FROM count_round_participation(current_setting('test.adaptive_round_id')::INT)),
  2,
  'count_round_participation returns correct proposing_count (2)'
);

-- Add grid rankings from all 3 participants (grid_position is 0-100)
DO $$
DECLARE
  v_round_id INT := current_setting('test.adaptive_round_id')::INT;
  v_p1_id INT := current_setting('test.p1_id')::INT;
  v_p2_id INT := current_setting('test.p2_id')::INT;
  v_p3_id INT := current_setting('test.p3_id')::INT;
  v_prop1_id INT := current_setting('test.prop1_id')::INT;
  v_prop2_id INT := current_setting('test.prop2_id')::INT;
BEGIN
  -- All 3 participants submit rankings for prop1
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  VALUES
    (v_round_id, v_p1_id, v_prop1_id, 80.0),
    (v_round_id, v_p2_id, v_prop1_id, 70.0),
    (v_round_id, v_p3_id, v_prop1_id, 90.0);
  -- All 3 participants also rank prop2
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  VALUES
    (v_round_id, v_p1_id, v_prop2_id, 40.0),
    (v_round_id, v_p2_id, v_prop2_id, 50.0),
    (v_round_id, v_p3_id, v_prop2_id, 30.0);
END $$;

-- Test 18: Count rating participants correctly (3 raters)
SELECT is(
  (SELECT rating_count FROM count_round_participation(current_setting('test.adaptive_round_id')::INT)),
  3,
  'count_round_participation returns correct rating_count (3)'
);

-- =============================================================================
-- APPLY_ADAPTIVE_DURATION FUNCTION
-- Uses existing early advance thresholds for determining adjustment
-- =============================================================================

-- Create a chat with adaptive duration enabled and early advance thresholds
INSERT INTO chats (
  name, initial_message, creator_session_token,
  adaptive_duration_enabled, adaptive_adjustment_percent,
  min_phase_duration_seconds, max_phase_duration_seconds,
  proposing_duration_seconds, rating_duration_seconds,
  proposing_threshold_count, rating_threshold_count
)
VALUES (
  'Adaptive Test Chat', 'Test adaptive', gen_random_uuid(),
  TRUE, 10, 60, 86400, 300, 300, 5, 5
);

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1_id INT;
  v_p2_id INT;
  v_p3_id INT;
  v_p4_id INT;
  v_p5_id INT;
  v_prop1_id INT;
  v_prop2_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Adaptive Test Chat';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating')
  RETURNING id INTO v_round_id;

  -- Create 5 participants (meeting threshold of 5)
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active')
  RETURNING id INTO v_p1_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P2', FALSE, 'active')
  RETURNING id INTO v_p2_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P3', FALSE, 'active')
  RETURNING id INTO v_p3_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P4', FALSE, 'active')
  RETURNING id INTO v_p4_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'P5', FALSE, 'active')
  RETURNING id INTO v_p5_id;

  -- 5 participants submit propositions (meets proposing_threshold_count of 5)
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_p1_id, 'Prop 1')
  RETURNING id INTO v_prop1_id;

  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p2_id, 'Prop 2');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p3_id, 'Prop 3');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p4_id, 'Prop 4');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p5_id, 'Prop 5')
  RETURNING id INTO v_prop2_id;

  PERFORM set_config('test.adaptive_test_chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.adaptive_test_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 19: apply_adaptive_duration adjusts proposing duration when threshold met
-- 5 proposers >= 5 threshold → decrease by 10%
-- 300 * 0.9 = 270 → ROUND(270/60) = 4.5 → 5 → 300
SELECT is(
  (SELECT new_proposing_duration FROM apply_adaptive_duration(current_setting('test.adaptive_test_round_id')::INT)),
  300,  -- 300 * 0.9 = 270 → rounds to 300 (nearest minute)
  'apply_adaptive_duration rounds proposing to nearest minute (270 → 300)'
);

-- Test 20: Chat durations updated after apply_adaptive_duration
SELECT is(
  (SELECT proposing_duration_seconds FROM chats WHERE name = 'Adaptive Test Chat'),
  300,
  'Chat proposing_duration_seconds updated to 300 (minute-rounded)'
);

-- Test 21: Rating duration also adjusted based on its own threshold
-- Rating count is 0 (no grid_rankings) < 5 threshold → increase by 10%
-- 300 * 1.1 = 330 → ROUND(330/60) = 5.5 → 6 → 360
SELECT is(
  (SELECT rating_duration_seconds FROM chats WHERE name = 'Adaptive Test Chat'),
  360,
  'Chat rating_duration_seconds increased to 360 (low participation)'
);

SELECT * FROM finish();
ROLLBACK;
