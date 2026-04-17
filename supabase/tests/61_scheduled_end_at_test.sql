-- Tests for scheduled_end_at (optional end time for one-time schedules)
BEGIN;
SELECT plan(16);

-- ============================================================================
-- TEST DATA SETUP
-- ============================================================================

DO $$
DECLARE
    v_chat_id INT;
    v_user_id UUID;
BEGIN
    -- Create anon user
    v_user_id := extensions.uuid_generate_v4();
    INSERT INTO auth.users (id, role) VALUES (v_user_id, 'authenticated');

    -- Create test chat
    INSERT INTO public.chats (
        name, initial_message, creator_id, start_mode, access_method
    ) VALUES (
        'Schedule End Test', 'Test question', v_user_id, 'auto', 'public'
    ) RETURNING id INTO v_chat_id;

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.user_id', v_user_id::TEXT, TRUE);
END $$;

-- ============================================================================
-- SCHEMA TESTS
-- ============================================================================

SELECT has_column('chats', 'scheduled_end_at',
    'chats table should have scheduled_end_at column');

SELECT col_is_null('chats', 'scheduled_end_at',
    'scheduled_end_at should be nullable');

-- ============================================================================
-- CONSTRAINT: end must be after start
-- ============================================================================

-- Set up one-time schedule with start in the past
UPDATE public.chats SET
    schedule_type = 'once',
    scheduled_start_at = NOW() - interval '2 hours'
WHERE id = current_setting('test.chat_id')::INT;

-- End time after start should succeed
SELECT lives_ok(
    format(
        'UPDATE public.chats SET scheduled_end_at = scheduled_start_at + interval ''1 hour'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    'scheduled_end_at after scheduled_start_at should be allowed'
);

-- End time before start should fail
SELECT throws_ok(
    format(
        'UPDATE public.chats SET scheduled_end_at = scheduled_start_at - interval ''1 hour'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    '23514',
    NULL,
    'scheduled_end_at before scheduled_start_at should be rejected'
);

-- End time equal to start should fail
SELECT throws_ok(
    format(
        'UPDATE public.chats SET scheduled_end_at = scheduled_start_at WHERE id = %s',
        current_setting('test.chat_id')
    ),
    '23514',
    NULL,
    'scheduled_end_at equal to scheduled_start_at should be rejected'
);

-- NULL end time is always fine
SELECT lives_ok(
    format(
        'UPDATE public.chats SET scheduled_end_at = NULL WHERE id = %s',
        current_setting('test.chat_id')
    ),
    'NULL scheduled_end_at should always be allowed'
);

-- ============================================================================
-- is_chat_in_schedule_window: one-time with end time
-- ============================================================================

-- Case 1: start in past, no end time → in window (indefinite)
UPDATE public.chats SET
    schedule_type = 'once',
    scheduled_start_at = NOW() - interval '2 hours',
    scheduled_end_at = NULL
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    TRUE,
    'One-time, past start, no end → in window (indefinite)'
);

-- Case 2: start in past, end in future → in window
UPDATE public.chats SET
    scheduled_end_at = NOW() + interval '1 hour'
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    TRUE,
    'One-time, past start, future end → in window'
);

-- Case 3: start in past, end in past → NOT in window
UPDATE public.chats SET
    scheduled_end_at = NOW() - interval '30 minutes'
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    FALSE,
    'One-time, past start, past end → NOT in window (expired)'
);

-- Case 4: start in future (regardless of end) → NOT in window
UPDATE public.chats SET
    scheduled_start_at = NOW() + interval '1 hour',
    scheduled_end_at = NOW() + interval '3 hours'
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    FALSE,
    'One-time, future start, future end → NOT in window'
);

-- Case 5: start in future, no end → NOT in window
UPDATE public.chats SET
    scheduled_end_at = NULL
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    FALSE,
    'One-time, future start, no end → NOT in window'
);

-- ============================================================================
-- is_chat_in_schedule_window: no schedule → always in window
-- ============================================================================

UPDATE public.chats SET
    schedule_type = NULL,
    scheduled_start_at = NULL,
    scheduled_end_at = NULL
WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_in_schedule_window(current_setting('test.chat_id')::INT),
    TRUE,
    'No schedule → always in window'
);

-- ============================================================================
-- process_scheduled_chats: pause after end time
-- ============================================================================

-- Set up: one-time schedule, start in past, end in past, not paused
UPDATE public.chats SET
    schedule_type = 'once',
    scheduled_start_at = NOW() - interval '3 hours',
    scheduled_end_at = NOW() - interval '1 hour',
    schedule_paused = FALSE,
    is_active = TRUE
WHERE id = current_setting('test.chat_id')::INT;

-- Process should pause the chat
SELECT lives_ok(
    'SELECT * FROM process_scheduled_chats()',
    'process_scheduled_chats runs without error'
);

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'Chat should be paused after end time has passed'
);

-- ============================================================================
-- process_scheduled_chats: resume within window (start past, end future)
-- ============================================================================

UPDATE public.chats SET
    scheduled_start_at = NOW() - interval '1 hour',
    scheduled_end_at = NOW() + interval '1 hour',
    schedule_paused = TRUE
WHERE id = current_setting('test.chat_id')::INT;

SELECT lives_ok(
    'SELECT * FROM process_scheduled_chats()',
    'process_scheduled_chats runs without error for resume case'
);

SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'Chat should be unpaused when within start-end window'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
