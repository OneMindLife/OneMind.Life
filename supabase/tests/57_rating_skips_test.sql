-- Tests for rating_skips table, RLS policies, and early advance triggers
BEGIN;
SELECT plan(10);

-- =============================================================================
-- SETUP: 4 participants, 100% rating threshold, each has 1 proposition
-- rating_minimum = 2 → max rating skips = 4 - 2 = 2
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
    v_prop_a_id INT;
    v_prop_b_id INT;
    v_prop_c_id INT;
    v_prop_d_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum
    ) VALUES (
        'RatingSkipTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL,   -- 100% percent threshold, no count threshold
        300, 300,
        3, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User1', 'active', gen_random_uuid()) RETURNING id INTO v_user1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User2', 'active', gen_random_uuid()) RETURNING id INTO v_user2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User3', 'active', gen_random_uuid()) RETURNING id INTO v_user3_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User4', 'active', gen_random_uuid()) RETURNING id INTO v_user4_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Each user has one proposition
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user1_id, 'Prop A') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_id, 'Prop B') RETURNING id INTO v_prop_b_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user3_id, 'Prop C') RETURNING id INTO v_prop_c_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user4_id, 'Prop D') RETURNING id INTO v_prop_d_id;

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.user1_id', v_user1_id::TEXT, TRUE);
    PERFORM set_config('test.user2_id', v_user2_id::TEXT, TRUE);
    PERFORM set_config('test.user3_id', v_user3_id::TEXT, TRUE);
    PERFORM set_config('test.user4_id', v_user4_id::TEXT, TRUE);
    PERFORM set_config('test.prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.prop_c_id', v_prop_c_id::TEXT, TRUE);
    PERFORM set_config('test.prop_d_id', v_prop_d_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST 1: rating_skips table exists
-- =============================================================================

SELECT is(
    (SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'rating_skips')),
    true,
    'rating_skips table exists'
);

-- =============================================================================
-- TEST 2: Initial state - round in rating phase
-- =============================================================================

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'rating',
    'Initial: Round in rating phase'
);

-- =============================================================================
-- TEST 3: count_rating_skips returns 0 initially
-- =============================================================================

SELECT is(
    count_rating_skips(current_setting('test.round_id')::INT),
    0,
    'No rating skips initially'
);

-- =============================================================================
-- TEST 4: User3 skips rating - skip is recorded
-- =============================================================================

INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.round_id')::INT, current_setting('test.user3_id')::INT);

SELECT is(
    count_rating_skips(current_setting('test.round_id')::INT),
    1,
    'After User3 skips: 1 rating skip recorded'
);

-- =============================================================================
-- TEST 5: Round NOT completed yet after one skip (only skip, no ratings)
-- =============================================================================

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 1 skip, 0 ratings: NOT completed'
);

-- =============================================================================
-- TEST 6: User4 skips rating - 2 skips total (max allowed with 4 participants, rating_minimum=2)
-- =============================================================================

INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.round_id')::INT, current_setting('test.user4_id')::INT);

SELECT is(
    count_rating_skips(current_setting('test.round_id')::INT),
    2,
    'After User4 skips: 2 rating skips recorded'
);

-- =============================================================================
-- TEST 7: User1 rates (skips own Prop A, rates B, C, D)
-- With 2 skippers: required = LEAST(CEIL(4*100/100), 4-1-2) = LEAST(4, 1) = 1
-- After User1: avg = 3/4 = 0.75 raters/prop. Need 1. 0.75 < 1. NOT met.
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_b_id')::INT, current_setting('test.user1_id')::INT, current_setting('test.round_id')::INT, 80),
    (current_setting('test.prop_c_id')::INT, current_setting('test.user1_id')::INT, current_setting('test.round_id')::INT, 60),
    (current_setting('test.prop_d_id')::INT, current_setting('test.user1_id')::INT, current_setting('test.round_id')::INT, 40);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After User1 rates (avg=0.75, need 1): NOT completed'
);

-- =============================================================================
-- TEST 8: User2 rates (skips own Prop B, rates A, C, D)
-- After User2: total=6 ratings / 4 props = 1.5 avg raters/prop. Need 1. 1.5 >= 1. MET!
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_a_id')::INT, current_setting('test.user2_id')::INT, current_setting('test.round_id')::INT, 70),
    (current_setting('test.prop_c_id')::INT, current_setting('test.user2_id')::INT, current_setting('test.round_id')::INT, 50),
    (current_setting('test.prop_d_id')::INT, current_setting('test.user2_id')::INT, current_setting('test.round_id')::INT, 30);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After User2 rates (avg=1.5 >= 1): COMPLETED with rating skips lowering threshold'
);

-- =============================================================================
-- TEST 9: Winner was calculated
-- =============================================================================

SELECT is(
    (SELECT winning_proposition_id IS NOT NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'Round has a winning proposition'
);

-- =============================================================================
-- TEST 10: Unique constraint prevents duplicate rating skips
-- =============================================================================

-- Try to insert another skip for User3 (already skipped) - use a new round
DO $$
DECLARE
    v_new_round_id INT;
    v_next_custom_id INT;
BEGIN
    -- Get next available custom_id (round completion may have created additional rounds)
    SELECT COALESCE(MAX(custom_id), 0) + 1 INTO v_next_custom_id
    FROM public.rounds r
    JOIN public.cycles c ON c.id = r.cycle_id
    WHERE c.chat_id = current_setting('test.chat_id')::INT;

    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (
        (SELECT cycle_id FROM rounds WHERE id = current_setting('test.round_id')::INT),
        v_next_custom_id, 'rating', NOW(), NOW() + INTERVAL '5 minutes'
    ) RETURNING id INTO v_new_round_id;

    -- Insert first skip - should succeed
    INSERT INTO public.rating_skips (round_id, participant_id)
    VALUES (v_new_round_id, current_setting('test.user3_id')::INT);

    -- Try duplicate - should fail
    BEGIN
        INSERT INTO public.rating_skips (round_id, participant_id)
        VALUES (v_new_round_id, current_setting('test.user3_id')::INT);
        RAISE EXCEPTION 'Duplicate insert should have failed';
    EXCEPTION WHEN unique_violation THEN
        -- Expected
        NULL;
    END;
END $$;

SELECT is(
    true, true,
    'Unique constraint prevents duplicate rating skips per round+participant'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
