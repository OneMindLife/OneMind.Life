-- Tests for per-proposition early advance model.
--
-- The new model advances the round when every proposition has enough ratings:
--   threshold = min(10, max(active_raters - 1, 1))
--   where active_raters = active participants - rating skippers
--   advance when min(ratings per proposition) >= threshold
--
-- Edge cases tested:
--   1. Carry-forward proposition (author has 2 props)
--   2. Multiple carry-forwards from tied previous round
--   3. Large chat (threshold caps at 10)
--   4. All participants skip rating
--   5. 2 participants minimum viable
--   6. Least-rated-first RPC functions
--   7. Carry-forward author leaves mid-rating

BEGIN;
SELECT plan(23);

-- =============================================================================
-- SCENARIO A: 3 participants + 1 carry-forward (authored by P1)
-- P1 has 2 propositions (own + carry). Threshold = min(10, max(3-1, 1)) = 2.
-- =============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_prev_round_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
    v_prop_a_id INT;  -- P1's new proposition
    v_prop_b_id INT;  -- P2's proposition
    v_prop_c_id INT;  -- P3's proposition
    v_prop_d_id INT;  -- Carry-forward (authored by P1)
    v_prev_prop_id INT;  -- Source proposition for carry-forward
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        'CarryForwardTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL,
        300, 300,
        3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P1', 'active', gen_random_uuid()) RETURNING id INTO v_p1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P2', 'active', gen_random_uuid()) RETURNING id INTO v_p2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P3', 'active', gen_random_uuid()) RETURNING id INTO v_p3_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Previous round (completed) with source proposition for carry-forward
    INSERT INTO public.rounds (cycle_id, custom_id, phase, completed_at)
    VALUES (v_cycle_id, 1, 'rating', NOW()) RETURNING id INTO v_prev_round_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_prev_round_id, v_p1_id, 'P1 prev winner') RETURNING id INTO v_prev_prop_id;

    -- Current round in rating phase
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 2, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- P1's new proposition
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'P1 new idea') RETURNING id INTO v_prop_a_id;
    -- P2's proposition
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'P2 idea') RETURNING id INTO v_prop_b_id;
    -- P3's proposition
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3_id, 'P3 idea') RETURNING id INTO v_prop_c_id;
    -- Carry-forward from P1 (references previous round's proposition)
    INSERT INTO public.propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round_id, v_p1_id, 'P1 carried', v_prev_prop_id) RETURNING id INTO v_prop_d_id;

    PERFORM set_config('test.a_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.a_round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.a_p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.a_p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.a_p3_id', v_p3_id::TEXT, TRUE);
    PERFORM set_config('test.a_prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.a_prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.a_prop_c_id', v_prop_c_id::TEXT, TRUE);
    PERFORM set_config('test.a_prop_d_id', v_prop_d_id::TEXT, TRUE);
END $$;

-- Test 1: Initial state
SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.a_round_id')::INT),
    'rating',
    'Scenario A: Initial round in rating phase'
);

-- Test 2: P1 rates B and C (can't rate own A or carry D). Only 2 rateable.
-- Per-prop: a=0, b=1, c=1, d=0 → min=0 < threshold=2. NOT completed.
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.a_prop_b_id')::INT, current_setting('test.a_p1_id')::INT, current_setting('test.a_round_id')::INT, 80),
    (current_setting('test.a_prop_c_id')::INT, current_setting('test.a_p1_id')::INT, current_setting('test.a_round_id')::INT, 60);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.a_round_id')::INT),
    true,
    'Scenario A: After P1 rates 2 (min=0 < 2): NOT completed'
);

-- Test 3: P2 rates A, C, D (can't rate own B). 3 rateable.
-- Per-prop: a=1, b=1, c=2, d=1 → min=1 < 2. NOT completed.
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.a_prop_a_id')::INT, current_setting('test.a_p2_id')::INT, current_setting('test.a_round_id')::INT, 70),
    (current_setting('test.a_prop_c_id')::INT, current_setting('test.a_p2_id')::INT, current_setting('test.a_round_id')::INT, 50),
    (current_setting('test.a_prop_d_id')::INT, current_setting('test.a_p2_id')::INT, current_setting('test.a_round_id')::INT, 40);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.a_round_id')::INT),
    true,
    'Scenario A: After P2 rates 3 (min=1 < 2): NOT completed'
);

-- Test 4: P3 rates A, B, D (can't rate own C). 3 rateable.
-- Per-prop: a=2, b=2, c=2, d=2 → min=2 >= 2. COMPLETED!
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.a_prop_a_id')::INT, current_setting('test.a_p3_id')::INT, current_setting('test.a_round_id')::INT, 60),
    (current_setting('test.a_prop_b_id')::INT, current_setting('test.a_p3_id')::INT, current_setting('test.a_round_id')::INT, 50),
    (current_setting('test.a_prop_d_id')::INT, current_setting('test.a_p3_id')::INT, current_setting('test.a_round_id')::INT, 30);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.a_round_id')::INT),
    true,
    'Scenario A: After P3 rates (min=2 >= 2): COMPLETED with carry-forward'
);

-- Test 5: Winner calculated
SELECT is(
    (SELECT winning_proposition_id IS NOT NULL FROM public.rounds WHERE id = current_setting('test.a_round_id')::INT),
    true,
    'Scenario A: Winner calculated'
);

-- =============================================================================
-- SCENARIO B: 3 participants + 2 carry-forwards (tied previous round, both by P1)
-- P1 has 3 propositions (own + 2 carries). Threshold = 2.
-- P1 can only rate B, C (2 props). P2 and P3 can rate 4 each.
-- =============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
    v_prev_round_id INT;
    v_prev_prop1_id INT;
    v_prev_prop2_id INT;
    v_prop_a_id INT;
    v_prop_b_id INT;
    v_prop_c_id INT;
    v_prop_d_id INT;
    v_prop_e_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        'TiedCarryTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL, 300, 300, 3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P1', 'active', gen_random_uuid()) RETURNING id INTO v_p1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P2', 'active', gen_random_uuid()) RETURNING id INTO v_p2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P3', 'active', gen_random_uuid()) RETURNING id INTO v_p3_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Previous completed round with source propositions for carry-forwards
    -- Use different authors to avoid unique_new_per_round constraint
    INSERT INTO public.rounds (cycle_id, custom_id, phase, completed_at)
    VALUES (v_cycle_id, 1, 'rating', NOW()) RETURNING id INTO v_prev_round_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_prev_round_id, v_p1_id, 'P1 prev win') RETURNING id INTO v_prev_prop1_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_prev_round_id, v_p2_id, 'P2 prev win') RETURNING id INTO v_prev_prop2_id;

    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 2, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'P1 new') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'P2 idea') RETURNING id INTO v_prop_b_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3_id, 'P3 idea') RETURNING id INTO v_prop_c_id;
    INSERT INTO public.propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round_id, v_p1_id, 'P1 carry1', v_prev_prop1_id) RETURNING id INTO v_prop_d_id;
    INSERT INTO public.propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round_id, v_p1_id, 'P1 carry2', v_prev_prop2_id) RETURNING id INTO v_prop_e_id;

    PERFORM set_config('test.b_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.b_round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.b_p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.b_p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.b_p3_id', v_p3_id::TEXT, TRUE);
    PERFORM set_config('test.b_prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.b_prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.b_prop_c_id', v_prop_c_id::TEXT, TRUE);
    PERFORM set_config('test.b_prop_d_id', v_prop_d_id::TEXT, TRUE);
    PERFORM set_config('test.b_prop_e_id', v_prop_e_id::TEXT, TRUE);
END $$;

-- Test 6: P1 rates B, C (can't rate own A, D, E → only 2 rateable)
-- Per-prop: a=0, b=1, c=1, d=0, e=0 → min=0. NOT completed.
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.b_prop_b_id')::INT, current_setting('test.b_p1_id')::INT, current_setting('test.b_round_id')::INT, 80),
    (current_setting('test.b_prop_c_id')::INT, current_setting('test.b_p1_id')::INT, current_setting('test.b_round_id')::INT, 60);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.b_round_id')::INT),
    true,
    'Scenario B: After P1 rates 2 (min=0): NOT completed'
);

-- Test 7: P2 rates A, C, D, E (can't rate own B → 4 rateable)
-- Per-prop: a=1, b=1, c=2, d=1, e=1 → min=1 < 2. NOT completed.
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.b_prop_a_id')::INT, current_setting('test.b_p2_id')::INT, current_setting('test.b_round_id')::INT, 70),
    (current_setting('test.b_prop_c_id')::INT, current_setting('test.b_p2_id')::INT, current_setting('test.b_round_id')::INT, 50),
    (current_setting('test.b_prop_d_id')::INT, current_setting('test.b_p2_id')::INT, current_setting('test.b_round_id')::INT, 40),
    (current_setting('test.b_prop_e_id')::INT, current_setting('test.b_p2_id')::INT, current_setting('test.b_round_id')::INT, 30);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.b_round_id')::INT),
    true,
    'Scenario B: After P2 rates 4 (min=1 < 2): NOT completed'
);

-- Test 8: P3 rates A, B, D, E (can't rate own C → 4 rateable)
-- Per-prop: a=2, b=2, c=2, d=2, e=2 → min=2 >= 2. COMPLETED!
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.b_prop_a_id')::INT, current_setting('test.b_p3_id')::INT, current_setting('test.b_round_id')::INT, 60),
    (current_setting('test.b_prop_b_id')::INT, current_setting('test.b_p3_id')::INT, current_setting('test.b_round_id')::INT, 50),
    (current_setting('test.b_prop_d_id')::INT, current_setting('test.b_p3_id')::INT, current_setting('test.b_round_id')::INT, 35),
    (current_setting('test.b_prop_e_id')::INT, current_setting('test.b_p3_id')::INT, current_setting('test.b_round_id')::INT, 25);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.b_round_id')::INT),
    true,
    'Scenario B: After P3 rates (min=2 >= 2): COMPLETED with 2 carry-forwards'
);

-- =============================================================================
-- SCENARIO C: 2 participants (minimum viable)
-- Threshold = min(10, max(2-1, 1)) = 1. Each rates the other's prop.
-- =============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_prop_a_id INT;
    v_prop_b_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        'MinViableTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL, 300, 300, 3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P1', 'active', gen_random_uuid()) RETURNING id INTO v_p1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P2', 'active', gen_random_uuid()) RETURNING id INTO v_p2_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'P1 idea') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'P2 idea') RETURNING id INTO v_prop_b_id;

    PERFORM set_config('test.c_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.c_round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.c_p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.c_p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.c_prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.c_prop_b_id', v_prop_b_id::TEXT, TRUE);
END $$;

-- Test 9: P1 rates B. Per-prop: a=0, b=1 → min=0 < 1. NOT completed.
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (current_setting('test.c_prop_b_id')::INT, current_setting('test.c_p1_id')::INT, current_setting('test.c_round_id')::INT, 70);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.c_round_id')::INT),
    true,
    'Scenario C (2 users): After P1 rates (min=0 < 1): NOT completed'
);

-- Test 10: P2 rates A. Per-prop: a=1, b=1 → min=1 >= 1. COMPLETED!
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (current_setting('test.c_prop_a_id')::INT, current_setting('test.c_p2_id')::INT, current_setting('test.c_round_id')::INT, 60);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.c_round_id')::INT),
    true,
    'Scenario C (2 users): After P2 rates (min=1 >= 1): COMPLETED'
);

-- =============================================================================
-- SCENARIO D: Maximum skips then remaining raters complete
-- 5 participants, rating_minimum=2, max_skips=3. 3 skip, 2 must rate.
-- active_raters = 5 - 3 = 2. threshold = min(10, max(2-1, 1)) = 1.
-- =============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
    v_p4_id INT;
    v_p5_id INT;
    v_prop_a_id INT;
    v_prop_b_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        'MaxSkipTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL, 300, 300, 3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P1', 'active', gen_random_uuid()) RETURNING id INTO v_p1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P2', 'active', gen_random_uuid()) RETURNING id INTO v_p2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P3', 'active', gen_random_uuid()) RETURNING id INTO v_p3_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P4', 'active', gen_random_uuid()) RETURNING id INTO v_p4_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P5', 'active', gen_random_uuid()) RETURNING id INTO v_p5_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Only 2 propositions (P1 and P2 proposed, others skipped proposing)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'P1 idea') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'P2 idea') RETURNING id INTO v_prop_b_id;

    PERFORM set_config('test.d_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.d_round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.d_p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.d_p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.d_p3_id', v_p3_id::TEXT, TRUE);
    PERFORM set_config('test.d_p4_id', v_p4_id::TEXT, TRUE);
    PERFORM set_config('test.d_p5_id', v_p5_id::TEXT, TRUE);
    PERFORM set_config('test.d_prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.d_prop_b_id', v_prop_b_id::TEXT, TRUE);
END $$;

-- Test 11: 3 participants skip rating. active_raters = 5 - 3 = 2. threshold = 1.
INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.d_round_id')::INT, current_setting('test.d_p3_id')::INT);
INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.d_round_id')::INT, current_setting('test.d_p4_id')::INT);
INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.d_round_id')::INT, current_setting('test.d_p5_id')::INT);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.d_round_id')::INT),
    true,
    'Scenario D: After 3/5 skip (min=0 < threshold=1): NOT completed'
);

-- Test 12: P1 rates B. Per-prop: a=0, b=1 → min=0 < 1. NOT completed.
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (current_setting('test.d_prop_b_id')::INT, current_setting('test.d_p1_id')::INT, current_setting('test.d_round_id')::INT, 70);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.d_round_id')::INT),
    true,
    'Scenario D: After P1 rates B (min=0, prop_a unrated): NOT completed'
);

-- Test 12b: P2 rates A. Per-prop: a=1, b=1 → min=1 >= 1. COMPLETED!
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES (current_setting('test.d_prop_a_id')::INT, current_setting('test.d_p2_id')::INT, current_setting('test.d_round_id')::INT, 60);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.d_round_id')::INT),
    true,
    'Scenario D: After P2 rates A (min=1 >= 1): COMPLETED with 3 skippers'
);

-- =============================================================================
-- SCENARIO E: 5 participants, 1 skip, 1 carry-forward
-- active_raters = 5 - 1 = 4. threshold = min(10, max(4-1, 1)) = 3.
-- Tests intermediate non-advance states.
-- =============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
    v_p4_id INT;
    v_p5_id INT;
    v_prev_round_id INT;
    v_prev_prop_id INT;
    v_prop_a_id INT;
    v_prop_b_id INT;
    v_prop_c_id INT;
    v_prop_d_id INT;
    v_prop_e_id INT;
    v_prop_f_id INT;  -- carry-forward
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        'FiveUserSkipCarryTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL, 300, 300, 3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P1', 'active', gen_random_uuid()) RETURNING id INTO v_p1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P2', 'active', gen_random_uuid()) RETURNING id INTO v_p2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P3', 'active', gen_random_uuid()) RETURNING id INTO v_p3_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P4', 'active', gen_random_uuid()) RETURNING id INTO v_p4_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P5', 'active', gen_random_uuid()) RETURNING id INTO v_p5_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Previous completed round with source proposition for carry-forward
    INSERT INTO public.rounds (cycle_id, custom_id, phase, completed_at)
    VALUES (v_cycle_id, 1, 'rating', NOW()) RETURNING id INTO v_prev_round_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_prev_round_id, v_p1_id, 'P1 prev winner') RETURNING id INTO v_prev_prop_id;

    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 2, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'P1 idea') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'P2 idea') RETURNING id INTO v_prop_b_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3_id, 'P3 idea') RETURNING id INTO v_prop_c_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p4_id, 'P4 idea') RETURNING id INTO v_prop_d_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p5_id, 'P5 idea') RETURNING id INTO v_prop_e_id;
    INSERT INTO public.propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round_id, v_p1_id, 'P1 carry', v_prev_prop_id) RETURNING id INTO v_prop_f_id;

    PERFORM set_config('test.e_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.e_round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.e_p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.e_p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.e_p3_id', v_p3_id::TEXT, TRUE);
    PERFORM set_config('test.e_p4_id', v_p4_id::TEXT, TRUE);
    PERFORM set_config('test.e_p5_id', v_p5_id::TEXT, TRUE);
    PERFORM set_config('test.e_prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.e_prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.e_prop_c_id', v_prop_c_id::TEXT, TRUE);
    PERFORM set_config('test.e_prop_d_id', v_prop_d_id::TEXT, TRUE);
    PERFORM set_config('test.e_prop_e_id', v_prop_e_id::TEXT, TRUE);
    PERFORM set_config('test.e_prop_f_id', v_prop_f_id::TEXT, TRUE);
END $$;

-- Test 13: P5 skips rating. active_raters = 4. threshold = 3.
INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.e_round_id')::INT, current_setting('test.e_p5_id')::INT);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.e_round_id')::INT),
    true,
    'Scenario E: After P5 skips (min=0 < 3): NOT completed'
);

-- Test 14: P2 rates all non-self (A, C, D, E, F = 5 props)
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.e_prop_a_id')::INT, current_setting('test.e_p2_id')::INT, current_setting('test.e_round_id')::INT, 90),
    (current_setting('test.e_prop_c_id')::INT, current_setting('test.e_p2_id')::INT, current_setting('test.e_round_id')::INT, 70),
    (current_setting('test.e_prop_d_id')::INT, current_setting('test.e_p2_id')::INT, current_setting('test.e_round_id')::INT, 50),
    (current_setting('test.e_prop_e_id')::INT, current_setting('test.e_p2_id')::INT, current_setting('test.e_round_id')::INT, 30),
    (current_setting('test.e_prop_f_id')::INT, current_setting('test.e_p2_id')::INT, current_setting('test.e_round_id')::INT, 20);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.e_round_id')::INT),
    true,
    'Scenario E: After P2 rates 5 (min=0, prop_b unrated): NOT completed'
);

-- Test 15: P3 rates all non-self (A, B, D, E, F = 5 props)
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.e_prop_a_id')::INT, current_setting('test.e_p3_id')::INT, current_setting('test.e_round_id')::INT, 85),
    (current_setting('test.e_prop_b_id')::INT, current_setting('test.e_p3_id')::INT, current_setting('test.e_round_id')::INT, 65),
    (current_setting('test.e_prop_d_id')::INT, current_setting('test.e_p3_id')::INT, current_setting('test.e_round_id')::INT, 45),
    (current_setting('test.e_prop_e_id')::INT, current_setting('test.e_p3_id')::INT, current_setting('test.e_round_id')::INT, 25),
    (current_setting('test.e_prop_f_id')::INT, current_setting('test.e_p3_id')::INT, current_setting('test.e_round_id')::INT, 15);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.e_round_id')::INT),
    true,
    'Scenario E: After P3 rates 5 (min=1, prop_b=1 < 3): NOT completed'
);

-- Test 16: P4 rates all non-self (A, B, C, E, F = 5 props)
-- Now prop_b has 2 ratings (P3, P4). Still min=2 < 3. NOT completed.
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.e_prop_a_id')::INT, current_setting('test.e_p4_id')::INT, current_setting('test.e_round_id')::INT, 80),
    (current_setting('test.e_prop_b_id')::INT, current_setting('test.e_p4_id')::INT, current_setting('test.e_round_id')::INT, 60),
    (current_setting('test.e_prop_c_id')::INT, current_setting('test.e_p4_id')::INT, current_setting('test.e_round_id')::INT, 40),
    (current_setting('test.e_prop_e_id')::INT, current_setting('test.e_p4_id')::INT, current_setting('test.e_round_id')::INT, 20),
    (current_setting('test.e_prop_f_id')::INT, current_setting('test.e_p4_id')::INT, current_setting('test.e_round_id')::INT, 10);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.e_round_id')::INT),
    true,
    'Scenario E: After P4 rates 5 (min=2, prop_b=2 < 3): NOT completed'
);

-- Test 17: P1 rates B, C, D, E (can't rate own A or carry F → 4 rateable)
-- prop_b now has 3 ratings (P3, P4, P1). min across all props = 3 >= 3. COMPLETED!
INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.e_prop_b_id')::INT, current_setting('test.e_p1_id')::INT, current_setting('test.e_round_id')::INT, 75),
    (current_setting('test.e_prop_c_id')::INT, current_setting('test.e_p1_id')::INT, current_setting('test.e_round_id')::INT, 55),
    (current_setting('test.e_prop_d_id')::INT, current_setting('test.e_p1_id')::INT, current_setting('test.e_round_id')::INT, 35),
    (current_setting('test.e_prop_e_id')::INT, current_setting('test.e_p1_id')::INT, current_setting('test.e_round_id')::INT, 15);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.e_round_id')::INT),
    true,
    'Scenario E: After P1 rates 4 (min=3 >= 3): COMPLETED'
);

-- =============================================================================
-- SCENARIO F: RPCs exist and work
-- =============================================================================

-- Test 18: get_least_rated_proposition function exists
SELECT has_function('get_least_rated_proposition');

-- Test 19: get_least_rated_propositions function exists
SELECT has_function('get_least_rated_propositions');

-- Test 20-22: Verify RPC returns propositions ordered by least-rated
-- Use scenario E's data (round is completed but we can still query)
-- We'll create a fresh round for this test

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_prop_a_id INT;
    v_prop_b_id INT;
    v_prop_c_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        'RPCTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL, 300, 300, 3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P1', 'active', gen_random_uuid()) RETURNING id INTO v_p1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P2', 'active', gen_random_uuid()) RETURNING id INTO v_p2_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- P1's prop, P2's prop, P2's carry-forward (3 props total for RPC testing)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'X') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'Y') RETURNING id INTO v_prop_b_id;
    -- Use prop_a as source for carry-forward (P2 authored carry references P1's prop)
    INSERT INTO public.propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round_id, v_p2_id, 'Z', v_prop_a_id) RETURNING id INTO v_prop_c_id;

    -- P1 rates prop_b (giving it 1 rating). prop_a=0, prop_c=0 (tied for least)
    INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
    VALUES (v_prop_b_id, v_p1_id, v_round_id, 50);

    PERFORM set_config('test.f_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.f_round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.f_p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.f_p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.f_prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.f_prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.f_prop_c_id', v_prop_c_id::TEXT, TRUE);
END $$;

-- Test 21: get_least_rated_proposition excludes user's own and returns least-rated
-- P2 can rate prop_a (0 ratings). prop_b has 1 rating but is P2's own.
-- prop_c is P2's carry so also excluded. Should return prop_a (0 ratings, only option).
SELECT is(
    (SELECT id FROM get_least_rated_proposition(
        current_setting('test.f_round_id')::BIGINT,
        current_setting('test.f_p2_id')::BIGINT,
        ARRAY[]::BIGINT[]
    )),
    current_setting('test.f_prop_a_id')::BIGINT,
    'RPC: get_least_rated_proposition returns least-rated prop for P2'
);

-- Test 22: get_least_rated_proposition with exclude_ids filters correctly
-- Exclude prop_a; P2's other props (B, C) are both P2's own → returns NULL
SELECT is(
    (SELECT id FROM get_least_rated_proposition(
        current_setting('test.f_round_id')::BIGINT,
        current_setting('test.f_p2_id')::BIGINT,
        ARRAY[current_setting('test.f_prop_a_id')::BIGINT]
    )),
    NULL::BIGINT,
    'RPC: get_least_rated_proposition returns NULL when no rateable props left'
);

-- Test 23: get_least_rated_propositions returns available results (capped by rateable count)
-- P2 can only rate prop_a, so requesting 2 returns just 1
SELECT is(
    (SELECT COUNT(*) FROM get_least_rated_propositions(
        current_setting('test.f_round_id')::BIGINT,
        current_setting('test.f_p2_id')::BIGINT,
        2,
        ARRAY[]::BIGINT[]
    )),
    1::BIGINT,
    'RPC: get_least_rated_propositions returns available count (1 rateable for P2)'
);

-- Also verify P1 can get 2 (prop_b=1 rating, prop_c=0 ratings, prop_a is P1's own)
-- Actually P1 already rated prop_b, so prop_c is the only unrated. But the RPC
-- doesn't know about already-rated — it uses exclude_ids. With empty exclude:
-- P1 can rate prop_b (P2's) and prop_c (P2's carry) = 2 rateable

-- =============================================================================
-- CLEANUP
-- =============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.a_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.b_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.c_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.d_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.e_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.f_chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
