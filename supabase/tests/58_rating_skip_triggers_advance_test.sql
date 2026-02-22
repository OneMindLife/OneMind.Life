-- Tests that a rating skip INSERT can trigger early advance
-- Scenario: 3 participants, rating_minimum=2, 50% threshold
-- User1 rates, then User2 skips → skip pushes over threshold → round completes
BEGIN;
SELECT plan(5);

-- =============================================================================
-- SETUP: 3 participants, 50% rating threshold, rating_minimum=2
-- max rating skips = 3 - 2 = 1
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
    v_prop_a_id INT;
    v_prop_b_id INT;
    v_prop_c_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum
    ) VALUES (
        'SkipTriggersAdvance', 'Test', v_session_token,
        'auto', 99,
        50, NULL,   -- 50% threshold
        300, 300,
        2, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User1', 'active', gen_random_uuid()) RETURNING id INTO v_user1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User2', 'active', gen_random_uuid()) RETURNING id INTO v_user2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User3', 'active', gen_random_uuid()) RETURNING id INTO v_user3_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user1_id, 'Prop A') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_id, 'Prop B') RETURNING id INTO v_prop_b_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user3_id, 'Prop C') RETURNING id INTO v_prop_c_id;

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.user1_id', v_user1_id::TEXT, TRUE);
    PERFORM set_config('test.user2_id', v_user2_id::TEXT, TRUE);
    PERFORM set_config('test.user3_id', v_user3_id::TEXT, TRUE);
    PERFORM set_config('test.prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.prop_c_id', v_prop_c_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST 1: Initial state
-- =============================================================================

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'rating',
    'Initial: Round in rating phase'
);

-- =============================================================================
-- TEST 2: User1 rates Prop B and Prop C (skips own Prop A)
-- 50% threshold with 3 participants: required = CEIL(3*50/100) = 2
-- Cap at participants - 1 = 2, so required = 2
-- avg = 2/3 = 0.67, need 2 → NOT met
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_b_id')::INT, current_setting('test.user1_id')::INT, current_setting('test.round_id')::INT, 80),
    (current_setting('test.prop_c_id')::INT, current_setting('test.user1_id')::INT, current_setting('test.round_id')::INT, 60);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After User1 rates: NOT completed (avg=0.67, need 2)'
);

-- =============================================================================
-- TEST 3: User2 skips rating
-- With 1 skipper: required = LEAST(2, 3-1-1) = LEAST(2, 1) = 1
-- avg is still 2/3 = 0.67, need 1. 0.67 < 1. NOT met yet.
-- =============================================================================

INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.round_id')::INT, current_setting('test.user2_id')::INT);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After User2 skips (avg=0.67, need 1): NOT completed'
);

-- =============================================================================
-- TEST 4: User3 rates Prop A and Prop B (skips own Prop C)
-- Total: 4 ratings / 3 props = 1.33 avg raters/prop
-- With 1 skipper: required = LEAST(2, 3-1-1) = 1
-- 1.33 >= 1 → MET! Round completes.
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_a_id')::INT, current_setting('test.user3_id')::INT, current_setting('test.round_id')::INT, 70),
    (current_setting('test.prop_b_id')::INT, current_setting('test.user3_id')::INT, current_setting('test.round_id')::INT, 50);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After User3 rates (avg=1.33 >= 1): COMPLETED - skip lowered threshold'
);

-- =============================================================================
-- TEST 5: Winner was calculated
-- =============================================================================

SELECT is(
    (SELECT winning_proposition_id IS NOT NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'Round has a winning proposition'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
