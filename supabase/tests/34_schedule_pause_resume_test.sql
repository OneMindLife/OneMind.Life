-- Tests for schedule pause/resume time preservation
BEGIN;
SELECT plan(15);

-- ============================================================================
-- TEST SETUP: Create a scheduled chat with active round
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_host_id INT;
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
BEGIN
    -- Create user
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- Create chat with schedule (manual facilitation + recurring schedule)
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, schedule_type,
        schedule_windows, schedule_timezone, schedule_paused,
        proposing_duration_seconds, rating_duration_seconds
    ) VALUES (
        'Test Scheduled Chat', 'Test message', v_session_token,
        'manual', 'recurring',  -- schedule is independent of start_mode
        '[{"start_day": "sunday", "start_time": "00:00", "end_day": "saturday", "end_time": "23:59"}]'::JSONB,
        'UTC', FALSE,
        300, 300  -- 5 minutes each phase
    ) RETURNING id INTO v_chat_id;

    -- Create host participant
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user_id, 'Host', TRUE, 'active')
    RETURNING id INTO v_host_id;

    -- Create cycle and round in proposing phase with timer set
    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + interval '5 minutes')
    RETURNING id INTO v_round_id;

    -- Store IDs for tests
    PERFORM set_config('test.user_id', v_user_id::TEXT, TRUE);
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
END $$;

-- ============================================================================
-- SCHEMA TESTS: New column exists
-- ============================================================================

SELECT has_column('rounds', 'phase_time_remaining_seconds',
    'rounds table should have phase_time_remaining_seconds column');

-- ============================================================================
-- TEST: Initial state - no remaining time stored
-- ============================================================================

SELECT is(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'Initially phase_time_remaining_seconds should be NULL'
);

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'proposing',
    'Initially round should be in proposing phase'
);

-- ============================================================================
-- TEST: Pause captures remaining time
-- ============================================================================

-- Simulate time passing (3 minutes elapsed, 2 minutes remaining)
UPDATE public.rounds
SET phase_ends_at = NOW() + interval '2 minutes'
WHERE id = current_setting('test.round_id')::INT;

-- Force chat outside schedule window by setting a narrow window (1 minute past midnight)
UPDATE public.chats
SET schedule_windows = '[{"start_day": "sunday", "start_time": "00:00", "end_day": "sunday", "end_time": "00:01"}]'::JSONB
WHERE id = current_setting('test.chat_id')::INT;

-- Process scheduled chats (should pause)
SELECT * FROM process_scheduled_chats();

-- Verify chat is paused
SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'Chat should be paused after process_scheduled_chats'
);

-- Verify remaining time was saved (approximately 2 minutes = 120 seconds, allow tolerance)
SELECT ok(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 100 AND 130,
    'phase_time_remaining_seconds should be approximately 120 (2 min remaining)'
);

-- ============================================================================
-- TEST: Resume restores remaining time
-- ============================================================================

-- Put chat back in schedule window (all week)
UPDATE public.chats
SET schedule_windows = '[{"start_day": "sunday", "start_time": "00:00", "end_day": "saturday", "end_time": "23:59"}]'::JSONB
WHERE id = current_setting('test.chat_id')::INT;

-- Process scheduled chats (should resume)
SELECT * FROM process_scheduled_chats();

-- Verify chat is unpaused
SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'Chat should be unpaused after resume'
);

-- Verify remaining time was cleared
SELECT is(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'phase_time_remaining_seconds should be cleared after resume'
);

-- Verify phase_ends_at was restored (should be ~2 minutes from now)
-- Note: calculate_round_minute_end() aligns to next minute boundary, adding up to 60 extra seconds
SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - NOW())) FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 100 AND 190,
    'phase_ends_at should be restored to approximately 2 minutes from now (with minute alignment)'
);

-- Verify phase_started_at was updated
SELECT ok(
    (SELECT phase_started_at FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) >= NOW() - interval '5 seconds',
    'phase_started_at should be updated to now on resume'
);

-- ============================================================================
-- TEST: Pause in rating phase preserves rating state
-- ============================================================================

-- Advance to rating phase
UPDATE public.rounds
SET phase = 'rating',
    phase_started_at = NOW(),
    phase_ends_at = NOW() + interval '3 minutes'
WHERE id = current_setting('test.round_id')::INT;

-- Force outside window
UPDATE public.chats
SET schedule_windows = '[{"start_day": "sunday", "start_time": "00:00", "end_day": "sunday", "end_time": "00:01"}]'::JSONB
WHERE id = current_setting('test.chat_id')::INT;

-- Process (pause)
SELECT * FROM process_scheduled_chats();

-- Verify phase is still rating
SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'rating',
    'Phase should still be rating after pause'
);

-- Verify time saved (approximately 180 seconds)
SELECT ok(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 160 AND 190,
    'Rating phase remaining time should be saved (~180 seconds)'
);

-- Resume
UPDATE public.chats
SET schedule_windows = '[{"start_day": "sunday", "start_time": "00:00", "end_day": "saturday", "end_time": "23:59"}]'::JSONB
WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM process_scheduled_chats();

-- Verify still in rating phase
SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'rating',
    'Phase should still be rating after resume'
);

-- Verify timer restored
-- Note: calculate_round_minute_end() aligns to next minute boundary, adding up to 60 extra seconds
SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - NOW())) FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 160 AND 250,
    'Rating phase timer should be restored (~180 seconds, with minute alignment)'
);

-- ============================================================================
-- TEST: Pause with expired timer saves 0
-- ============================================================================

-- Set timer to already expired
UPDATE public.rounds
SET phase_ends_at = NOW() - interval '1 minute'
WHERE id = current_setting('test.round_id')::INT;

-- Force outside window
UPDATE public.chats
SET schedule_windows = '[{"start_day": "sunday", "start_time": "00:00", "end_day": "sunday", "end_time": "00:01"}]'::JSONB
WHERE id = current_setting('test.chat_id')::INT;

-- Process (pause)
SELECT * FROM process_scheduled_chats();

-- Verify remaining time is 0 (not negative)
SELECT is(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT),
    0,
    'Expired timer should save 0 seconds remaining, not negative'
);

-- ============================================================================
-- TEST: Resume with 0 remaining uses full phase duration
-- ============================================================================

-- Resume
UPDATE public.chats
SET schedule_windows = '[{"start_day": "sunday", "start_time": "00:00", "end_day": "saturday", "end_time": "23:59"}]'::JSONB
WHERE id = current_setting('test.chat_id')::INT;

-- But first set remaining to 0 explicitly
UPDATE public.rounds
SET phase_time_remaining_seconds = 0
WHERE id = current_setting('test.round_id')::INT;

SELECT * FROM process_scheduled_chats();

-- With 0 remaining, it should use full duration (300 seconds for rating)
-- Note: calculate_round_minute_end() aligns to next minute boundary, adding up to 60 extra seconds
SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - NOW())) FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 290 AND 370,
    'Resume with 0 remaining should use full phase duration (300 seconds, with minute alignment)'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
