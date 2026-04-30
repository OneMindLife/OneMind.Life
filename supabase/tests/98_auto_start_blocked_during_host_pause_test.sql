-- Auto-start trigger must respect host_paused.
-- Companion behavior: host_resume_chat retries auto-start if the participant
-- threshold was reached during the pause window.
--
-- Migration: 20260429120000_block_auto_start_during_host_pause.sql

BEGIN;
SELECT plan(14);

DO $$
DECLARE
    v_host_user_id UUID := gen_random_uuid();
    v_user1_id UUID := gen_random_uuid();
    v_user2_id UUID := gen_random_uuid();
    v_chat_id INT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_host_user_id);
    INSERT INTO auth.users (id) VALUES (v_user1_id);
    INSERT INTO auth.users (id) VALUES (v_user2_id);

    INSERT INTO public.chats (
        name, initial_message,
        start_mode, auto_start_participant_count,
        proposing_duration_seconds, rating_duration_seconds,
        access_method
    ) VALUES (
        'Test: Auto Start During Pause', 'Q?',
        'auto', 3,
        60, 60,
        'code'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_host_user_id, 'Host', TRUE, 'active');

    PERFORM set_config('test.host_user_id', v_host_user_id::TEXT, TRUE);
    PERFORM set_config('test.user1_id', v_user1_id::TEXT, TRUE);
    PERFORM set_config('test.user2_id', v_user2_id::TEXT, TRUE);
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Sanity: no cycle yet
SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
    0,
    'No cycle when 1 participant (below threshold)'
);

-- Host pauses the chat as their first action
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.host_user_id'))::TEXT, TRUE);
SELECT host_pause_chat(current_setting('test.chat_id')::BIGINT);
RESET ROLE;

SELECT is(
    (SELECT host_paused FROM chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'Chat is paused after host_pause_chat'
);

-- Two more participants join while paused → threshold reached
INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user1_id')::UUID, 'User 1', FALSE, 'active');

INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, current_setting('test.user2_id')::UUID, 'User 2', FALSE, 'active');

-- Auto-start must NOT fire during pause
SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
    0,
    'No cycle created while host_paused (threshold reached but pause blocks auto-start)'
);

SELECT is(
    (SELECT COUNT(*)::INT
     FROM rounds r
     JOIN cycles c ON r.cycle_id = c.id
     WHERE c.chat_id = current_setting('test.chat_id')::INT),
    0,
    'No round created while host_paused'
);

SELECT is(
    (SELECT host_paused FROM chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'Chat is still host_paused after threshold-reaching join'
);

-- Now host resumes — auto-start retry should fire because threshold is already met
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.host_user_id'))::TEXT, TRUE);
SELECT host_resume_chat(current_setting('test.chat_id')::BIGINT);
RESET ROLE;

SELECT is(
    (SELECT host_paused FROM chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'Chat is no longer paused after host_resume_chat'
);

SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT),
    1,
    'Resume retried auto-start: cycle now exists'
);

SELECT is(
    (SELECT phase
     FROM rounds r
     JOIN cycles c ON r.cycle_id = c.id
     WHERE c.chat_id = current_setting('test.chat_id')::INT
     ORDER BY r.id LIMIT 1),
    'proposing',
    'Resume retried auto-start: round is in proposing phase'
);

SELECT ok(
    (SELECT phase_ends_at IS NOT NULL
     FROM rounds r
     JOIN cycles c ON r.cycle_id = c.id
     WHERE c.chat_id = current_setting('test.chat_id')::INT
     ORDER BY r.id LIMIT 1),
    'Resume retried auto-start: phase_ends_at is set'
);

-- Resume's auto-start delegates to create_round_for_cycle, which uses
-- calculate_round_minute_end() for cron alignment. With a 60s phase the
-- end time rounds up to the next :00 minute boundary, so the actual
-- remaining time is in [60, 120) seconds.
SELECT ok(
    (SELECT phase_ends_at >= NOW() + INTERVAL '60 seconds'
            AND phase_ends_at <  NOW() + INTERVAL '120 seconds'
     FROM rounds r
     JOIN cycles c ON r.cycle_id = c.id
     WHERE c.chat_id = current_setting('test.chat_id')::INT
     ORDER BY r.id LIMIT 1),
    'Resume auto-start sets minute-aligned phase_ends_at in [60s, 120s)'
);

SELECT ok(
    (SELECT EXTRACT(SECOND FROM phase_ends_at)::INT = 0
     FROM rounds r
     JOIN cycles c ON r.cycle_id = c.id
     WHERE c.chat_id = current_setting('test.chat_id')::INT
     ORDER BY r.id LIMIT 1),
    'Resume auto-start phase_ends_at falls on a :00 second boundary (cron alignment)'
);

-- Resume's auto-start path also funds participants via create_round_for_cycle.
-- All 3 active participants who joined while paused should now be funded for
-- the round that was created on resume.
SELECT is(
    (SELECT COUNT(*)::INT
     FROM round_funding rf
     JOIN rounds r ON r.id = rf.round_id
     JOIN cycles c ON c.id = r.cycle_id
     WHERE c.chat_id = current_setting('test.chat_id')::INT),
    3,
    'Resume auto-start funded all 3 participants who joined during pause'
);

-- ===========================================================================
-- Late-joiner regression coverage. This is the bug introduced by the prior
-- migration (20260429211818) and fixed here: a participant joining a chat
-- that already has an active round MUST receive a round_funding row, not
-- be silently spectator-locked.
-- ===========================================================================
DO $$
DECLARE
    v_late_user_id UUID := gen_random_uuid();
    v_late_pid INT;
    v_round_id INT;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_late_user_id);

    SELECT r.id INTO v_round_id
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE c.chat_id = current_setting('test.chat_id')::INT
    ORDER BY r.id LIMIT 1;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (
        current_setting('test.chat_id')::INT,
        v_late_user_id,
        'Late Joiner',
        FALSE,
        'active'
    ) RETURNING id INTO v_late_pid;

    PERFORM set_config('test.late_pid', v_late_pid::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT COUNT(*)::INT
     FROM round_funding
     WHERE round_id = current_setting('test.round_id')::INT
       AND participant_id = current_setting('test.late_pid')::INT),
    1,
    'Mid-round joiner is funded for the active round (regression test for the bug)'
);

SELECT is(
    (SELECT COUNT(*)::INT
     FROM round_funding rf
     JOIN rounds r ON r.id = rf.round_id
     JOIN cycles c ON c.id = r.cycle_id
     WHERE c.chat_id = current_setting('test.chat_id')::INT),
    4,
    'Total funded participants is now 4 (3 originals + 1 late joiner)'
);

SELECT * FROM finish();
ROLLBACK;
