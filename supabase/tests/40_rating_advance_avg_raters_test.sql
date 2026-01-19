-- Tests for rating auto-advance using AVERAGE RATERS PER PROPOSITION
-- (not unique participants who have rated)
--
-- BUG: Current behavior advances when X unique participants have rated anything
-- EXPECTED: Should advance when average raters per proposition >= threshold
--
-- Example with threshold=2:
--   - OLD: 2 people rated (even if they only rated 1 prop each) → advance
--   - NEW: Average of 2 raters per proposition required → advance only when coverage is adequate
BEGIN;
SELECT plan(9);

-- =============================================================================
-- SETUP: Create test chat with rating_threshold_count = 2
-- Using only count-based threshold (percent = NULL) to isolate the behavior
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
    -- Create auto-mode chat with rating_threshold_count = 2
    -- This should mean: advance when average raters per proposition >= 2
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,  -- Only count-based
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum
    ) VALUES (
        'AvgRatersTest', 'Test', v_session_token,
        'auto', 99,  -- High threshold to prevent auto-start
        NULL, 2,     -- Average of 2 raters per proposition required
        300, 300,
        3, 2
    ) RETURNING id INTO v_chat_id;

    -- Add 3 participants
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User1', 'active', gen_random_uuid()) RETURNING id INTO v_user1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User2', 'active', gen_random_uuid()) RETURNING id INTO v_user2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'User3', 'active', gen_random_uuid()) RETURNING id INTO v_user3_id;

    -- Create cycle and round in RATING phase (skip proposing for this test)
    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Create 3 propositions (one from each user)
    -- User1's prop (can be rated by User2, User3)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user1_id, 'Proposition A from User1') RETURNING id INTO v_prop_a_id;
    -- User2's prop (can be rated by User1, User3)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_id, 'Proposition B from User2') RETURNING id INTO v_prop_b_id;
    -- User3's prop (can be rated by User1, User2)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user3_id, 'Proposition C from User3') RETURNING id INTO v_prop_c_id;

    -- Store IDs for tests
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
-- TEST 1: Initial state - rating phase, no ratings yet
-- =============================================================================

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'rating',
    'Initial: Round should be in rating phase'
);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'Initial: Round should NOT be completed yet'
);

-- =============================================================================
-- TEST 2: User1 rates Prop B only (1 unique rater, avg = 1/3 per prop)
-- Should NOT advance
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (
    current_setting('test.prop_b_id')::INT,
    current_setting('test.user1_id')::INT,
    current_setting('test.round_id')::INT,
    80.0
);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After User1 rates 1 prop: NOT completed (avg = 0.33 raters/prop)'
);

-- =============================================================================
-- TEST 3: User2 rates Prop A only (2 unique raters, avg = 2/3 per prop)
-- OLD BUG: Would advance because 2 unique raters >= threshold of 2
-- NEW: Should NOT advance because avg = 0.67 < 2
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (
    current_setting('test.prop_a_id')::INT,
    current_setting('test.user2_id')::INT,
    current_setting('test.round_id')::INT,
    70.0
);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'BUG TEST: 2 unique raters but avg=0.67/prop - should NOT be completed yet'
);

-- =============================================================================
-- TEST 4: User1 also rates Prop C (still 2 unique raters, avg = 1 per prop)
-- Should NOT advance
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (
    current_setting('test.prop_c_id')::INT,
    current_setting('test.user1_id')::INT,
    current_setting('test.round_id')::INT,
    60.0
);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After User1 rates 2 props: NOT completed (avg = 1 rater/prop)'
);

-- =============================================================================
-- TEST 5: User2 also rates Prop C (still 2 unique raters, avg = 1.33 per prop)
-- Prop A: 1 rater, Prop B: 1 rater, Prop C: 2 raters → avg = 1.33
-- Should NOT advance
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (
    current_setting('test.prop_c_id')::INT,
    current_setting('test.user2_id')::INT,
    current_setting('test.round_id')::INT,
    50.0
);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 4 total ratings: NOT completed (avg = 1.33 raters/prop)'
);

-- =============================================================================
-- TEST 6: User3 rates Prop A (3 unique raters, avg = 1.67 per prop)
-- Prop A: 2 raters, Prop B: 1 rater, Prop C: 2 raters → avg = 1.67
-- Should NOT advance
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (
    current_setting('test.prop_a_id')::INT,
    current_setting('test.user3_id')::INT,
    current_setting('test.round_id')::INT,
    40.0
);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 5 total ratings: NOT completed (avg = 1.67 raters/prop)'
);

-- =============================================================================
-- TEST 7: User3 rates Prop B (3 unique raters, avg = 2 per prop)
-- Prop A: 2 raters, Prop B: 2 raters, Prop C: 2 raters → avg = 2.0
-- NOW should advance (avg >= threshold of 2)
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (
    current_setting('test.prop_b_id')::INT,
    current_setting('test.user3_id')::INT,
    current_setting('test.round_id')::INT,
    30.0
);

SELECT is(
    (SELECT r.completed_at IS NOT NULL FROM public.rounds r
     WHERE r.id = current_setting('test.round_id')::INT),
    true,
    'After 6 ratings (avg = 2.0 raters/prop): round should be COMPLETED'
);

-- =============================================================================
-- TEST 8: Verify winner was calculated
-- =============================================================================

SELECT is(
    (SELECT r.winning_proposition_id IS NOT NULL FROM public.rounds r
     WHERE r.id = current_setting('test.round_id')::INT),
    true,
    'Round should have a winning proposition'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
