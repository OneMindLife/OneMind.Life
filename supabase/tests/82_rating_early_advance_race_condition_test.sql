-- Tests for rating early advance with 6 participants, mixed raters + rating skippers.
--
-- CONTEXT: In production (ASHRIK's Family 3, chat 228), rating early advance
-- intermittently fails when all 6 participants complete rating but the round
-- doesn't auto-advance. Root cause: concurrent transactions inserting
-- grid_rankings rows — each trigger sees only its own transaction's rows.
--
-- Uses per-proposition model: advance when min(ratings per prop) >= threshold.
-- With 6 participants, 1 skip: active_raters=5, threshold=min(10,max(4,1))=4.
-- 3 propositions, each can get max 4 ratings (5 raters - 1 author).
--
-- Related tests:
--   56 - rating self-skip advance (3 participants)
--   57 - rating skips + early advance (4 participants)
--   59 - function source code checks (per-proposition approach)

BEGIN;
SELECT plan(12);

-- =============================================================================
-- SETUP: 6 participants, 100% rating threshold, mixed proposers + skippers
-- Mimics the real scenario: 2 AI agents propose, 1 human proposes,
-- 3 humans skip proposing. During rating: 1 skips rating, 5 rate.
-- =============================================================================

DO $$
DECLARE
    v_session_token UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;  -- "Guardian" agent
    v_p2_id INT;  -- "Harmonizer" agent
    v_p3_id INT;  -- Human who proposed
    v_p4_id INT;  -- Human who skipped proposing
    v_p5_id INT;  -- Human who skipped proposing
    v_p6_id INT;  -- Human who will skip rating
    v_prop_a_id INT;
    v_prop_b_id INT;
    v_prop_c_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum,
        rating_start_mode
    ) VALUES (
        'RatingRaceConditionTest', 'Test', v_session_token,
        'auto', 99,
        100, NULL,   -- 100% threshold (all must be done)
        120, 120,
        3, 2,
        'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'Agent1', 'active', gen_random_uuid()) RETURNING id INTO v_p1_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'Agent2', 'active', gen_random_uuid()) RETURNING id INTO v_p2_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'Human1', 'active', gen_random_uuid()) RETURNING id INTO v_p3_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'Human2', 'active', gen_random_uuid()) RETURNING id INTO v_p4_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'Human3', 'active', gen_random_uuid()) RETURNING id INTO v_p5_id;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'Human4', 'active', gen_random_uuid()) RETURNING id INTO v_p6_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Round already in rating phase (proposing done)
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- 3 propositions from p1, p2, p3 (p4, p5, p6 skipped proposing)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'Agent1 proposal') RETURNING id INTO v_prop_a_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2_id, 'Agent2 proposal') RETURNING id INTO v_prop_b_id;
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3_id, 'Human1 proposal') RETURNING id INTO v_prop_c_id;

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.p1_id', v_p1_id::TEXT, TRUE);
    PERFORM set_config('test.p2_id', v_p2_id::TEXT, TRUE);
    PERFORM set_config('test.p3_id', v_p3_id::TEXT, TRUE);
    PERFORM set_config('test.p4_id', v_p4_id::TEXT, TRUE);
    PERFORM set_config('test.p5_id', v_p5_id::TEXT, TRUE);
    PERFORM set_config('test.p6_id', v_p6_id::TEXT, TRUE);
    PERFORM set_config('test.prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.prop_c_id', v_prop_c_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST 1: Initial state — round in rating phase, not completed
-- =============================================================================

SELECT is(
    (SELECT phase FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'rating',
    'Initial: round in rating phase'
);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'Initial: round not completed'
);

-- =============================================================================
-- TEST 3: p6 skips rating (the "Pixel 7" scenario)
-- 1 done out of 6 — should NOT advance
-- =============================================================================

INSERT INTO public.rating_skips (round_id, participant_id)
VALUES (current_setting('test.round_id')::INT, current_setting('test.p6_id')::INT);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 1 rating skip (1/6 done): NOT completed'
);

-- =============================================================================
-- TEST 4: p4 rates all propositions (none are their own)
-- p4 skipped proposing so they rate all 3 props. 2 done out of 6.
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_a_id')::INT, current_setting('test.p4_id')::INT, current_setting('test.round_id')::INT, 80),
    (current_setting('test.prop_b_id')::INT, current_setting('test.p4_id')::INT, current_setting('test.round_id')::INT, 50),
    (current_setting('test.prop_c_id')::INT, current_setting('test.p4_id')::INT, current_setting('test.round_id')::INT, 30);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 1 skip + 1 rater (2/6 done): NOT completed'
);

-- =============================================================================
-- TEST 5: p5 rates all propositions (none are their own)
-- 3 done out of 6.
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_a_id')::INT, current_setting('test.p5_id')::INT, current_setting('test.round_id')::INT, 60),
    (current_setting('test.prop_b_id')::INT, current_setting('test.p5_id')::INT, current_setting('test.round_id')::INT, 40),
    (current_setting('test.prop_c_id')::INT, current_setting('test.p5_id')::INT, current_setting('test.round_id')::INT, 90);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 1 skip + 2 raters (3/6 done): NOT completed'
);

-- =============================================================================
-- TEST 6: p1 (Agent1) rates the other 2 props (skips own prop_a)
-- 4 done out of 6.
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_b_id')::INT, current_setting('test.p1_id')::INT, current_setting('test.round_id')::INT, 20),
    (current_setting('test.prop_c_id')::INT, current_setting('test.p1_id')::INT, current_setting('test.round_id')::INT, 70);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 1 skip + 3 raters (4/6 done): NOT completed'
);

-- =============================================================================
-- TEST 7: p2 (Agent2) rates the other 2 props (skips own prop_b)
-- 5 done out of 6.
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_a_id')::INT, current_setting('test.p2_id')::INT, current_setting('test.round_id')::INT, 40),
    (current_setting('test.prop_c_id')::INT, current_setting('test.p2_id')::INT, current_setting('test.round_id')::INT, 60);

SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 1 skip + 4 raters (5/6 done): NOT completed'
);

-- =============================================================================
-- TEST 8-10: p3 (Human1) rates the other 2 props (skips own prop_c)
-- 6 done out of 6 — this MUST trigger early advance.
--
-- NOTE: In production, this is the step that intermittently fails when p2
-- and p3 submit ratings in concurrent transactions. The trigger on p3's
-- insert doesn't see p2's uncommitted rows, counts only 5/6 done, and
-- doesn't advance. p2's trigger also counts 5/6 for the same reason.
-- In this sequential test, p2's rows are already visible, so it works.
-- =============================================================================

INSERT INTO public.grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.prop_a_id')::INT, current_setting('test.p3_id')::INT, current_setting('test.round_id')::INT, 50),
    (current_setting('test.prop_b_id')::INT, current_setting('test.p3_id')::INT, current_setting('test.round_id')::INT, 90);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'After 1 skip + 5 raters (6/6 done): COMPLETED via early advance'
);

SELECT is(
    (SELECT winning_proposition_id IS NOT NULL FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    true,
    'Winner was calculated after early advance'
);

-- Verify timer gives sufficient duration (regression from test 79)
SELECT ok(
    (SELECT EXTRACT(EPOCH FROM (phase_ends_at - phase_started_at)) >= 120
     FROM public.rounds WHERE id = current_setting('test.round_id')::INT),
    'Timer gives at least rating_duration_seconds after early advance'
);

-- =============================================================================
-- TEST 11-12: Verify per-proposition logic matches expected values
-- =============================================================================

SELECT is(
    (SELECT COUNT(*) FROM public.participants
     WHERE chat_id = current_setting('test.chat_id')::INT AND status = 'active'),
    6::bigint,
    'Sanity: 6 active participants'
);

-- Verify min ratings per proposition = 4 (the threshold for 5 active raters)
-- prop_a: rated by p2,p3,p4,p5 = 4. prop_b: rated by p1,p3,p4,p5 = 4. prop_c: rated by p1,p2,p4,p5 = 4.
SELECT is(
    (SELECT MIN(cnt)::bigint FROM (
        SELECT p.id, (
            SELECT COUNT(*) FROM grid_rankings gr
            WHERE gr.proposition_id = p.id AND gr.round_id = current_setting('test.round_id')::INT
        ) AS cnt
        FROM propositions p
        WHERE p.round_id = current_setting('test.round_id')::INT
    ) sub),
    4::bigint,
    'Min ratings per proposition = 4 (threshold met for 5 active raters)'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
