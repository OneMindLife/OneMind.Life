-- Auto-start must require at least one HUMAN participant, never start on agents
-- alone, and still preserve solo-game AI seat-fill (1 human + AI seats reaching
-- the threshold).
--
-- Regression for the 2026-07-08 bug: a public chat with enable_agents=true got a
-- persona agent auto-joined at creation; with auto_start_participant_count=1 that
-- lone agent tripped check_auto_start_on_participant_join and the chat started
-- with zero humans, cascading empty agent-only rounds.
--
-- Migration: 20260708233000_auto_start_requires_human.sql

BEGIN;
SELECT plan(6);

-- ===========================================================================
-- Scenario 1: threshold=1. An agent alone must NOT start; one human must.
-- ===========================================================================
DO $$
DECLARE
    v_chat_id INT;
    v_human_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id) VALUES (v_human_id);

    INSERT INTO public.chats (
        name, initial_message,
        start_mode, auto_start_participant_count,
        proposing_duration_seconds, rating_duration_seconds,
        access_method
    ) VALUES (
        'Test: Auto Start Requires Human (t=1)', 'Q?',
        'auto', 1,
        60, 60,
        'code'
    ) RETURNING id INTO v_chat_id;

    -- Agent joins first (is_agent=true, session-token seat, no user_id)
    INSERT INTO public.participants (chat_id, session_token, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, gen_random_uuid(), 'AI', FALSE, 'active', TRUE);

    PERFORM set_config('test.s1_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.s1_human_id', v_human_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.s1_chat_id')::INT),
    0,
    'threshold=1: lone agent does NOT auto-start (zero humans present)'
);

-- Now a human joins → 1 active human, meets threshold=1 → starts
INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.s1_chat_id')::INT, current_setting('test.s1_human_id')::UUID, 'Human', FALSE, 'active');

SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.s1_chat_id')::INT),
    1,
    'threshold=1: first human meets threshold → auto-starts'
);

-- ===========================================================================
-- Scenario 2: threshold=2, solo-game seat-fill. 1 human + 1 agent = 2 active
-- participants with >=1 human → MUST start (preserves AI seat-fill for a lone
-- human).
-- ===========================================================================
DO $$
DECLARE
    v_chat_id INT;
    v_human_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id) VALUES (v_human_id);

    INSERT INTO public.chats (
        name, initial_message,
        start_mode, auto_start_participant_count,
        proposing_duration_seconds, rating_duration_seconds,
        access_method
    ) VALUES (
        'Test: Solo Game Seat-Fill (t=2)', 'Q?',
        'auto', 2,
        60, 60,
        'code'
    ) RETURNING id INTO v_chat_id;

    -- One agent seat (total active = 1, humans = 0) → below threshold, no start
    INSERT INTO public.participants (chat_id, session_token, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, gen_random_uuid(), 'AI', FALSE, 'active', TRUE);

    PERFORM set_config('test.s2_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.s2_human_id', v_human_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.s2_chat_id')::INT),
    0,
    'threshold=2: 1 agent alone is below threshold → no start'
);

-- Human joins → total active = 2 (1 human + 1 agent), >=1 human, >= threshold → starts
INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.s2_chat_id')::INT, current_setting('test.s2_human_id')::UUID, 'Human', FALSE, 'active');

SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.s2_chat_id')::INT),
    1,
    'threshold=2: 1 human + 1 agent seat reaches threshold → auto-starts (solo-game preserved)'
);

-- ===========================================================================
-- Scenario 3: threshold=2, pure human. Unchanged behavior — starts on 2 humans.
-- ===========================================================================
DO $$
DECLARE
    v_chat_id INT;
    v_h1 UUID := gen_random_uuid();
    v_h2 UUID := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id) VALUES (v_h1);
    INSERT INTO auth.users (id) VALUES (v_h2);

    INSERT INTO public.chats (
        name, initial_message,
        start_mode, auto_start_participant_count,
        proposing_duration_seconds, rating_duration_seconds,
        access_method
    ) VALUES (
        'Test: Pure Human Start (t=2)', 'Q?',
        'auto', 2,
        60, 60,
        'code'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_h1, 'Human 1', FALSE, 'active');

    PERFORM set_config('test.s3_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.s3_h2', v_h2::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.s3_chat_id')::INT),
    0,
    'threshold=2: 1 human is below threshold → no start'
);

INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
VALUES (current_setting('test.s3_chat_id')::INT, current_setting('test.s3_h2')::UUID, 'Human 2', FALSE, 'active');

SELECT is(
    (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.s3_chat_id')::INT),
    1,
    'threshold=2: second human reaches threshold → auto-starts'
);

SELECT * FROM finish();
ROLLBACK;
