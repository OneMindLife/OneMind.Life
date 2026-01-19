-- Tests for scheduled chats functionality
-- NOTE: Schedule is now independent of start_mode (facilitation).
-- start_mode can only be 'manual' or 'auto', and schedule is configured separately.
BEGIN;
SELECT plan(18);

-- ============================================================================
-- TEST DATA SETUP
-- ============================================================================

DO $$
DECLARE
    v_chat_id INT;
    v_session_token UUID := gen_random_uuid();
BEGIN
    -- Create test chat with default settings
    INSERT INTO public.chats (
        name, initial_message, creator_session_token, start_mode
    ) VALUES (
        'Test Chat', 'What should we do?', v_session_token, 'manual'
    ) RETURNING id INTO v_chat_id;

    PERFORM set_config('test.session_token', v_session_token::TEXT, TRUE);
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- ============================================================================
-- SCHEMA TESTS
-- ============================================================================

SELECT has_column('chats', 'schedule_type',
    'chats table should have schedule_type column');

SELECT has_column('chats', 'schedule_timezone',
    'chats table should have schedule_timezone column');

SELECT has_column('chats', 'scheduled_start_at',
    'chats table should have scheduled_start_at column');

SELECT has_column('chats', 'schedule_windows',
    'chats table should have schedule_windows column');

SELECT has_column('chats', 'visible_outside_schedule',
    'chats table should have visible_outside_schedule column');

SELECT has_column('chats', 'schedule_paused',
    'chats table should have schedule_paused column');

-- ============================================================================
-- DEFAULT VALUES TESTS
-- ============================================================================

SELECT is(
    (SELECT schedule_timezone FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    'UTC',
    'schedule_timezone should default to UTC'
);

SELECT is(
    (SELECT visible_outside_schedule FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'visible_outside_schedule should default to TRUE'
);

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'schedule_paused should default to FALSE'
);

-- ============================================================================
-- CONSTRAINT TESTS: start_mode only allows 'manual' and 'auto'
-- ============================================================================

SELECT throws_ok(
    format(
        'UPDATE public.chats SET start_mode = ''scheduled'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    '23514',
    NULL,
    'start_mode should NOT allow scheduled (use schedule_type instead)'
);

SELECT lives_ok(
    format(
        'UPDATE public.chats SET start_mode = ''auto'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    'start_mode should allow auto'
);

UPDATE public.chats SET start_mode = 'manual' WHERE id = current_setting('test.chat_id')::INT;

-- ============================================================================
-- CONSTRAINT TESTS: schedule_type can be set independently of start_mode
-- ============================================================================

-- Manual mode with one-time schedule
SELECT lives_ok(
    format(
        'UPDATE public.chats SET schedule_type = ''once'', scheduled_start_at = NOW() + interval ''1 hour'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    'manual mode can have schedule_type once'
);

-- Reset
UPDATE public.chats SET schedule_type = NULL, scheduled_start_at = NULL
WHERE id = current_setting('test.chat_id')::INT;

-- Manual mode with recurring schedule
SELECT lives_ok(
    format(
        'UPDATE public.chats SET schedule_type = ''recurring'', schedule_windows = ''[{"start_day": "wednesday", "start_time": "10:00", "end_day": "wednesday", "end_time": "11:00"}]'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    'manual mode can have schedule_type recurring'
);

-- Reset
UPDATE public.chats SET schedule_type = NULL, schedule_windows = NULL
WHERE id = current_setting('test.chat_id')::INT;

-- ============================================================================
-- FUNCTION TESTS: is_chat_in_schedule_window
-- ============================================================================

-- Test: Chat with no schedule is always in window
SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    TRUE,
    'Chat with no schedule should always be in window'
);

-- Test: One-time schedule - future
UPDATE public.chats SET
    schedule_type = 'once',
    scheduled_start_at = NOW() + interval '1 hour'
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    FALSE,
    'One-time schedule with future start should not be in window'
);

-- Test: One-time schedule - past
UPDATE public.chats SET
    scheduled_start_at = NOW() - interval '1 hour'
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    TRUE,
    'One-time schedule with past start should be in window'
);

-- ============================================================================
-- FUNCTION TESTS: process_scheduled_chats
-- ============================================================================

SELECT has_function('process_scheduled_chats',
    'process_scheduled_chats function should exist');

-- Test that it runs without error
SELECT lives_ok(
    'SELECT * FROM process_scheduled_chats()',
    'process_scheduled_chats should execute without error'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
