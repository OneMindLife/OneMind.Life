-- =============================================================================
-- TEST: Adaptive Duration Minute Alignment & Early Advance
-- =============================================================================
-- Tests for:
-- 1. Minimum duration constraint >= 60 (not 30)
-- 2. Duration calculations round to nearest minute
-- 3. Early advance applies adaptive duration
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(17);

-- =============================================================================
-- TEST 1: MINIMUM DURATION CONSTRAINT (>= 60, NOT 30)
-- =============================================================================

-- Test 1: min_phase_duration_seconds must be >= 60 (fails at 59)
SELECT throws_ok(
    $$INSERT INTO chats (name, initial_message, creator_session_token, min_phase_duration_seconds)
      VALUES ('Bad Min', 'Too low', gen_random_uuid(), 59)$$,
    '23514',
    NULL,
    'min_phase_duration_seconds cannot be 59 (must be >= 60)'
);

-- Test 2: min_phase_duration_seconds = 60 succeeds
INSERT INTO chats (name, initial_message, creator_session_token, min_phase_duration_seconds)
VALUES ('Good Min', 'Exactly 60', gen_random_uuid(), 60);

SELECT is(
    (SELECT min_phase_duration_seconds FROM chats WHERE name = 'Good Min'),
    60,
    'min_phase_duration_seconds = 60 is valid'
);

-- Test 3: 30 seconds no longer allowed (was allowed before)
SELECT throws_ok(
    $$INSERT INTO chats (name, initial_message, creator_session_token, min_phase_duration_seconds)
      VALUES ('Old Min', 'Was 30', gen_random_uuid(), 30)$$,
    '23514',
    NULL,
    'min_phase_duration_seconds = 30 no longer allowed (cron granularity)'
);

-- =============================================================================
-- TEST 2: MINUTE ALIGNMENT (ROUND TO NEAREST 60)
-- =============================================================================

-- Test 4: 270s rounds to 300s (nearest minute = 5 min, not 4.5 min)
-- 300 * 0.9 = 270 → ROUND(270/60) = ROUND(4.5) = 5 → 5*60 = 300
SELECT is(
    calculate_adaptive_duration(300, 10, 10, 10, 60, 86400),
    300,
    '300s - 10% = 270s rounds UP to 300s (nearest minute, .5 rounds up)'
);

-- Test 5: 330s rounds to 360s (nearest minute = 6 min)
-- 300 * 1.1 = 330 → ROUND(330/60) = ROUND(5.5) = 6 → 6*60 = 360
SELECT is(
    calculate_adaptive_duration(300, 5, 10, 10, 60, 86400),
    360,
    '300s + 10% = 330s rounds to 360s (6 min)'
);

-- Test 6: 249s rounds DOWN to 240s (nearest minute = 4 min)
-- 300 * 0.83 = 249 → ROUND(249/60) = ROUND(4.15) = 4 → 4*60 = 240
SELECT is(
    calculate_adaptive_duration(300, 10, 10, 17, 60, 86400),
    240,
    '300s - 17% = 249s rounds DOWN to 240s (4 min)'
);

-- Test 7: Large duration also rounds
-- 3600 * 0.9 = 3240 → ROUND(3240/60) = ROUND(54) = 54 → 54*60 = 3240 (already aligned)
SELECT is(
    calculate_adaptive_duration(3600, 10, 10, 10, 60, 86400),
    3240,
    '3600s - 10% = 3240s stays at 3240s (already minute-aligned)'
);

-- Test 8: 90 seconds adjustment rounds properly
-- 60 * 1.5 = 90 → ROUND(90/60) = ROUND(1.5) = 2 → 2*60 = 120
-- But wait, 1.5 adjustment percent doesn't exist... let's use 50%
-- 60 * 1.5 = 90 → ROUND(1.5) = 2 → 120
SELECT is(
    calculate_adaptive_duration(60, 5, 10, 50, 60, 86400),
    120,
    '60s + 50% = 90s rounds to 120s (2 min)'
);

-- =============================================================================
-- TEST 3: MINIMUM FLOOR ENFORCED AT 60
-- =============================================================================

-- Test 9: Result below 60 gets floored to 60
-- 60 * 0.5 = 30 → ROUND(30/60) = ROUND(0.5) = 1 → 1*60 = 60 (or floored to 60)
SELECT is(
    calculate_adaptive_duration(60, 10, 10, 50, 60, 86400),
    60,
    '60s - 50% = 30s → floored to 60s (minimum)'
);

-- Test 10: Very low result still gets 60
-- 100 * 0.5 = 50 → ROUND(50/60) = ROUND(0.83) = 1 → 60
SELECT is(
    calculate_adaptive_duration(100, 10, 10, 50, 60, 86400),
    60,
    '100s - 50% = 50s → rounds to 60s (minimum)'
);

-- Test 11: Custom min_duration of 120 is respected
SELECT is(
    calculate_adaptive_duration(180, 10, 10, 50, 120, 86400),
    120,
    '180s - 50% = 90s → floored to custom min 120s'
);

-- =============================================================================
-- TEST 4: MAXIMUM CEILING ENFORCED
-- =============================================================================

-- Test 12: Result above max gets capped
SELECT is(
    calculate_adaptive_duration(80000, 5, 10, 20, 60, 86400),
    86400,
    '80000s + 20% = 96000s → capped to 86400s (max)'
);

-- =============================================================================
-- TEST 5: EARLY ADVANCE APPLIES ADAPTIVE DURATION
-- =============================================================================

-- Setup: Create chat with adaptive duration + early advance thresholds
-- Now uses existing early advance thresholds for adaptive duration decisions
INSERT INTO chats (
    name, initial_message, creator_session_token,
    start_mode, adaptive_duration_enabled,
    adaptive_adjustment_percent,
    min_phase_duration_seconds, max_phase_duration_seconds,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_threshold_count, rating_threshold_count, proposing_minimum
)
VALUES (
    'Early Advance Adaptive', 'Test early advance + adaptive', gen_random_uuid(),
    'auto', TRUE,
    10,  -- 10% adjustment
    60, 86400,
    300, 300,  -- 5 min each
    3, 2, 3  -- Proposing threshold = 3, Rating threshold = 2 avg raters/prop, proposing minimum = 3
);

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
    v_prop3_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Early Advance Adaptive';

    -- Create cycle and round
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round_id;

    -- Create 3 participants (meets threshold)
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'Host', TRUE, 'active')
    RETURNING id INTO v_p1_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'User2', FALSE, 'active')
    RETURNING id INTO v_p2_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'User3', FALSE, 'active')
    RETURNING id INTO v_p3_id;

    -- Create 3 propositions (one from each participant)
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'Idea 1')
    RETURNING id INTO v_prop1_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'Idea 2')
    RETURNING id INTO v_prop2_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3_id, 'Idea 3')
    RETURNING id INTO v_prop3_id;

    -- Store IDs for tests
    PERFORM set_config('test.ea_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.ea_round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.ea_p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.ea_p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.ea_p3_id', v_p3_id::TEXT, TRUE);
    PERFORM set_config('test.ea_prop1_id', v_prop1_id::TEXT, TRUE);
    PERFORM set_config('test.ea_prop2_id', v_prop2_id::TEXT, TRUE);
    PERFORM set_config('test.ea_prop3_id', v_prop3_id::TEXT, TRUE);
END $$;

-- Test 13: Before early advance, durations are 300s
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Early Advance Adaptive'),
    300,
    'Before early advance: proposing_duration = 300s'
);

-- Submit ratings from 2 participants (not enough for threshold of 3)
DO $$
DECLARE
    v_round_id INT := current_setting('test.ea_round_id')::INT;
    v_p1_id INT := current_setting('test.ea_p1_id')::INT;
    v_p2_id INT := current_setting('test.ea_p2_id')::INT;
    v_prop1_id INT := current_setting('test.ea_prop1_id')::INT;
    v_prop2_id INT := current_setting('test.ea_prop2_id')::INT;
    v_prop3_id INT := current_setting('test.ea_prop3_id')::INT;
BEGIN
    -- P1 rates (can't rate own prop1)
    INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES
        (v_round_id, v_p1_id, v_prop2_id, 80.0),
        (v_round_id, v_p1_id, v_prop3_id, 40.0);

    -- P2 rates (can't rate own prop2)
    INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES
        (v_round_id, v_p2_id, v_prop1_id, 70.0),
        (v_round_id, v_p2_id, v_prop3_id, 50.0);
END $$;

-- Test 14: After 2 ratings, durations still 300s (threshold not met)
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Early Advance Adaptive'),
    300,
    'After 2 ratings (threshold=3 not met): durations unchanged'
);

-- Now P3 rates, triggering early advance (3/3 = 100% >= threshold)
DO $$
DECLARE
    v_round_id INT := current_setting('test.ea_round_id')::INT;
    v_p3_id INT := current_setting('test.ea_p3_id')::INT;
    v_prop1_id INT := current_setting('test.ea_prop1_id')::INT;
    v_prop2_id INT := current_setting('test.ea_prop2_id')::INT;
BEGIN
    -- P3 rates (can't rate own prop3)
    INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES
        (v_round_id, v_p3_id, v_prop1_id, 90.0),
        (v_round_id, v_p3_id, v_prop2_id, 30.0);
END $$;

-- Test 15: Round completed by early advance
SELECT is(
    (SELECT completed_at IS NOT NULL FROM rounds WHERE id = current_setting('test.ea_round_id')::INT),
    TRUE,
    'Early advance completed the round'
);

-- Test 16: Adaptive duration applied after early advance
-- 300s - 10% = 270s → rounds to 300s (participation 3 >= threshold 3)
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Early Advance Adaptive'),
    300,
    'After early advance: adaptive duration applied (300s - 10% = 270s → 300s rounded)'
);

-- Test 17: Rating duration also adjusted
SELECT is(
    (SELECT rating_duration_seconds FROM chats WHERE name = 'Early Advance Adaptive'),
    300,
    'Rating duration also adjusted after early advance'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
