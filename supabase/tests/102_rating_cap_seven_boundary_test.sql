-- =============================================================================
-- Test: rating early-advance cap at 7
-- =============================================================================
-- The threshold formula is:
--     threshold = LEAST(7, GREATEST(active_raters - 1, 1))
--
-- Behavior expected per active-raters:
--     1 rater  → threshold = 1   (no cap)
--     2 raters → threshold = 1
--     3 raters → threshold = 2
--     ...
--     7 raters → threshold = 6   (one below cap; cap inactive)
--     8 raters → threshold = 7   (cap kicks in for the first time)
--    10 raters → threshold = 7   (cap stays)
--    15 raters → threshold = 7   (cap stays, large group)
--
-- These scenarios specifically exercise the boundary where the cap takes
-- over from active_raters - 1. Smaller-N cases (2, 3, 5) are already
-- covered by 85_per_proposition_early_advance_test.sql; this file fills
-- the gap on N=7,8,10 and a skips-into-cap case so future changes to the
-- cap value (or the formula) trip a clear, focused failure.
-- =============================================================================

BEGIN;
SELECT plan(9);

-- =============================================================================
-- Helper: build N participants + N propositions in a fresh rating round.
-- Returns the round_id via test config keys ('test.<scenario>_round_id',
-- 'test.<scenario>_p1_id'..'test.<scenario>_pN_id', and prop ids keyed
-- the same way). Caller picks the scenario prefix.
-- =============================================================================

CREATE OR REPLACE FUNCTION pg_temp.setup_round(
    p_scenario TEXT,
    p_chat_name TEXT,
    p_n_participants INT
) RETURNS VOID AS $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p_id INT;
    v_prop_id INT;
    i INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        p_chat_name, 'Q', gen_random_uuid(),
        'auto', 99,
        100, NULL, 300, 300, 3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id)
        RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (
        cycle_id, custom_id, phase, phase_started_at, phase_ends_at
    ) VALUES (
        v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes'
    ) RETURNING id INTO v_round_id;

    PERFORM set_config('test.' || p_scenario || '_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.' || p_scenario || '_round_id', v_round_id::TEXT, TRUE);

    FOR i IN 1..p_n_participants LOOP
        INSERT INTO public.participants (
            chat_id, display_name, status, session_token
        ) VALUES (
            v_chat_id, 'P' || i, 'active', gen_random_uuid()
        ) RETURNING id INTO v_p_id;
        PERFORM set_config('test.' || p_scenario || '_p' || i || '_id',
                           v_p_id::TEXT, TRUE);

        INSERT INTO public.propositions (round_id, participant_id, content)
        VALUES (v_round_id, v_p_id, 'P' || i || ' idea')
        RETURNING id INTO v_prop_id;
        PERFORM set_config('test.' || p_scenario || '_prop' || i || '_id',
                           v_prop_id::TEXT, TRUE);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Helper: rater P_i rates every non-self proposition in the scenario.
-- Inserts (n-1) grid_rankings rows in a single statement so the early-
-- advance trigger fires once per call.
CREATE OR REPLACE FUNCTION pg_temp.rate_all_non_self(
    p_scenario TEXT,
    p_rater_idx INT,
    p_n INT
) RETURNS VOID AS $$
DECLARE
    v_round_id INT := current_setting('test.' || p_scenario || '_round_id')::INT;
    v_rater_id INT := current_setting('test.' || p_scenario || '_p' || p_rater_idx || '_id')::INT;
    j INT;
BEGIN
    FOR j IN 1..p_n LOOP
        IF j = p_rater_idx THEN CONTINUE; END IF;
        INSERT INTO public.grid_rankings (
            round_id, participant_id, proposition_id, grid_position
        ) VALUES (
            v_round_id, v_rater_id,
            current_setting('test.' || p_scenario || '_prop' || j || '_id')::INT,
            50  -- grid_position is irrelevant to the trigger
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- SCENARIO G: 7 raters — threshold = 6 (cap NOT active)
-- 6 raters rating all non-self covers 6 of every prop except their own
-- author. After 6 raters, every prop authored by those 6 has only 5 ratings
-- (peers minus self), so min=5 < 6.
-- The 7th rater closes it: each prop gets one more rater. min=6 = threshold.
-- =============================================================================

SELECT pg_temp.setup_round('g', 'CapBoundary 7 raters', 7);

-- Insert 6 raters' ratings. After this:
--   prop authored by P_k (k in 1..6): rated by {P1..P6} \ {P_k} = 5 raters
--   prop authored by P7              : rated by {P1..P6}        = 6 raters
--   min = 5
SELECT pg_temp.rate_all_non_self('g', 1, 7);
SELECT pg_temp.rate_all_non_self('g', 2, 7);
SELECT pg_temp.rate_all_non_self('g', 3, 7);
SELECT pg_temp.rate_all_non_self('g', 4, 7);
SELECT pg_temp.rate_all_non_self('g', 5, 7);
SELECT pg_temp.rate_all_non_self('g', 6, 7);

-- 1: round still open at min=5 < threshold=6
SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds
     WHERE id = current_setting('test.g_round_id')::INT),
    true,
    'G (7 raters, threshold=6): min=5 keeps round open'
);

-- 7th rater closes it. Now every prop has 6 raters.
SELECT pg_temp.rate_all_non_self('g', 7, 7);

-- 2: round completed at min=6 = threshold
SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds
     WHERE id = current_setting('test.g_round_id')::INT),
    true,
    'G (7 raters, threshold=6): min=6 advances the round'
);

-- =============================================================================
-- SCENARIO H: 8 raters — threshold = 7 (cap kicks in for the first time)
-- After 7 raters' rounds, every prop except those authored by the 7 raters
-- has 7 ratings; the 7 self-authored props have 6 each. min=6 < 7.
-- The 8th rater closes it.
-- =============================================================================

SELECT pg_temp.setup_round('h', 'CapBoundary 8 raters', 8);

SELECT pg_temp.rate_all_non_self('h', 1, 8);
SELECT pg_temp.rate_all_non_self('h', 2, 8);
SELECT pg_temp.rate_all_non_self('h', 3, 8);
SELECT pg_temp.rate_all_non_self('h', 4, 8);
SELECT pg_temp.rate_all_non_self('h', 5, 8);
SELECT pg_temp.rate_all_non_self('h', 6, 8);
SELECT pg_temp.rate_all_non_self('h', 7, 8);

-- 3: still open at min=6 < cap=7
SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds
     WHERE id = current_setting('test.h_round_id')::INT),
    true,
    'H (8 raters, threshold=7): min=6 keeps round open (cap is exactly 7)'
);

SELECT pg_temp.rate_all_non_self('h', 8, 8);

-- 4: completed once the 8th rater pushes min to 7
SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds
     WHERE id = current_setting('test.h_round_id')::INT),
    true,
    'H (8 raters, threshold=7): min=7 advances at the cap'
);

-- =============================================================================
-- SCENARIO I: 10 raters — threshold stays at 7 even though active-1 = 9
-- After 7 raters rate everything, each non-rater prop (3 of them) has 7
-- ratings; the 7 rater-authored props have 6 each. min=6 < 7. NOT advanced.
-- The 8th rater pushes min to 7 → ADVANCE, even though more raters could
-- still go (proves the cap stops further work).
-- =============================================================================

SELECT pg_temp.setup_round('i', 'CapBoundary 10 raters', 10);

SELECT pg_temp.rate_all_non_self('i', 1, 10);
SELECT pg_temp.rate_all_non_self('i', 2, 10);
SELECT pg_temp.rate_all_non_self('i', 3, 10);
SELECT pg_temp.rate_all_non_self('i', 4, 10);
SELECT pg_temp.rate_all_non_self('i', 5, 10);
SELECT pg_temp.rate_all_non_self('i', 6, 10);
SELECT pg_temp.rate_all_non_self('i', 7, 10);

-- 5: still open — min=6 across rater-authored props
SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds
     WHERE id = current_setting('test.i_round_id')::INT),
    true,
    'I (10 raters, threshold=7): min=6 keeps round open'
);

SELECT pg_temp.rate_all_non_self('i', 8, 10);

-- 6: completed — even though 9 others could still rate, the cap fires advance
SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds
     WHERE id = current_setting('test.i_round_id')::INT),
    true,
    'I (10 raters, threshold=7): cap fires advance after 8th rater'
);

-- =============================================================================
-- SCENARIO J: 10 raters with 2 skips → 8 active → threshold = 7 (still cap)
-- Confirms skips deflate the active count and the cap remains the binding
-- constraint when the deflated active count is still ≥ 8.
-- =============================================================================

SELECT pg_temp.setup_round('j', 'CapBoundary 10 raters with 2 skips', 10);

-- P9 and P10 skip rating. active_raters = 10 - 2 = 8 → threshold = 7.
INSERT INTO public.rating_skips (round_id, participant_id) VALUES
  (current_setting('test.j_round_id')::INT,
   current_setting('test.j_p9_id')::INT),
  (current_setting('test.j_round_id')::INT,
   current_setting('test.j_p10_id')::INT);

-- 7 active raters do their thing. With 10 props (P9 and P10 still authored,
-- since proposing already ran) and 7 raters {P1..P7}, the prop authored by
-- P_k (k in 1..7) has 6 ratings (peers minus self); P8/P9/P10 props have 7.
-- min=6 < 7.
SELECT pg_temp.rate_all_non_self('j', 1, 10);
SELECT pg_temp.rate_all_non_self('j', 2, 10);
SELECT pg_temp.rate_all_non_self('j', 3, 10);
SELECT pg_temp.rate_all_non_self('j', 4, 10);
SELECT pg_temp.rate_all_non_self('j', 5, 10);
SELECT pg_temp.rate_all_non_self('j', 6, 10);
SELECT pg_temp.rate_all_non_self('j', 7, 10);

-- 7: still open at min=6 even with 7 active raters all done
SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds
     WHERE id = current_setting('test.j_round_id')::INT),
    true,
    'J (10 raters, 2 skipped, threshold=7): min=6 keeps round open'
);

-- P8 (the last active rater) closes it.
SELECT pg_temp.rate_all_non_self('j', 8, 10);

-- 8: completed at min=7
SELECT is(
    (SELECT completed_at IS NOT NULL FROM public.rounds
     WHERE id = current_setting('test.j_round_id')::INT),
    true,
    'J (10 raters, 2 skipped, threshold=7): min=7 advances'
);

-- =============================================================================
-- SCENARIO K: 8 funded participants, P8 left with a preserved rating_skip.
-- Regression guard for the active-only JOIN added in 20260430120000
-- (soft-delete leave preserves rating_skips). Without that JOIN the
-- preserved skip would inflate skip_count and DROP active_raters from 8 to
-- 7, dropping the threshold from 7 to 6 — so the round would advance early
-- even though 1 fewer person actually voted.
--
-- Setup pins funded count via round_funding so v_total_participants stays
-- at 8 even after P8 flips to status='left' (the funded path is what the
-- trigger takes whenever any funding row exists).
-- =============================================================================

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p_id INT;
    v_prop_id INT;
    i INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode, auto_start_participant_count,
        rating_threshold_percent, rating_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum, rating_start_mode
    ) VALUES (
        'CapBoundary 8 funded with leaver-skip', 'Q', gen_random_uuid(),
        'auto', 99, 100, NULL, 300, 300, 3, 2, 'auto'
    ) RETURNING id INTO v_chat_id;
    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id)
        RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (
        cycle_id, custom_id, phase, phase_started_at, phase_ends_at
    ) VALUES (
        v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes'
    ) RETURNING id INTO v_round_id;

    PERFORM set_config('test.k_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.k_round_id', v_round_id::TEXT, TRUE);

    -- The auto-start trigger funds each new participant on join, so
    -- round_funding is populated automatically as long as a round is
    -- already open in 'rating' phase (it is — we created one above).
    FOR i IN 1..8 LOOP
        INSERT INTO public.participants (chat_id, display_name, status, session_token)
        VALUES (v_chat_id, 'P' || i, 'active', gen_random_uuid())
        RETURNING id INTO v_p_id;
        PERFORM set_config('test.k_p' || i || '_id', v_p_id::TEXT, TRUE);

        INSERT INTO public.propositions (round_id, participant_id, content)
        VALUES (v_round_id, v_p_id, 'P' || i || ' idea')
        RETURNING id INTO v_prop_id;
        PERFORM set_config('test.k_prop' || i || '_id', v_prop_id::TEXT, TRUE);
    END LOOP;
END $$;

-- P8 skips rating, then leaves. The skip row is preserved (soft-delete).
INSERT INTO public.rating_skips (round_id, participant_id) VALUES (
    current_setting('test.k_round_id')::INT,
    current_setting('test.k_p8_id')::INT
);
UPDATE public.participants SET status = 'left'
WHERE id = current_setting('test.k_p8_id')::INT;

-- All 7 remaining active raters rate every non-self proposition.
-- After this: prop_k for k in 1..7 has 6 ratings each (peers minus self);
-- prop_8 (leaver's) has 7 ratings. min = 6.
SELECT pg_temp.rate_all_non_self('k', 1, 8);
SELECT pg_temp.rate_all_non_self('k', 2, 8);
SELECT pg_temp.rate_all_non_self('k', 3, 8);
SELECT pg_temp.rate_all_non_self('k', 4, 8);
SELECT pg_temp.rate_all_non_self('k', 5, 8);
SELECT pg_temp.rate_all_non_self('k', 6, 8);
SELECT pg_temp.rate_all_non_self('k', 7, 8);

-- 9: with the active-only JOIN, threshold = 7 and min=6 keeps the round
--    open (timer will eventually advance it). If a regression dropped the
--    JOIN, skip_count would jump to 1, active_raters to 7, threshold to 6,
--    and min=6 would fire early-advance — failing this assertion.
SELECT is(
    (SELECT completed_at IS NULL FROM public.rounds
     WHERE id = current_setting('test.k_round_id')::INT),
    true,
    'K (8 funded, P8 left with skip): preserved leaver-skip does NOT inflate skip_count and trigger early advance'
);

-- =============================================================================
-- Cleanup (rolled back anyway, but explicit for clarity)
-- =============================================================================
DELETE FROM public.chats WHERE id = current_setting('test.g_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.h_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.i_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.j_chat_id')::INT;
DELETE FROM public.chats WHERE id = current_setting('test.k_chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
