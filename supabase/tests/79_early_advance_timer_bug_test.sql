-- Tests for the phase_ends_at calculation bug in check_early_advance_on_skip
-- and check_early_advance_on_proposition triggers.
--
-- BUG: These triggers calculate phase_ends_at as:
--   date_trunc('minute', NOW()) + INTERVAL '1 minute' * CEIL(duration / 60.0)
-- This truncates NOW() to minute start BEFORE adding duration, producing a timer
-- that can be as short as 1 second when the trigger fires late in a minute.
--
-- CORRECT formula (used by process-timers edge function):
--   round_up_to_minute(NOW() + duration)
-- This adds duration to NOW() first, then rounds up.

BEGIN;
SELECT plan(8);

-- =============================================================================
-- SETUP: Chat with 60-second rating timer, 100% proposing threshold
-- =============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_user1_id INT;
    v_user2_id INT;
    v_user3_id INT;
    v_user4_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        proposing_threshold_percent, proposing_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum,
        rating_start_mode
    ) VALUES (
        'EarlyAdvanceTimerBugTest', 'Test', v_session_token,
        'auto', 99,
        100, 3,        -- 100% threshold, count=3
        300, 60,       -- 60-second rating timer (key for the bug)
        3, 2,
        'auto'
    ) RETURNING id INTO v_chat_id;

    -- 4 participants
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User1', 'active', gen_random_uuid()) RETURNING id INTO v_user1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User2', 'active', gen_random_uuid()) RETURNING id INTO v_user2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User3', 'active', gen_random_uuid()) RETURNING id INTO v_user3_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User4', 'active', gen_random_uuid()) RETURNING id INTO v_user4_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Round in proposing phase
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- 3 users submit propositions (meets proposing_minimum=3)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user1_id, 'Proposition A');
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_id, 'Proposition B');
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user3_id, 'Proposition C');

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.user4_id', v_user4_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST 1: Round starts in proposing phase
-- =============================================================================

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'proposing',
    'Round starts in proposing phase'
);

-- =============================================================================
-- TEST 2: User4 skips → triggers early advance to rating
-- (3 propositions + 1 skip = 4/4 = 100% threshold met)
-- =============================================================================

DO $$
BEGIN
    INSERT INTO public.round_skips (round_id, participant_id)
    VALUES (
        current_setting('test.round_id')::INT,
        current_setting('test.user4_id')::INT
    );
END $$;

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'rating',
    'Phase advanced to rating after skip meets 100% threshold'
);

-- =============================================================================
-- TEST 3: phase_started_at was set
-- =============================================================================

SELECT isnt(
    (SELECT phase_started_at FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'phase_started_at is set after advancing to rating'
);

-- =============================================================================
-- TEST 4: phase_ends_at was set
-- =============================================================================

SELECT isnt(
    (SELECT phase_ends_at FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    NULL,
    'phase_ends_at is set after advancing to rating'
);

-- =============================================================================
-- TEST 5: phase_ends_at is in the future
-- BUG: With the date_trunc formula, phase_ends_at can be in the PAST
--      if the trigger fires late in a minute (e.g. at :55 seconds,
--      phase_ends_at = start_of_current_minute + 1 min = only 5 sec away)
-- =============================================================================

SELECT ok(
    (SELECT phase_ends_at > NOW() FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'phase_ends_at should be in the future'
);

-- =============================================================================
-- TEST 6 (KEY BUG TEST): Timer gives at least rating_duration_seconds
-- The rating timer is 60 seconds. phase_ends_at should be at least 60 seconds
-- after phase_started_at (rounded up to the next minute boundary).
--
-- BUG: date_trunc('minute', NOW()) + 1 minute gives a timer of (60 - seconds_past_minute).
--      When the trigger fires at XX:YY:55, this is only 5 seconds!
-- =============================================================================

SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - phase_started_at)) >= 60
     FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'Timer must give at least rating_duration_seconds (60s) from phase_started_at'
);

-- =============================================================================
-- TEST 7: Same bug in check_early_advance_on_proposition
-- Setup a new round and trigger advance via proposition insert
-- =============================================================================

DO $$
DECLARE
    v_round2_id INT;
    v_new_user_id INT;
BEGIN
    -- Create a new round in proposing with 100% threshold
    INSERT INTO public.rounds (
        cycle_id, custom_id, phase, phase_started_at, phase_ends_at
    ) VALUES (
        current_setting('test.cycle_id')::INT, 2,
        'proposing', NOW(), NOW() + INTERVAL '5 minutes'
    ) RETURNING id INTO v_round2_id;

    -- Need a 4th proposer. Reuse users 1-3 for propositions.
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round2_id, (SELECT id FROM public.participants
            WHERE chat_id = current_setting('test.chat_id')::INT
            AND display_name = 'User1' LIMIT 1), 'R2 Prop A');
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round2_id, (SELECT id FROM public.participants
            WHERE chat_id = current_setting('test.chat_id')::INT
            AND display_name = 'User2' LIMIT 1), 'R2 Prop B');
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round2_id, (SELECT id FROM public.participants
            WHERE chat_id = current_setting('test.chat_id')::INT
            AND display_name = 'User3' LIMIT 1), 'R2 Prop C');

    -- User4's proposition will be the 4th (100% = 4/4).
    -- This INSERT fires check_early_advance_on_proposition trigger.
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round2_id, current_setting('test.user4_id')::INT, 'R2 Prop D');

    PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round2_id')::INT),
    'rating',
    'Proposition trigger also advances to rating when threshold met'
);

-- =============================================================================
-- TEST 8: Proposition trigger also has correct timer duration
-- =============================================================================

SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - phase_started_at)) >= 60
     FROM public.rounds WHERE id = current_setting('test.round2_id')::INT),
    'Proposition trigger timer must also give at least 60s from phase_started_at'
);

SELECT * FROM finish();
ROLLBACK;
