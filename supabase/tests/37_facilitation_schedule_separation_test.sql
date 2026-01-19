-- Tests for facilitation mode and schedule being independent concepts
-- Facilitation (start_mode): 'manual' or 'auto' - how proposing starts
-- Schedule (schedule_type): NULL, 'once', or 'recurring' - when chat room is open
-- These are orthogonal and can be combined in any way.
BEGIN;
SELECT plan(24);

-- ============================================================================
-- TEST DATA SETUP
-- ============================================================================

DO $$
DECLARE
    v_session_token_1 UUID := gen_random_uuid();
    v_session_token_2 UUID := gen_random_uuid();
BEGIN
    PERFORM set_config('test.session_token_1', v_session_token_1::TEXT, TRUE);
    PERFORM set_config('test.session_token_2', v_session_token_2::TEXT, TRUE);
END $$;

-- ============================================================================
-- CONSTRAINT TESTS: start_mode only allows 'manual' and 'auto'
-- ============================================================================

-- Test 1: start_mode 'manual' is valid
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode)
      VALUES ('Manual Mode Chat', 'Test', '$$ || current_setting('test.session_token_1') || $$', 'manual')$$,
    'start_mode=manual should be valid'
);

-- Test 2: start_mode 'auto' is valid
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode, auto_start_participant_count)
      VALUES ('Auto Mode Chat', 'Test', '$$ || current_setting('test.session_token_1') || $$', 'auto', 5)$$,
    'start_mode=auto should be valid'
);

-- Test 3: start_mode 'scheduled' is NOT valid (must use schedule_type instead)
SELECT throws_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode)
      VALUES ('Invalid Scheduled Chat', 'Test', '$$ || current_setting('test.session_token_1') || $$', 'scheduled')$$,
    '23514',
    NULL,
    'start_mode=scheduled should NOT be valid (use schedule_type instead)'
);

-- ============================================================================
-- COMBINATION TESTS: Manual facilitation with different schedules
-- ============================================================================

-- Test 4: Manual + No Schedule (always open, host starts)
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode, schedule_type)
      VALUES ('Manual No Schedule', 'Test', '$$ || current_setting('test.session_token_1') || $$', 'manual', NULL)$$,
    'manual + no schedule should be valid'
);

-- Test 5: Manual + One-time Schedule (opens once, host starts)
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode, schedule_type, scheduled_start_at)
      VALUES ('Manual Once Schedule', 'Test', '$$ || current_setting('test.session_token_1') || $$', 'manual', 'once', NOW() + interval '1 hour')$$,
    'manual + one-time schedule should be valid'
);

-- Test 6: Manual + Recurring Schedule (opens on schedule, host starts)
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode, schedule_type, schedule_windows)
      VALUES ('Manual Recurring', 'Test', '$$ || current_setting('test.session_token_1') || $$', 'manual', 'recurring',
              '[{"start_day": "monday", "start_time": "09:00", "end_day": "friday", "end_time": "17:00"}]')$$,
    'manual + recurring schedule should be valid'
);

-- ============================================================================
-- COMBINATION TESTS: Auto facilitation with different schedules
-- (use second session token to avoid rate limit)
-- ============================================================================

-- Test 7: Auto + No Schedule (always open, starts on participant count)
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode, auto_start_participant_count, schedule_type)
      VALUES ('Auto No Schedule', 'Test', '$$ || current_setting('test.session_token_2') || $$', 'auto', 5, NULL)$$,
    'auto + no schedule should be valid'
);

-- Test 8: Auto + One-time Schedule (opens once, starts on participant count)
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode, auto_start_participant_count, schedule_type, scheduled_start_at)
      VALUES ('Auto Once Schedule', 'Test', '$$ || current_setting('test.session_token_2') || $$', 'auto', 5, 'once', NOW() + interval '1 hour')$$,
    'auto + one-time schedule should be valid'
);

-- Test 9: Auto + Recurring Schedule (opens on schedule, starts on participant count)
SELECT lives_ok(
    $$INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode, auto_start_participant_count, schedule_type, schedule_windows)
      VALUES ('Auto Recurring', 'Test', '$$ || current_setting('test.session_token_2') || $$', 'auto', 5, 'recurring',
              '[{"start_day": "monday", "start_time": "09:00", "end_day": "friday", "end_time": "17:00"}]')$$,
    'auto + recurring schedule should be valid'
);

-- ============================================================================
-- is_chat_in_schedule_window FUNCTION TESTS
-- ============================================================================

-- Test 10: Chat with no schedule is always in window (manual mode)
SELECT is(
    (SELECT is_chat_in_schedule_window(id::INT) FROM public.chats WHERE name = 'Manual No Schedule'),
    TRUE,
    'Manual + no schedule: always in window'
);

-- Test 11: Chat with no schedule is always in window (auto mode)
SELECT is(
    (SELECT is_chat_in_schedule_window(id::INT) FROM public.chats WHERE name = 'Auto No Schedule'),
    TRUE,
    'Auto + no schedule: always in window'
);

-- Test 12: Chat with future one-time schedule is NOT in window (manual mode)
SELECT is(
    (SELECT is_chat_in_schedule_window(id::INT) FROM public.chats WHERE name = 'Manual Once Schedule'),
    FALSE,
    'Manual + future one-time schedule: not in window'
);

-- Test 13: Chat with future one-time schedule is NOT in window (auto mode)
SELECT is(
    (SELECT is_chat_in_schedule_window(id::INT) FROM public.chats WHERE name = 'Auto Once Schedule'),
    FALSE,
    'Auto + future one-time schedule: not in window'
);

-- ============================================================================
-- schedule_paused BEHAVIOR TESTS
-- ============================================================================

-- Store chat ID for testing
DO $$
DECLARE
    v_manual_recurring_id INT;
BEGIN
    SELECT id INTO v_manual_recurring_id FROM public.chats WHERE name = 'Manual Recurring';
    PERFORM set_config('test.manual_recurring_id', v_manual_recurring_id::TEXT, TRUE);
END $$;

-- Test 14: Pausing schedule works
UPDATE public.chats SET schedule_paused = TRUE WHERE id = current_setting('test.manual_recurring_id')::INT;
SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.manual_recurring_id')::INT),
    TRUE,
    'Manual + recurring: can pause schedule'
);

-- Test 15: schedule_paused flag is independent of is_chat_in_schedule_window
-- The is_chat_in_schedule_window checks time-based windows only
-- schedule_paused is used at a higher level (process_scheduled_chats, app layer)
SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE id = current_setting('test.manual_recurring_id')::INT),
    TRUE,
    'schedule_paused flag is stored correctly'
);

-- Reset pause state
UPDATE public.chats SET schedule_paused = FALSE
WHERE id = current_setting('test.manual_recurring_id')::INT;

-- ============================================================================
-- DEFAULT VALUE TESTS
-- ============================================================================

-- Test 16: Default start_mode is manual
SELECT is(
    (SELECT start_mode FROM public.chats WHERE name = 'Manual No Schedule'),
    'manual',
    'start_mode can be manual'
);

-- Test 17: start_mode can be auto
SELECT is(
    (SELECT start_mode FROM public.chats WHERE name = 'Auto No Schedule'),
    'auto',
    'start_mode can be auto'
);

-- Test 18: Default visible_outside_schedule is TRUE
SELECT is(
    (SELECT visible_outside_schedule FROM public.chats WHERE name = 'Manual No Schedule'),
    TRUE,
    'Default visible_outside_schedule is TRUE'
);

-- Test 19: Default schedule_paused is FALSE
SELECT is(
    (SELECT schedule_paused FROM public.chats WHERE name = 'Manual No Schedule'),
    FALSE,
    'Default schedule_paused is FALSE'
);

-- ============================================================================
-- QUERY PATTERN TESTS (how backend queries scheduled chats)
-- ============================================================================

-- Test 20: Can query chats with schedule by schedule_type IS NOT NULL
SELECT is(
    (SELECT COUNT(*) FROM public.chats
     WHERE schedule_type IS NOT NULL
     AND creator_session_token IN (
         current_setting('test.session_token_1')::UUID,
         current_setting('test.session_token_2')::UUID
     ))::INT >= 4,
    TRUE,
    'Can find scheduled chats by schedule_type IS NOT NULL'
);

-- Test 21: Schedule query works for both manual and auto modes
SELECT is(
    (SELECT COUNT(DISTINCT start_mode) FROM public.chats
     WHERE schedule_type IS NOT NULL
     AND creator_session_token IN (
         current_setting('test.session_token_1')::UUID,
         current_setting('test.session_token_2')::UUID
     ))::INT,
    2,
    'Both manual and auto modes can have schedules'
);

-- ============================================================================
-- ORTHOGONALITY TESTS: start_mode is independent of schedule_type
-- ============================================================================

-- Test 22: Manual mode with schedule_type='once' exists
SELECT is(
    (SELECT COUNT(*) FROM public.chats
     WHERE start_mode = 'manual' AND schedule_type = 'once'
     AND creator_session_token = current_setting('test.session_token_1')::UUID)::INT,
    1,
    'manual + once schedule combination exists'
);

-- Test 23: Auto mode with schedule_type='once' exists
SELECT is(
    (SELECT COUNT(*) FROM public.chats
     WHERE start_mode = 'auto' AND schedule_type = 'once'
     AND creator_session_token = current_setting('test.session_token_2')::UUID)::INT,
    1,
    'auto + once schedule combination exists'
);

-- Test 24: Manual mode with schedule_type='recurring' exists
SELECT is(
    (SELECT COUNT(*) FROM public.chats
     WHERE start_mode = 'manual' AND schedule_type = 'recurring'
     AND creator_session_token = current_setting('test.session_token_1')::UUID)::INT,
    1,
    'manual + recurring schedule combination exists'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE creator_session_token IN (
    current_setting('test.session_token_1')::UUID,
    current_setting('test.session_token_2')::UUID
);

SELECT * FROM finish();
ROLLBACK;
