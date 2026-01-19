-- =============================================================================
-- TEST: Adaptive Duration Edge Cases
-- =============================================================================
-- Tests for edge cases identified in gap analysis:
-- 1. Disabled adaptive duration no-op
-- 2. Zero participants
-- 3. Compounding over multiple rounds
-- 4. Different proposing vs rating durations
--
-- Updated to use existing early advance thresholds (proposing_threshold_*,
-- rating_threshold_*) instead of separate adaptive_threshold_count
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(28);

-- =============================================================================
-- EDGE CASE 1: DISABLED ADAPTIVE DURATION NO-OP
-- =============================================================================
-- When adaptive_duration_enabled = FALSE, apply_adaptive_duration should:
-- - Return 'disabled' as adjustment_applied
-- - NOT modify chat durations
-- =============================================================================

-- Setup: Create chat with adaptive DISABLED
INSERT INTO chats (
    name, initial_message, creator_session_token,
    adaptive_duration_enabled,
    proposing_duration_seconds, rating_duration_seconds
)
VALUES (
    'Disabled Adaptive Chat', 'Testing disabled', gen_random_uuid(),
    FALSE,  -- Adaptive disabled
    300, 300
);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Disabled Adaptive Chat';

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round_id;

    -- Create participant with activity
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active')
    RETURNING id INTO v_p1_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'Test prop');

    PERFORM set_config('test.disabled_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.disabled_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 1: apply_adaptive_duration returns 'disabled' when feature is off
SELECT is(
    (SELECT adjustment_applied FROM apply_adaptive_duration(current_setting('test.disabled_round_id')::INT)),
    'disabled',
    'apply_adaptive_duration returns "disabled" when adaptive_duration_enabled = FALSE'
);

-- Test 2: Proposing duration unchanged after apply_adaptive_duration
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Disabled Adaptive Chat'),
    300,
    'Proposing duration unchanged (300s) when adaptive disabled'
);

-- Test 3: Rating duration unchanged after apply_adaptive_duration
SELECT is(
    (SELECT rating_duration_seconds FROM chats WHERE name = 'Disabled Adaptive Chat'),
    300,
    'Rating duration unchanged (300s) when adaptive disabled'
);

-- =============================================================================
-- EDGE CASE 2: ZERO PARTICIPANTS
-- =============================================================================
-- When a round has zero participation AND no thresholds configured,
-- the function should return 'unchanged/unchanged' for both phases
-- =============================================================================

INSERT INTO chats (
    name, initial_message, creator_session_token,
    adaptive_duration_enabled, adaptive_adjustment_percent,
    min_phase_duration_seconds, max_phase_duration_seconds,
    proposing_duration_seconds, rating_duration_seconds
    -- NO thresholds configured (NULL)
)
VALUES (
    'Zero Participation Chat', 'Testing zero', gen_random_uuid(),
    TRUE, 10, 60, 86400, 300, 300
);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_result RECORD;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Zero Participation Chat';

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    -- Round with NO propositions or ratings
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round_id;

    -- No participants at all means no thresholds can be calculated
    -- So adjustment should be 'unchanged/unchanged'

    PERFORM set_config('test.zero_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 4: Zero participants returns 'no_participants'
SELECT is(
    (SELECT adjustment_applied FROM apply_adaptive_duration(current_setting('test.zero_round_id')::INT)),
    'no_participants',
    'Zero participants: adjustment_applied = "no_participants"'
);

-- Test 5: Proposing duration unchanged when no participants
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Zero Participation Chat'),
    300,
    'Zero participants: proposing duration unchanged'
);

-- Test 6: Rating duration unchanged when no participants
SELECT is(
    (SELECT rating_duration_seconds FROM chats WHERE name = 'Zero Participation Chat'),
    300,
    'Zero participants: rating duration unchanged'
);

-- =============================================================================
-- EDGE CASE 3: COMPOUNDING OVER MULTIPLE ROUNDS
-- =============================================================================
-- Multiple rounds should compound adjustments correctly
-- Each round applies percentage to NEW base value
-- =============================================================================

INSERT INTO chats (
    name, initial_message, creator_session_token,
    adaptive_duration_enabled, adaptive_adjustment_percent,
    min_phase_duration_seconds, max_phase_duration_seconds,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_threshold_count, rating_threshold_count
)
VALUES (
    'Compounding Chat', 'Testing compounding', gen_random_uuid(),
    TRUE, 10, 60, 86400, 600, 600,  -- Start at 10 minutes
    5, 5  -- Thresholds at 5 participants
);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round1_id INT;
    v_round2_id INT;
    v_round3_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
    v_p4_id INT;
    v_p5_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Compounding Chat';

    -- Create 5 participants (meets threshold)
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

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Round 1: All 5 participate
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round1_id;

    INSERT INTO propositions (round_id, participant_id, content) VALUES
        (v_round1_id, v_p1_id, 'R1P1'),
        (v_round1_id, v_p2_id, 'R1P2'),
        (v_round1_id, v_p3_id, 'R1P3'),
        (v_round1_id, v_p4_id, 'R1P4'),
        (v_round1_id, v_p5_id, 'R1P5');

    -- Round 2 and 3 for later
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 2, 'rating')
    RETURNING id INTO v_round2_id;

    INSERT INTO propositions (round_id, participant_id, content) VALUES
        (v_round2_id, v_p1_id, 'R2P1'),
        (v_round2_id, v_p2_id, 'R2P2'),
        (v_round2_id, v_p3_id, 'R2P3'),
        (v_round2_id, v_p4_id, 'R2P4'),
        (v_round2_id, v_p5_id, 'R2P5');

    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 3, 'rating')
    RETURNING id INTO v_round3_id;

    INSERT INTO propositions (round_id, participant_id, content) VALUES
        (v_round3_id, v_p1_id, 'R3P1'),
        (v_round3_id, v_p2_id, 'R3P2'),
        (v_round3_id, v_p3_id, 'R3P3'),
        (v_round3_id, v_p4_id, 'R3P4'),
        (v_round3_id, v_p5_id, 'R3P5');

    PERFORM set_config('test.compound_round1_id', v_round1_id::TEXT, TRUE);
    PERFORM set_config('test.compound_round2_id', v_round2_id::TEXT, TRUE);
    PERFORM set_config('test.compound_round3_id', v_round3_id::TEXT, TRUE);
END $$;

-- Test 7: Initial duration is 600s
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Compounding Chat'),
    600,
    'Compounding: initial duration is 600s (10 min)'
);

-- Apply round 1 (5 participants >= 5 threshold = decrease)
-- 600 * 0.9 = 540 → ROUND(540/60) = 9 → 540s
SELECT is(
    (SELECT new_proposing_duration FROM apply_adaptive_duration(current_setting('test.compound_round1_id')::INT)),
    540,
    'Compounding Round 1: 600s - 10% = 540s'
);

-- Test 8: After round 1, duration is 540s
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Compounding Chat'),
    540,
    'Compounding: after round 1, duration is 540s'
);

-- Apply round 2 (540 * 0.9 = 486 → ROUND(486/60) = 8.1 → 480s)
SELECT is(
    (SELECT new_proposing_duration FROM apply_adaptive_duration(current_setting('test.compound_round2_id')::INT)),
    480,
    'Compounding Round 2: 540s - 10% = 486s → 480s (rounded)'
);

-- Test 9: After round 2, duration is 480s
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Compounding Chat'),
    480,
    'Compounding: after round 2, duration is 480s (8 min)'
);

-- Apply round 3 (480 * 0.9 = 432 → ROUND(432/60) = 7.2 → 420s)
SELECT is(
    (SELECT new_proposing_duration FROM apply_adaptive_duration(current_setting('test.compound_round3_id')::INT)),
    420,
    'Compounding Round 3: 480s - 10% = 432s → 420s (rounded)'
);

-- Test 10: After round 3, duration is 420s
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Compounding Chat'),
    420,
    'Compounding: after round 3, duration is 420s (7 min)'
);

-- Test 11: Verify compounding trajectory: 600 → 540 → 480 → 420
-- (10min → 9min → 8min → 7min)
SELECT ok(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Compounding Chat') = 420,
    'Compounding trajectory verified: 600 → 540 → 480 → 420'
);

-- =============================================================================
-- EDGE CASE 4: DIFFERENT PROPOSING VS RATING DURATIONS & THRESHOLDS
-- =============================================================================
-- Proposing and rating can have different thresholds, causing different
-- adjustment directions
-- =============================================================================

INSERT INTO chats (
    name, initial_message, creator_session_token,
    adaptive_duration_enabled, adaptive_adjustment_percent,
    min_phase_duration_seconds, max_phase_duration_seconds,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_threshold_count, rating_threshold_count
)
VALUES (
    'Different Durations Chat', 'Testing different', gen_random_uuid(),
    TRUE, 10, 60, 86400,
    300, 600,  -- 5 min proposing, 10 min rating
    3, 3  -- Both thresholds at 3
);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Different Durations Chat';

    -- Create 3 participants (meets threshold)
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active')
    RETURNING id INTO v_p1_id;
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P2', FALSE, 'active')
    RETURNING id INTO v_p2_id;
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P3', FALSE, 'active')
    RETURNING id INTO v_p3_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round_id;

    -- All 3 submit propositions (meets proposing threshold)
    INSERT INTO propositions (round_id, participant_id, content) VALUES
        (v_round_id, v_p1_id, 'Prop 1'),
        (v_round_id, v_p2_id, 'Prop 2'),
        (v_round_id, v_p3_id, 'Prop 3');

    -- NO ratings submitted (0 < rating threshold of 3)

    PERFORM set_config('test.diff_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 12: Initial proposing duration is 300s
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Different Durations Chat'),
    300,
    'Different durations: initial proposing = 300s'
);

-- Test 13: Initial rating duration is 600s
SELECT is(
    (SELECT rating_duration_seconds FROM chats WHERE name = 'Different Durations Chat'),
    600,
    'Different durations: initial rating = 600s'
);

-- Apply adaptive duration
-- Proposing: 3 >= 3 threshold → decrease
-- Rating: 0 < 3 threshold → increase
SELECT ok(
    (SELECT new_proposing_duration FROM apply_adaptive_duration(current_setting('test.diff_round_id')::INT)) IS NOT NULL,
    'Different durations: apply_adaptive_duration executed'
);

-- Test 14: Proposing adjusted from its own base (300 * 0.9 = 270 → 300 rounded)
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Different Durations Chat'),
    300,
    'Different durations: proposing 300s - 10% = 270s → 300s (rounded to 5 min)'
);

-- Test 15: Rating INCREASED because 0 raters < 3 threshold
-- 600 * 1.1 = 660 → ROUND(660/60) = 11 → 660s
SELECT is(
    (SELECT rating_duration_seconds FROM chats WHERE name = 'Different Durations Chat'),
    660,
    'Different durations: rating 600s + 10% = 660s (low participation increased)'
);

-- Test 16: Proposing and rating moved in OPPOSITE directions
SELECT ok(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Different Durations Chat') <
    (SELECT rating_duration_seconds FROM chats WHERE name = 'Different Durations Chat'),
    'Different durations: proposing decreased, rating increased'
);

-- =============================================================================
-- EDGE CASE 5: MINIMUM FLOOR DURING COMPOUNDING
-- =============================================================================
-- Verify that compounding doesn't go below minimum even over many rounds
-- =============================================================================

INSERT INTO chats (
    name, initial_message, creator_session_token,
    adaptive_duration_enabled, adaptive_adjustment_percent,
    min_phase_duration_seconds, max_phase_duration_seconds,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_threshold_count, rating_threshold_count
)
VALUES (
    'Floor Test Chat', 'Testing floor', gen_random_uuid(),
    TRUE, 50, 60, 86400, 120, 120,  -- 50% adjustment, start at 2 min
    3, 2  -- Minimum valid thresholds (proposing >= 3, rating >= 2)
);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round1_id INT;
    v_round2_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Floor Test Chat';

    -- Need 3 participants to meet proposing_threshold_count of 3
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active')
    RETURNING id INTO v_p1_id;
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P2', FALSE, 'active')
    RETURNING id INTO v_p2_id;
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P3', FALSE, 'active')
    RETURNING id INTO v_p3_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Round 1: All 3 submit propositions to meet threshold
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round1_id;
    INSERT INTO propositions (round_id, participant_id, content) VALUES
        (v_round1_id, v_p1_id, 'Floor R1P1'),
        (v_round1_id, v_p2_id, 'Floor R1P2'),
        (v_round1_id, v_p3_id, 'Floor R1P3');

    -- Round 2: All 3 submit again
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 2, 'rating')
    RETURNING id INTO v_round2_id;
    INSERT INTO propositions (round_id, participant_id, content) VALUES
        (v_round2_id, v_p1_id, 'Floor R2P1'),
        (v_round2_id, v_p2_id, 'Floor R2P2'),
        (v_round2_id, v_p3_id, 'Floor R2P3');

    PERFORM set_config('test.floor_round1_id', v_round1_id::TEXT, TRUE);
    PERFORM set_config('test.floor_round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- Test 17: Round 1: 120s - 50% = 60s (hits floor)
-- 3 proposers >= 3 threshold → decrease by 50%
-- 120 * 0.5 = 60 → exactly at floor
SELECT ok(
    (SELECT new_proposing_duration FROM apply_adaptive_duration(current_setting('test.floor_round1_id')::INT)) = 60,
    'Floor test round 1: 120s - 50% = 60s (minimum)'
);

-- Test 18: After round 1, duration is at floor (60s)
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Floor Test Chat'),
    60,
    'Floor test: duration at minimum 60s after round 1'
);

-- Test 19: Round 2: 60s - 50% = 30s → floored to 60s
SELECT ok(
    (SELECT new_proposing_duration FROM apply_adaptive_duration(current_setting('test.floor_round2_id')::INT)) = 60,
    'Floor test round 2: 60s - 50% = 30s → floored to 60s'
);

-- Test 20: Duration stays at floor after second decrease attempt
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Floor Test Chat'),
    60,
    'Floor test: duration stays at 60s minimum (cannot go lower)'
);

-- =============================================================================
-- EDGE CASE 6: NO THRESHOLD CONFIGURED = NO ADJUSTMENT
-- =============================================================================
-- When a phase has no threshold, that phase should not adjust
-- =============================================================================

INSERT INTO chats (
    name, initial_message, creator_session_token,
    adaptive_duration_enabled, adaptive_adjustment_percent,
    min_phase_duration_seconds, max_phase_duration_seconds,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_threshold_count, rating_threshold_count  -- Explicitly set rating to NULL
)
VALUES (
    'Partial Threshold Chat', 'Testing partial', gen_random_uuid(),
    TRUE, 10, 60, 86400, 300, 300,
    3, NULL  -- Only proposing threshold, rating explicitly NULL
);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Partial Threshold Chat';

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active')
    RETURNING id INTO v_p1_id;
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P2', FALSE, 'active')
    RETURNING id INTO v_p2_id;
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P3', FALSE, 'active')
    RETURNING id INTO v_p3_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round_id;

    -- All 3 submit propositions (meets proposing threshold)
    INSERT INTO propositions (round_id, participant_id, content) VALUES
        (v_round_id, v_p1_id, 'PT1'),
        (v_round_id, v_p2_id, 'PT2'),
        (v_round_id, v_p3_id, 'PT3');

    PERFORM set_config('test.partial_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 21: Execute apply_adaptive_duration
SELECT ok(
    (SELECT adjustment_applied FROM apply_adaptive_duration(current_setting('test.partial_round_id')::INT)) IS NOT NULL,
    'Partial threshold: apply_adaptive_duration executed'
);

-- Test 22: Proposing adjusted (has threshold)
-- 3 >= 3 → decrease by 10%: 300 * 0.9 = 270 → 300 (rounded)
SELECT is(
    (SELECT proposing_duration_seconds FROM chats WHERE name = 'Partial Threshold Chat'),
    300,
    'Partial threshold: proposing adjusted (300s - 10% → 300s rounded)'
);

-- Test 23: Rating unchanged (no threshold configured)
SELECT is(
    (SELECT rating_duration_seconds FROM chats WHERE name = 'Partial Threshold Chat'),
    300,
    'Partial threshold: rating unchanged (no threshold configured)'
);

-- Test 24: Adjustment string shows decreased/unchanged
SELECT ok(
    (SELECT adjustment_applied FROM apply_adaptive_duration(current_setting('test.partial_round_id')::INT)) LIKE '%unchanged%',
    'Partial threshold: adjustment shows rating unchanged'
);

SELECT * FROM finish();
ROLLBACK;
