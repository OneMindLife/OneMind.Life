-- Test: Round-Minute Timer Alignment
-- Ensures phase_ends_at always falls on :00 seconds

BEGIN;

SELECT plan(6);

-- =============================================================================
-- Test 1: Helper function exists
-- =============================================================================
SELECT has_function(
    'public',
    'calculate_round_minute_end',
    ARRAY['integer'],
    'calculate_round_minute_end function exists'
);

-- =============================================================================
-- Test 2: Round minute calculation at :00 stays at :00
-- =============================================================================
-- If NOW() + duration lands exactly on :00, don't add extra minute
-- This is tricky to test deterministically, so we test the formula

SELECT is(
    EXTRACT(SECOND FROM calculate_round_minute_end(60)),
    0::NUMERIC,
    'Round minute end always has 0 seconds'
);

-- =============================================================================
-- Test 3: Result is always in the future
-- =============================================================================
SELECT ok(
    calculate_round_minute_end(1) > NOW(),
    'Round minute end is always in the future'
);

-- =============================================================================
-- Test 4: Result is at least duration seconds from now
-- =============================================================================
SELECT ok(
    calculate_round_minute_end(300) >= NOW() + INTERVAL '300 seconds',
    'Round minute end is at least duration from now (300s)'
);

-- =============================================================================
-- Test 5: Result is at most duration + 60 seconds from now
-- =============================================================================
-- Worst case: we're at XX:YY:59 and add 1 second, rounds up to next minute
SELECT ok(
    calculate_round_minute_end(60) <= NOW() + INTERVAL '120 seconds',
    'Round minute end is at most duration + 60s from now'
);

-- =============================================================================
-- Test 6: Auto-start trigger uses round minutes
-- =============================================================================
-- Create an auto-mode chat and verify phase_ends_at has 0 seconds

-- Set up test user
SELECT set_config('test.session_token', gen_random_uuid()::TEXT, true);

-- Create host with auto-mode chat
INSERT INTO chats (
    name,
    initial_message,
    access_method,
    start_mode,
    auto_start_participant_count,
    proposing_duration_seconds,
    rating_duration_seconds,
    proposing_minimum,
    rating_minimum,
    creator_session_token
)
VALUES (
    'Round Minute Test Chat',
    'Testing round minutes',
    'code',
    'auto',
    3, -- Auto-start when 3 participants join (minimum allowed)
    60, -- 1 minute proposing
    60, -- 1 minute rating
    3,
    2,
    current_setting('test.session_token')::UUID
);

SELECT set_config('test.chat_id', (SELECT id::TEXT FROM chats WHERE name = 'Round Minute Test Chat'), true);

-- Add host as participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (
    current_setting('test.chat_id')::INT,
    current_setting('test.session_token')::UUID,
    'Host',
    true,
    'active'
);

-- Add second participant (still below threshold)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (
    current_setting('test.chat_id')::INT,
    gen_random_uuid(),
    'User 2',
    false,
    'active'
);

-- Add third participant to trigger auto-start (threshold=3)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (
    current_setting('test.chat_id')::INT,
    gen_random_uuid(),
    'User 3',
    false,
    'active'
);

-- Check that the round was created with phase_ends_at at :00
SELECT is(
    EXTRACT(SECOND FROM (
        SELECT phase_ends_at
        FROM rounds
        WHERE cycle_id IN (SELECT id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT)
        LIMIT 1
    )),
    0::NUMERIC,
    'Auto-start creates round with phase_ends_at at :00 seconds'
);

SELECT * FROM finish();

ROLLBACK;
