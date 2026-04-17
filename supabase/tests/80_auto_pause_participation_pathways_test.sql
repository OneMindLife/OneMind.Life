-- Tests for auto-pause across all human participation pathways.
-- The auto-pause fires in on_round_winner_set() and checks whether any human
-- submitted a NEW proposition OR explicitly skipped proposing (round_skips).
-- Rating activity (grid_rankings, rating_skips) is NOT checked.

BEGIN;
SELECT plan(10);

-- =============================================================================
-- SHARED SETUP: Create host user
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (id) VALUES (v_host_id);
    PERFORM set_config('test.host_id', v_host_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- HELPER: Create a chat with agents, one human, one agent, a round in rating
-- phase, and an agent proposition. Returns chat_id, round_id, human participant
-- id, agent participant id, and the agent proposition id.
-- =============================================================================
-- (Each test creates its own chat via inline DO blocks for isolation)

-- =============================================================================
-- SCENARIO 1: Human proposes + skips rating → should NOT auto-pause
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT; v_human_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S1: Propose+SkipRating', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Human proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_human_id, 'Human idea') RETURNING id INTO v_human_prop_id;

    -- Agent proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Human skips rating
    INSERT INTO public.rating_skips (round_id, participant_id)
    VALUES (v_round_id, v_human_id);

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s1_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s1_chat_id')::INT),
    FALSE,
    'S1: Human proposed + skipped rating → NOT paused'
);

-- =============================================================================
-- SCENARIO 2: Human skips proposing + rates → should NOT auto-pause
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S2: SkipPropose+Rate', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Agent proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Human skips proposing
    INSERT INTO public.round_skips (round_id, participant_id)
    VALUES (v_round_id, v_human_id);

    -- Human rates
    INSERT INTO public.grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES (v_round_id, v_human_id, v_agent_prop_id, 75);

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s2_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s2_chat_id')::INT),
    FALSE,
    'S2: Human skipped proposing + rated → NOT paused'
);

-- =============================================================================
-- SCENARIO 3: Human proposes + rates (does both) → should NOT auto-pause
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT; v_human_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S3: Propose+Rate', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Human proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_human_id, 'Human idea') RETURNING id INTO v_human_prop_id;

    -- Agent proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Human rates agent's proposition
    INSERT INTO public.grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES (v_round_id, v_human_id, v_agent_prop_id, 80);

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s3_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s3_chat_id')::INT),
    FALSE,
    'S3: Human proposed + rated → NOT paused'
);

-- =============================================================================
-- SCENARIO 4: Human proposes, does NOT skip rating, does NOT rate
--             → should NOT auto-pause (proposed = participated)
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT; v_human_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S4: ProposeOnly', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Human proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_human_id, 'Human idea') RETURNING id INTO v_human_prop_id;

    -- Agent proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Human does NOT rate, does NOT skip rating — just silent in rating phase

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s4_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s4_chat_id')::INT),
    FALSE,
    'S4: Human proposed but silent during rating → NOT paused'
);

-- =============================================================================
-- SCENARIO 5: Human does NOT propose, does NOT skip proposing, but RATES
--             → should auto-pause (no proposing-phase activity from human)
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S5: RateOnly', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Only agent proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Human only rates (no proposition, no proposing skip)
    INSERT INTO public.grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES (v_round_id, v_human_id, v_agent_prop_id, 60);

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s5_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s5_chat_id')::INT),
    TRUE,
    'S5: Human only rated (no proposing activity) → PAUSED'
);

-- =============================================================================
-- SCENARIO 6: Human does NOT participate at all → should auto-pause
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S6: NoParticipation', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Only agent proposes — human does nothing at all
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s6_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s6_chat_id')::INT),
    TRUE,
    'S6: Human did not participate at all → PAUSED'
);

-- =============================================================================
-- SCENARIO 7: Human skips BOTH proposing and rating → should NOT auto-pause
--             (proposing skip = participation)
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S7: SkipBoth', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Only agent proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Human skips both phases
    INSERT INTO public.round_skips (round_id, participant_id)
    VALUES (v_round_id, v_human_id);
    INSERT INTO public.rating_skips (round_id, participant_id)
    VALUES (v_round_id, v_human_id);

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s7_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s7_chat_id')::INT),
    FALSE,
    'S7: Human skipped both proposing and rating → NOT paused (skip = participation)'
);

-- =============================================================================
-- SCENARIO 8: Human only skips rating (no proposing activity)
--             → should auto-pause (rating skip doesn't count as participation)
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := current_setting('test.host_id')::UUID;
    v_chat_id INT; v_cycle_id INT; v_round_id INT;
    v_human_id INT; v_agent_id INT;
    v_agent_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'S8: SkipRatingOnly', 'Test', v_host_id,
        'manual', 300, 300, true, 5, 5, 2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false) RETURNING id INTO v_human_id;

    SELECT id INTO v_agent_id FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Only agent proposes
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_id, 'Agent idea') RETURNING id INTO v_agent_prop_id;

    -- Human only skips rating — no proposing activity at all
    INSERT INTO public.rating_skips (round_id, participant_id)
    VALUES (v_round_id, v_human_id);

    -- Complete round
    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_agent_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id, is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.s8_chat_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.s8_chat_id')::INT),
    TRUE,
    'S8: Human only skipped rating (no proposing activity) → PAUSED'
);

-- =============================================================================
-- SUMMARY TABLE (for readability)
-- =============================================================================
-- S1: Propose + skip rating          → NOT paused  (proposed)
-- S2: Skip proposing + rate          → NOT paused  (proposing skip)
-- S3: Propose + rate                 → NOT paused  (proposed)
-- S4: Propose + silent in rating     → NOT paused  (proposed)
-- S5: Silent in proposing + rate     → PAUSED      (no proposing activity)
-- S6: No participation at all        → PAUSED      (no activity)
-- S7: Skip proposing + skip rating   → NOT paused  (proposing skip)
-- S8: Silent in proposing + skip rating → PAUSED   (no proposing activity)
--
-- Key insight: Auto-pause only checks PROPOSING-phase participation.
-- Rating-only activity (grid_rankings, rating_skips) does NOT prevent pause.
-- =============================================================================

-- Extra assertions to verify the paused chats are really paused
SELECT is(
    (SELECT COUNT(*)::INT FROM public.chats
     WHERE id IN (
         current_setting('test.s1_chat_id')::INT,
         current_setting('test.s2_chat_id')::INT,
         current_setting('test.s3_chat_id')::INT,
         current_setting('test.s4_chat_id')::INT,
         current_setting('test.s7_chat_id')::INT
     ) AND host_paused = false),
    5,
    'All 5 non-paused scenarios confirmed unpaused'
);

SELECT is(
    (SELECT COUNT(*)::INT FROM public.chats
     WHERE id IN (
         current_setting('test.s5_chat_id')::INT,
         current_setting('test.s6_chat_id')::INT,
         current_setting('test.s8_chat_id')::INT
     ) AND host_paused = true),
    3,
    'All 3 paused scenarios confirmed paused'
);

SELECT * FROM finish();
ROLLBACK;
