-- Tests for flexible schedule windows
BEGIN;
SELECT plan(31);

-- ============================================================================
-- SCHEMA TESTS
-- ============================================================================

SELECT has_column('chats', 'schedule_windows',
    'chats table should have schedule_windows column');

SELECT col_type_is('chats', 'schedule_windows', 'jsonb',
    'schedule_windows should be JSONB type');

-- Old columns should be dropped
SELECT hasnt_column('chats', 'schedule_days',
    'schedule_days column should be dropped');

SELECT hasnt_column('chats', 'schedule_start_time',
    'schedule_start_time column should be dropped');

SELECT hasnt_column('chats', 'schedule_end_time',
    'schedule_end_time column should be dropped');

-- ============================================================================
-- HELPER FUNCTION TESTS
-- ============================================================================

SELECT is(
    day_name_to_number('sunday'),
    0,
    'Sunday should be day 0'
);

SELECT is(
    day_name_to_number('saturday'),
    6,
    'Saturday should be day 6'
);

SELECT is(
    day_name_to_number('MONDAY'),
    1,
    'day_name_to_number should be case-insensitive'
);

-- ============================================================================
-- WINDOW VALIDATION TESTS (Test Cases 1-6)
-- ============================================================================

-- Test 1: Valid same-day window
SELECT is(
    validate_schedule_window('{"start_day": "monday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}'::JSONB),
    TRUE,
    'Valid same-day window should pass validation'
);

-- Test 2: Valid cross-day window (midnight spanning)
SELECT is(
    validate_schedule_window('{"start_day": "thursday", "start_time": "23:00", "end_day": "friday", "end_time": "01:00"}'::JSONB),
    TRUE,
    'Valid cross-day (midnight) window should pass validation'
);

-- Test 3: Valid multi-day window
SELECT is(
    validate_schedule_window('{"start_day": "saturday", "start_time": "10:00", "end_day": "sunday", "end_time": "18:00"}'::JSONB),
    TRUE,
    'Valid multi-day window should pass validation'
);

-- Test 4: Invalid same-day (end before start)
SELECT is(
    validate_schedule_window('{"start_day": "monday", "start_time": "17:00", "end_day": "monday", "end_time": "15:00"}'::JSONB),
    FALSE,
    'Same-day window with end before start should fail'
);

-- Test 5: Missing field
SELECT is(
    validate_schedule_window('{"start_day": "monday", "start_time": "09:00", "end_day": "monday"}'::JSONB),
    FALSE,
    'Window missing end_time should fail'
);

-- Test 6: Invalid day name
SELECT is(
    validate_schedule_window('{"start_day": "notaday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}'::JSONB),
    FALSE,
    'Window with invalid day name should fail'
);

-- ============================================================================
-- OVERLAP DETECTION TESTS (Test Cases 7-11)
-- ============================================================================

-- Test 7: Same-day overlap
SELECT is(
    windows_overlap(
        '{"start_day": "monday", "start_time": "15:00", "end_day": "monday", "end_time": "17:00"}'::JSONB,
        '{"start_day": "monday", "start_time": "16:00", "end_day": "monday", "end_time": "18:00"}'::JSONB
    ),
    TRUE,
    'Same-day overlapping windows should be detected'
);

-- Test 8: Same-day adjacent (no overlap - end is exclusive)
SELECT is(
    windows_overlap(
        '{"start_day": "monday", "start_time": "15:00", "end_day": "monday", "end_time": "17:00"}'::JSONB,
        '{"start_day": "monday", "start_time": "17:00", "end_day": "monday", "end_time": "19:00"}'::JSONB
    ),
    FALSE,
    'Adjacent same-day windows should not overlap (end is exclusive)'
);

-- Test 9: Cross-day overlap
SELECT is(
    windows_overlap(
        '{"start_day": "thursday", "start_time": "23:00", "end_day": "friday", "end_time": "02:00"}'::JSONB,
        '{"start_day": "friday", "start_time": "01:00", "end_day": "friday", "end_time": "03:00"}'::JSONB
    ),
    TRUE,
    'Cross-day overlapping windows should be detected'
);

-- Test 10: Cross-day no overlap
SELECT is(
    windows_overlap(
        '{"start_day": "thursday", "start_time": "23:00", "end_day": "friday", "end_time": "01:00"}'::JSONB,
        '{"start_day": "friday", "start_time": "02:00", "end_day": "friday", "end_time": "04:00"}'::JSONB
    ),
    FALSE,
    'Non-overlapping cross-day windows should not be detected as overlap'
);

-- Test 11: Week wraparound overlap (Sat 11pm → Sun 2am overlaps with Sun 1am → Sun 3am)
SELECT is(
    windows_overlap(
        '{"start_day": "saturday", "start_time": "23:00", "end_day": "sunday", "end_time": "02:00"}'::JSONB,
        '{"start_day": "sunday", "start_time": "01:00", "end_day": "sunday", "end_time": "03:00"}'::JSONB
    ),
    TRUE,
    'Week wraparound overlapping windows should be detected'
);

-- ============================================================================
-- IN-WINDOW DETECTION TESTS (Test Cases 12-19)
-- ============================================================================

-- Test 12: Same-day, inside window
SELECT is(
    is_in_single_window(1, '10:00'::TIME, '{"start_day": "monday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}'::JSONB),
    TRUE,
    'Should be in window: Mon 10am, window Mon 9am-5pm'
);

-- Test 13: Same-day, outside window
SELECT is(
    is_in_single_window(1, '18:00'::TIME, '{"start_day": "monday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}'::JSONB),
    FALSE,
    'Should NOT be in window: Mon 6pm, window Mon 9am-5pm'
);

-- Test 14: Cross-day, on start day after start time
SELECT is(
    is_in_single_window(4, '23:30'::TIME, '{"start_day": "thursday", "start_time": "23:00", "end_day": "friday", "end_time": "01:00"}'::JSONB),
    TRUE,
    'Should be in window: Thu 11:30pm, window Thu 11pm-Fri 1am'
);

-- Test 15: Cross-day, on end day before end time
SELECT is(
    is_in_single_window(5, '00:30'::TIME, '{"start_day": "thursday", "start_time": "23:00", "end_day": "friday", "end_time": "01:00"}'::JSONB),
    TRUE,
    'Should be in window: Fri 12:30am, window Thu 11pm-Fri 1am'
);

-- Test 16: Cross-day, on end day after end time
SELECT is(
    is_in_single_window(5, '01:30'::TIME, '{"start_day": "thursday", "start_time": "23:00", "end_day": "friday", "end_time": "01:00"}'::JSONB),
    FALSE,
    'Should NOT be in window: Fri 1:30am, window Thu 11pm-Fri 1am'
);

-- Test 17: Multi-day, middle day
SELECT is(
    is_in_single_window(0, '15:00'::TIME, '{"start_day": "saturday", "start_time": "10:00", "end_day": "monday", "end_time": "08:00"}'::JSONB),
    TRUE,
    'Should be in window: Sun 3pm, window Sat 10am-Mon 8am (middle day)'
);

-- Test 18: Week wraparound (Sun 11pm → Mon 1am, check Mon 12:30am)
SELECT is(
    is_in_single_window(1, '00:30'::TIME, '{"start_day": "sunday", "start_time": "23:00", "end_day": "monday", "end_time": "01:00"}'::JSONB),
    TRUE,
    'Should be in window: Mon 12:30am, window Sun 11pm-Mon 1am'
);

-- Test 19: Not in any window when day doesn't match
SELECT is(
    is_in_single_window(2, '10:00'::TIME, '{"start_day": "monday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}'::JSONB),
    FALSE,
    'Should NOT be in window: Tue 10am, window Mon 9am-5pm'
);

-- ============================================================================
-- CONSTRAINT TESTS
-- ============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
BEGIN
    -- Create test chat
    INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode)
    VALUES ('Test Chat', 'Test', v_session_token, 'manual')
    RETURNING id INTO v_chat_id;

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Test: Valid recurring with windows (schedule is independent of start_mode)
SELECT lives_ok(
    format(
        'UPDATE public.chats SET schedule_type = ''recurring'', schedule_windows = ''[{"start_day": "monday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}]'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    'Recurring with valid windows should succeed (with manual start_mode)'
);

-- Reset
UPDATE public.chats SET schedule_type = NULL, schedule_windows = NULL
WHERE id = current_setting('test.chat_id')::INT;

-- Test: Recurring without windows should fail
SELECT throws_ok(
    format(
        'UPDATE public.chats SET schedule_type = ''recurring'', schedule_windows = NULL WHERE id = %s',
        current_setting('test.chat_id')
    ),
    '23514',
    NULL,
    'Recurring without windows should fail constraint'
);

-- Test: Recurring with empty windows should fail
SELECT throws_ok(
    format(
        'UPDATE public.chats SET schedule_type = ''recurring'', schedule_windows = ''[]'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    '23514',
    NULL,
    'Recurring with empty windows array should fail constraint'
);

-- Test: Overlapping windows should fail
SELECT throws_ok(
    format(
        'UPDATE public.chats SET schedule_type = ''recurring'', schedule_windows = ''[{"start_day": "monday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}, {"start_day": "monday", "start_time": "12:00", "end_day": "monday", "end_time": "18:00"}]'' WHERE id = %s',
        current_setting('test.chat_id')
    ),
    '23514',
    NULL,
    'Overlapping windows should fail validation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
