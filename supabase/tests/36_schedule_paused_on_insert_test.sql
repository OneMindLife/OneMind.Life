-- Tests for schedule_paused being set correctly on chat INSERT
-- Bug: Recurring chats created outside schedule window should start paused
BEGIN;
SELECT plan(6);

-- ============================================================================
-- TEST 1: Recurring chat created OUTSIDE window should be paused on insert
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_is_paused BOOLEAN;
    v_current_dow TEXT;
    v_other_dow TEXT;
BEGIN
    -- Create user
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- Get current day of week and pick a different day for the window
    v_current_dow := LOWER(TO_CHAR(NOW() AT TIME ZONE 'UTC', 'day'));
    v_current_dow := TRIM(v_current_dow);

    -- Pick a day that's NOT today (if today is monday, use tuesday, etc.)
    v_other_dow := CASE v_current_dow
        WHEN 'monday' THEN 'tuesday'
        WHEN 'tuesday' THEN 'wednesday'
        WHEN 'wednesday' THEN 'thursday'
        WHEN 'thursday' THEN 'friday'
        WHEN 'friday' THEN 'saturday'
        WHEN 'saturday' THEN 'sunday'
        WHEN 'sunday' THEN 'monday'
    END;

    -- Create recurring chat with window on a DIFFERENT day (so we're outside window)
    -- Note: schedule is independent of start_mode, so we use 'manual' + schedule_type='recurring'
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, schedule_type,
        schedule_windows, schedule_timezone
    ) VALUES (
        'Test Outside Window', 'Test message', v_session_token,
        'manual', 'recurring',
        format('[{"start_day": "%s", "start_time": "09:00", "end_day": "%s", "end_time": "17:00"}]', v_other_dow, v_other_dow)::JSONB,
        'UTC'
    ) RETURNING id INTO v_chat_id;

    -- Store ID for test assertion
    PERFORM set_config('test.outside_window_chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- This test should FAIL until we add the trigger
SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.outside_window_chat_id')::INT),
    TRUE,
    'Recurring chat created OUTSIDE schedule window should have schedule_paused = TRUE on insert'
);

-- ============================================================================
-- TEST 2: Recurring chat created INSIDE window should NOT be paused on insert
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
BEGIN
    -- Create user
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- Create recurring chat with window covering ALL days (so we're always inside)
    -- Note: schedule is independent of start_mode
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, schedule_type,
        schedule_windows, schedule_timezone
    ) VALUES (
        'Test Inside Window', 'Test message', v_session_token,
        'manual', 'recurring',
        '[{"start_day": "sunday", "start_time": "00:00", "end_day": "saturday", "end_time": "23:59"}]'::JSONB,
        'UTC'
    ) RETURNING id INTO v_chat_id;

    PERFORM set_config('test.inside_window_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.inside_window_chat_id')::INT),
    FALSE,
    'Recurring chat created INSIDE schedule window should have schedule_paused = FALSE on insert'
);

-- ============================================================================
-- TEST 3: One-time scheduled chat should NOT be paused on insert (different logic)
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- One-time scheduled chat for future time
    -- Note: schedule is independent of start_mode
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, schedule_type,
        scheduled_start_at, schedule_timezone
    ) VALUES (
        'Test One-Time', 'Test message', v_session_token,
        'manual', 'once',
        NOW() + interval '1 hour',
        'UTC'
    ) RETURNING id INTO v_chat_id;

    PERFORM set_config('test.once_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.once_chat_id')::INT),
    FALSE,
    'One-time scheduled chat should have schedule_paused = FALSE (uses scheduled_start_at instead)'
);

-- ============================================================================
-- TEST 4: Non-scheduled chat should NOT be paused
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- Manual mode chat
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode
    ) VALUES (
        'Test Manual', 'Test message', v_session_token,
        'manual'
    ) RETURNING id INTO v_chat_id;

    PERFORM set_config('test.manual_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.manual_chat_id')::INT),
    FALSE,
    'Manual mode chat should have schedule_paused = FALSE'
);

-- ============================================================================
-- TEST 5: Recurring chat with time-based window (outside current hour)
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_current_dow TEXT;
    v_window_start TEXT;
    v_window_end TEXT;
    v_current_hour INT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user_id);

    -- Get current day and hour in UTC
    v_current_dow := TRIM(LOWER(TO_CHAR(NOW() AT TIME ZONE 'UTC', 'day')));
    v_current_hour := EXTRACT(HOUR FROM NOW() AT TIME ZONE 'UTC')::INT;

    -- Create window that's 2-3 hours AFTER current time (so we're outside)
    v_window_start := LPAD(((v_current_hour + 2) % 24)::TEXT, 2, '0') || ':00';
    v_window_end := LPAD(((v_current_hour + 3) % 24)::TEXT, 2, '0') || ':00';

    -- Create chat with narrow window later today
    -- Note: schedule is independent of start_mode
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, schedule_type,
        schedule_windows, schedule_timezone
    ) VALUES (
        'Test Time Window', 'Test message', v_session_token,
        'manual', 'recurring',
        format('[{"start_day": "%s", "start_time": "%s", "end_day": "%s", "end_time": "%s"}]',
               v_current_dow, v_window_start, v_current_dow, v_window_end)::JSONB,
        'UTC'
    ) RETURNING id INTO v_chat_id;

    PERFORM set_config('test.time_window_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.time_window_chat_id')::INT),
    TRUE,
    'Recurring chat created outside time window (same day, later hours) should be paused'
);

-- ============================================================================
-- TEST 6: Recurring chat with overnight window (currently outside)
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_current_dow TEXT;
    v_next_dow TEXT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user_id);

    v_current_dow := TRIM(LOWER(TO_CHAR(NOW() AT TIME ZONE 'UTC', 'day')));
    v_next_dow := CASE v_current_dow
        WHEN 'monday' THEN 'tuesday'
        WHEN 'tuesday' THEN 'wednesday'
        WHEN 'wednesday' THEN 'thursday'
        WHEN 'thursday' THEN 'friday'
        WHEN 'friday' THEN 'saturday'
        WHEN 'saturday' THEN 'sunday'
        WHEN 'sunday' THEN 'monday'
    END;

    -- Create overnight window that spans from tomorrow 11pm to next day 1am
    -- This is definitely outside current time
    -- Note: schedule is independent of start_mode
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, schedule_type,
        schedule_windows, schedule_timezone
    ) VALUES (
        'Test Overnight Window', 'Test message', v_session_token,
        'manual', 'recurring',
        format('[{"start_day": "%s", "start_time": "23:00", "end_day": "%s", "end_time": "01:00"}]',
               v_next_dow,
               CASE v_next_dow
                   WHEN 'monday' THEN 'tuesday'
                   WHEN 'tuesday' THEN 'wednesday'
                   WHEN 'wednesday' THEN 'thursday'
                   WHEN 'thursday' THEN 'friday'
                   WHEN 'friday' THEN 'saturday'
                   WHEN 'saturday' THEN 'sunday'
                   WHEN 'sunday' THEN 'monday'
               END)::JSONB,
        'UTC'
    ) RETURNING id INTO v_chat_id;

    PERFORM set_config('test.overnight_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.overnight_chat_id')::INT),
    TRUE,
    'Recurring chat with overnight window (tomorrow) should be paused on insert'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.outside_window_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.inside_window_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.once_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.manual_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.time_window_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.overnight_chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
