-- Tests for schedule resume respecting facilitation mode (start_mode)
-- BUG: When a recurring schedule window opens and round is in 'waiting' phase,
-- the current code force-starts 'proposing' regardless of start_mode.
-- EXPECTED: Resume should respect start_mode:
--   - manual: keep 'waiting', host must click "Start"
--   - auto: keep 'waiting', let process-timers check participant threshold
BEGIN;
SELECT plan(9);

-- ============================================================================
-- TEST SETUP: Create test session tokens
-- ============================================================================

DO $$
DECLARE
    v_session_token_manual UUID := gen_random_uuid();
    v_session_token_auto UUID := gen_random_uuid();
BEGIN
    PERFORM set_config('test.session_token_manual', v_session_token_manual::TEXT, TRUE);
    PERFORM set_config('test.session_token_auto', v_session_token_auto::TEXT, TRUE);
END $$;

-- ============================================================================
-- TEST 1-3: MANUAL FACILITATION + RECURRING SCHEDULE
-- When window opens with waiting phase, should STAY in waiting (host starts)
-- ============================================================================

-- Setup: Create chat with manual facilitation + recurring schedule
DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_host_id INT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- Create chat: manual facilitation + recurring schedule
    -- Use a window that covers ALL times (Monday 00:00 to Sunday 23:59 spanning full week)
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode,  -- MANUAL facilitation
        schedule_type, schedule_windows, schedule_timezone, schedule_paused,
        proposing_duration_seconds, rating_duration_seconds
    ) VALUES (
        'Manual + Recurring', 'Test', current_setting('test.session_token_manual')::UUID,
        'manual',
        'recurring',
        '[{"start_day": "monday", "start_time": "00:00", "end_day": "sunday", "end_time": "23:59"}]'::JSONB,
        'UTC', TRUE,  -- Start paused (simulating schedule was closed)
        300, 300
    ) RETURNING id INTO v_chat_id;

    -- Create host participant
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user_id, 'Host', TRUE, 'active')
    RETURNING id INTO v_host_id;

    -- Create cycle and round in WAITING phase (not started yet)
    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'waiting', NULL, NULL)
    RETURNING id INTO v_round_id;

    PERFORM set_config('test.manual_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('test.manual_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.manual_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 1: Verify initial state - manual mode, waiting phase
SELECT is(
    (SELECT start_mode FROM public.chats WHERE id = current_setting('test.manual_chat_id')::INT),
    'manual',
    'Chat should have manual facilitation mode'
);

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.manual_round_id')::INT),
    'waiting',
    'Round should start in waiting phase'
);

-- Verify the window IS open (sanity check)
SELECT is(
    is_chat_in_schedule_window(current_setting('test.manual_chat_id')::INT),
    TRUE,
    'Sanity check: window should be detected as open'
);

-- Manually pause the chat to simulate "window was closed, now opened"
-- (The INSERT trigger may have set it to FALSE because window is open)
UPDATE public.chats SET schedule_paused = TRUE WHERE id = current_setting('test.manual_chat_id')::INT;

-- Now call process_scheduled_chats to trigger the resume
SELECT * FROM process_scheduled_chats();

-- Test 2: BUG TEST - Phase should STILL be 'waiting' for manual mode
-- Current buggy behavior: force-starts 'proposing'
-- Expected behavior: stay in 'waiting', host must click "Start"
SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.manual_round_id')::INT),
    'waiting',
    'BUG: Manual mode should stay in waiting phase after schedule resume (host starts)'
);

-- ============================================================================
-- TEST 4-6: AUTO FACILITATION + RECURRING SCHEDULE
-- When window opens with waiting phase, should STAY in waiting
-- (process-timers checks participant threshold)
-- ============================================================================

-- Setup: Create chat with auto facilitation + recurring schedule
DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_host_id INT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- Create chat: auto facilitation + recurring schedule
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,  -- AUTO facilitation, needs 5 participants
        schedule_type, schedule_windows, schedule_timezone, schedule_paused,
        proposing_duration_seconds, rating_duration_seconds
    ) VALUES (
        'Auto + Recurring', 'Test', current_setting('test.session_token_auto')::UUID,
        'auto', 5,
        'recurring',
        '[{"start_day": "monday", "start_time": "00:00", "end_day": "sunday", "end_time": "23:59"}]'::JSONB,
        'UTC', TRUE,  -- Start paused (simulating schedule was closed)
        300, 300
    ) RETURNING id INTO v_chat_id;

    -- Create ONLY 2 participants (below threshold of 5)
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user_id, 'Host', TRUE, 'active')
    RETURNING id INTO v_host_id;

    INSERT INTO public.participants (chat_id, display_name, is_host, status, session_token)
    VALUES (v_chat_id, 'Participant2', FALSE, 'active', gen_random_uuid());

    -- Create cycle and round in WAITING phase
    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'waiting', NULL, NULL)
    RETURNING id INTO v_round_id;

    PERFORM set_config('test.auto_user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('test.auto_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.auto_round_id', v_round_id::TEXT, TRUE);
END $$;

-- Test 4: Verify initial state - auto mode, waiting phase
SELECT is(
    (SELECT start_mode FROM public.chats WHERE id = current_setting('test.auto_chat_id')::INT),
    'auto',
    'Chat should have auto facilitation mode'
);

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.auto_round_id')::INT),
    'waiting',
    'Auto chat round should start in waiting phase'
);

-- Manually pause the chat to simulate "window was closed, now opened"
UPDATE public.chats SET schedule_paused = TRUE WHERE id = current_setting('test.auto_chat_id')::INT;

-- Now call process_scheduled_chats to trigger the resume
SELECT * FROM process_scheduled_chats();

-- Test 5: BUG TEST - Phase should STILL be 'waiting' for auto mode (below threshold)
-- Current buggy behavior: force-starts 'proposing' even without enough participants
-- Expected behavior: stay in 'waiting', let process-timers check participant count
SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.auto_round_id')::INT),
    'waiting',
    'BUG: Auto mode should stay in waiting phase after schedule resume (needs participant threshold)'
);

-- ============================================================================
-- TEST 7-10: MID-PHASE RESUME SHOULD STILL WORK (existing behavior preserved)
-- ============================================================================

-- Setup: Put manual chat back to paused and in proposing phase
UPDATE public.chats SET schedule_paused = TRUE WHERE id = current_setting('test.manual_chat_id')::INT;
UPDATE public.rounds
SET phase = 'proposing',
    phase_started_at = NOW(),
    phase_ends_at = NOW() + interval '3 minutes',
    phase_time_remaining_seconds = 180  -- 3 mins saved
WHERE id = current_setting('test.manual_round_id')::INT;

-- Now resume
SELECT * FROM process_scheduled_chats();

-- Test 7: Manual mode mid-proposing: should resume proposing phase
SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.manual_round_id')::INT),
    'proposing',
    'Manual mode mid-proposing: should resume proposing phase'
);

-- Setup: Put manual chat back to paused and in rating phase
UPDATE public.chats SET schedule_paused = TRUE WHERE id = current_setting('test.manual_chat_id')::INT;
UPDATE public.rounds
SET phase = 'rating',
    phase_started_at = NOW(),
    phase_ends_at = NOW() + interval '3 minutes',
    phase_time_remaining_seconds = 180  -- 3 mins saved
WHERE id = current_setting('test.manual_round_id')::INT;

-- Now resume
SELECT * FROM process_scheduled_chats();

-- Test 8: Manual mode mid-rating: should resume rating phase
SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.manual_round_id')::INT),
    'rating',
    'Manual mode mid-rating: should resume rating phase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE creator_session_token IN (
    current_setting('test.session_token_manual')::UUID,
    current_setting('test.session_token_auto')::UUID
);

SELECT * FROM finish();
ROLLBACK;
