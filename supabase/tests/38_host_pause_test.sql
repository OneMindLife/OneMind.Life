-- Tests for host manual pause functionality
BEGIN;
SELECT plan(24);

-- ============================================================================
-- TEST SETUP: Create a chat with active round
-- ============================================================================

DO $$
DECLARE
    v_host_user_id UUID := gen_random_uuid();
    v_other_user_id UUID := gen_random_uuid();
    v_session_token UUID := gen_random_uuid();
    v_host_id INT;
    v_other_id INT;
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
BEGIN
    -- Create users
    INSERT INTO auth.users (id) VALUES (v_host_user_id);
    INSERT INTO auth.users (id) VALUES (v_other_user_id);

    -- Create chat
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, proposing_duration_seconds, rating_duration_seconds
    ) VALUES (
        'Test Host Pause Chat', 'Test message', v_session_token,
        'manual', 300, 300  -- 5 minutes each phase
    ) RETURNING id INTO v_chat_id;

    -- Create host participant
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_host_user_id, 'Host', TRUE, 'active')
    RETURNING id INTO v_host_id;

    -- Create non-host participant
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_other_user_id, 'Participant', FALSE, 'active')
    RETURNING id INTO v_other_id;

    -- Create cycle and round in proposing phase with timer set
    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + interval '5 minutes')
    RETURNING id INTO v_round_id;

    -- Store IDs for tests
    PERFORM set_config('test.host_user_id', v_host_user_id::TEXT, TRUE);
    PERFORM set_config('test.other_user_id', v_other_user_id::TEXT, TRUE);
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
END $$;

-- ============================================================================
-- SCHEMA TESTS: New column exists
-- ============================================================================

SELECT has_column('chats', 'host_paused',
    'chats table should have host_paused column');

SELECT has_function('host_pause_chat',
    'host_pause_chat function should exist');

SELECT has_function('host_resume_chat',
    'host_resume_chat function should exist');

SELECT has_function('is_chat_paused',
    'is_chat_paused function should exist');

-- ============================================================================
-- TEST: Initial state
-- ============================================================================

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'Initially host_paused should be FALSE'
);

SELECT is(
    is_chat_paused(current_setting('test.chat_id')::BIGINT),
    FALSE,
    'is_chat_paused should return FALSE initially'
);

-- ============================================================================
-- TEST: Non-host cannot pause
-- ============================================================================

-- Set auth context to non-host user
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.other_user_id'))::TEXT, TRUE);

SELECT throws_ok(
    format('SELECT host_pause_chat(%s)', current_setting('test.chat_id')::INT),
    'Only hosts can pause the chat',
    'Non-host should not be able to pause chat'
);

-- ============================================================================
-- TEST: Host can pause - saves timer state
-- ============================================================================

-- Set auth context to host user
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.host_user_id'))::TEXT, TRUE);

-- Simulate time passing (3 minutes elapsed, 2 minutes remaining)
UPDATE public.rounds
SET phase_ends_at = NOW() + interval '2 minutes'
WHERE id = current_setting('test.round_id')::INT;

-- Pause the chat
SELECT host_pause_chat(current_setting('test.chat_id')::BIGINT);

-- Verify chat is paused
SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'host_paused should be TRUE after host_pause_chat'
);

SELECT is(
    is_chat_paused(current_setting('test.chat_id')::BIGINT),
    TRUE,
    'is_chat_paused should return TRUE after pause'
);

-- Verify timer state was saved
SELECT ok(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 100 AND 130,
    'phase_time_remaining_seconds should be saved (~120 seconds)'
);

-- Verify phase_ends_at was cleared
SELECT is(
    (SELECT phase_ends_at FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'phase_ends_at should be NULL while paused'
);

-- ============================================================================
-- TEST: Host can resume - restores timer
-- ============================================================================

SELECT host_resume_chat(current_setting('test.chat_id')::BIGINT);

-- Verify chat is unpaused
SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'host_paused should be FALSE after host_resume_chat'
);

-- Verify timer was restored (now minute-aligned, so could be up to 180s due to rounding)
SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - NOW())) FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 100 AND 180,
    'phase_ends_at should be restored (~120-180 seconds from now, minute aligned)'
);

-- Verify saved time was cleared
SELECT is(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'phase_time_remaining_seconds should be NULL after resume'
);

-- ============================================================================
-- TEST: Double pause/resume is idempotent
-- ============================================================================

-- Pause twice
SELECT host_pause_chat(current_setting('test.chat_id')::BIGINT);
SELECT host_pause_chat(current_setting('test.chat_id')::BIGINT);

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'Double pause should still result in host_paused = TRUE'
);

-- Resume twice
SELECT host_resume_chat(current_setting('test.chat_id')::BIGINT);
SELECT host_resume_chat(current_setting('test.chat_id')::BIGINT);

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'Double resume should still result in host_paused = FALSE'
);

-- ============================================================================
-- TEST: is_chat_paused with schedule_paused
-- ============================================================================

-- Set schedule_paused = true (host_paused is already false from previous test)
UPDATE public.chats SET schedule_paused = true WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_paused(current_setting('test.chat_id')::BIGINT),
    TRUE,
    'is_chat_paused should return TRUE when schedule_paused is TRUE'
);

-- Set both pauses to true
UPDATE public.chats SET host_paused = true WHERE id = current_setting('test.chat_id')::INT;

SELECT is(
    is_chat_paused(current_setting('test.chat_id')::BIGINT),
    TRUE,
    'is_chat_paused should return TRUE when both pauses are TRUE'
);

-- ============================================================================
-- TEST: Host resume while schedule is also paused
-- ============================================================================

-- Setup: host_paused=true, schedule_paused=true, timer saved
UPDATE public.rounds
SET phase_ends_at = NULL,
    phase_time_remaining_seconds = 60
WHERE id = current_setting('test.round_id')::INT;

-- Host resumes (but schedule is still paused)
SELECT host_resume_chat(current_setting('test.chat_id')::BIGINT);

-- host_paused should be cleared
SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'host_paused should be FALSE after resume even with schedule paused'
);

-- But timer should NOT be restored (schedule still blocking)
SELECT is(
    (SELECT phase_ends_at FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'phase_ends_at should remain NULL when schedule is still paused'
);

-- Saved time should still be preserved for when schedule resumes
SELECT is(
    (SELECT phase_time_remaining_seconds FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    60,
    'phase_time_remaining_seconds should be preserved when schedule is still paused'
);

-- ============================================================================
-- TEST: Resume aligns phase_ends_at to whole minutes (:00 seconds)
-- ============================================================================

-- Setup: Clear schedule pause, set saved time
UPDATE public.chats SET schedule_paused = false, host_paused = true
WHERE id = current_setting('test.chat_id')::INT;

UPDATE public.rounds
SET phase_ends_at = NULL,
    phase_time_remaining_seconds = 90  -- 1.5 minutes
WHERE id = current_setting('test.round_id')::INT;

-- Resume the chat
SELECT host_resume_chat(current_setting('test.chat_id')::BIGINT);

-- Verify phase_ends_at has :00 seconds (aligned to whole minute)
SELECT is(
    (SELECT EXTRACT(SECOND FROM phase_ends_at)::INTEGER FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT),
    0,
    'phase_ends_at should end at :00 seconds (minute aligned)'
);

-- Verify the time is approximately correct (should be 2+ minutes from now due to rounding up)
-- 90 seconds + rounding up to next minute = at least 90 seconds, at most ~150 seconds
SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - NOW())) FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT) BETWEEN 90 AND 180,
    'phase_ends_at should be 90-180 seconds from now (minute aligned)'
);

-- Verify phase_time_remaining_seconds was cleared
SELECT is(
    (SELECT phase_time_remaining_seconds FROM public.rounds
     WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'phase_time_remaining_seconds should be NULL after minute-aligned resume'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
