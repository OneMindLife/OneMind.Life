-- Tests for auto-pause when round completes with only agent activity
BEGIN;
SELECT plan(9);

-- ============================================================================
-- TEST SETUP
-- ============================================================================

DO $$
DECLARE
    v_host_id UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_host_part_id INT;
    v_agent_part_id INT;
    v_prop_id INT;

    -- Second chat: human participates
    v_chat2_id INT;
    v_cycle2_id INT;
    v_round2_id INT;
    v_host2_part_id INT;
    v_agent2_part_id INT;
    v_prop2_id INT;
    v_prop2h_id INT;

    -- Third chat: agents disabled
    v_chat3_id INT;
    v_cycle3_id INT;
    v_round3_id INT;
    v_host3_part_id INT;
    v_prop3_id INT;
BEGIN
    -- Create host user
    INSERT INTO auth.users (id) VALUES (v_host_id);

    -- ========================================================================
    -- CHAT 1: Agent-only propositions (should auto-pause)
    -- ========================================================================
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'Agent Only Chat', 'Test', v_host_id,
        'manual', 300, 300,
        true, 5, 5,
        2
    ) RETURNING id INTO v_chat_id;

    -- Host joins
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false)
    RETURNING id INTO v_host_part_id;

    -- Get one of the auto-created agent participants
    SELECT id INTO v_agent_part_id
    FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true
    LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round_id;

    -- Only agent submits a proposition
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_part_id, 'Agent proposal')
    RETURNING id INTO v_prop_id;

    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_prop_id, 1, 100.0);

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.prop_id', v_prop_id::TEXT, TRUE);

    -- ========================================================================
    -- CHAT 2: Human + agent propositions (should NOT auto-pause)
    -- ========================================================================
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'Human Active Chat', 'Test', v_host_id,
        'manual', 300, 300,
        true, 5, 5,
        2
    ) RETURNING id INTO v_chat2_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat2_id, v_host_id, 'Host', TRUE, 'active', false)
    RETURNING id INTO v_host2_part_id;

    SELECT id INTO v_agent2_part_id
    FROM public.participants
    WHERE chat_id = v_chat2_id AND is_agent = true
    LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat2_id) RETURNING id INTO v_cycle2_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle2_id, 1, 'rating')
    RETURNING id INTO v_round2_id;

    -- Both agent and human submit propositions
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round2_id, v_agent2_part_id, 'Agent proposal')
    RETURNING id INTO v_prop2_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round2_id, v_host2_part_id, 'Human proposal')
    RETURNING id INTO v_prop2h_id;

    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round2_id, v_prop2_id, 1, 100.0);

    PERFORM set_config('test.chat2_id', v_chat2_id::TEXT, TRUE);
    PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
    PERFORM set_config('test.prop2_id', v_prop2_id::TEXT, TRUE);

    -- ========================================================================
    -- CHAT 3: Agents disabled (should NOT auto-pause)
    -- ========================================================================
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, confirmation_rounds_required
    ) VALUES (
        'No Agents Chat', 'Test', v_host_id,
        'manual', 300, 300,
        false, 2
    ) RETURNING id INTO v_chat3_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat3_id, v_host_id, 'Host', TRUE, 'active', false)
    RETURNING id INTO v_host3_part_id;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat3_id) RETURNING id INTO v_cycle3_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle3_id, 1, 'rating')
    RETURNING id INTO v_round3_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round3_id, v_host3_part_id, 'Human only proposal')
    RETURNING id INTO v_prop3_id;

    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round3_id, v_prop3_id, 1, 100.0);

    PERFORM set_config('test.chat3_id', v_chat3_id::TEXT, TRUE);
    PERFORM set_config('test.round3_id', v_round3_id::TEXT, TRUE);
    PERFORM set_config('test.prop3_id', v_prop3_id::TEXT, TRUE);
END $$;

-- ============================================================================
-- TEST 1: Initial state — all chats are not paused
-- ============================================================================

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    FALSE,
    'Chat 1 (agent-only) should start unpaused'
);

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat2_id')::INT),
    FALSE,
    'Chat 2 (human active) should start unpaused'
);

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat3_id')::INT),
    FALSE,
    'Chat 3 (no agents) should start unpaused'
);

-- ============================================================================
-- TEST 2: Complete agent-only round → should auto-pause
-- ============================================================================

UPDATE public.rounds
SET winning_proposition_id = current_setting('test.prop_id')::INT,
    is_sole_winner = true
WHERE id = current_setting('test.round_id')::INT;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat_id')::INT),
    TRUE,
    'Chat 1 should be auto-paused after agent-only round completes'
);

-- ============================================================================
-- TEST 3: Complete round with human participation → should NOT auto-pause
-- ============================================================================

UPDATE public.rounds
SET winning_proposition_id = current_setting('test.prop2_id')::INT,
    is_sole_winner = true
WHERE id = current_setting('test.round2_id')::INT;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat2_id')::INT),
    FALSE,
    'Chat 2 should NOT be auto-paused when human proposed'
);

-- ============================================================================
-- TEST 4: Complete round with agents disabled → should NOT auto-pause
-- ============================================================================

UPDATE public.rounds
SET winning_proposition_id = current_setting('test.prop3_id')::INT,
    is_sole_winner = true
WHERE id = current_setting('test.round3_id')::INT;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat3_id')::INT),
    FALSE,
    'Chat 3 should NOT be auto-paused when agents are disabled'
);

-- ============================================================================
-- TEST 5: Carried-forward human proposition doesn't prevent pause
-- ============================================================================
-- A carried-forward prop from a human in a previous round should not count
-- as human participation in the current round.

DO $$
DECLARE
    v_host_id UUID := (SELECT creator_id FROM public.chats WHERE id = current_setting('test.chat_id')::INT);
    v_chat_id INT;
    v_cycle_id INT;
    v_round1_id INT;
    v_round2_id INT;
    v_host_part_id INT;
    v_agent_part_id INT;
    v_human_prop_id INT;
    v_agent_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'Carry Forward Test', 'Test', v_host_id,
        'manual', 300, 300,
        true, 5, 5,
        2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false)
    RETURNING id INTO v_host_part_id;

    SELECT id INTO v_agent_part_id
    FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true
    LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Round 1: human proposes, completes (should NOT pause — human participated)
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round1_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_host_part_id, 'Human idea')
    RETURNING id INTO v_human_prop_id;

    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round1_id, v_human_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_human_prop_id,
        is_sole_winner = true
    WHERE id = v_round1_id;

    -- Round 1 had human participation, so it should NOT have paused.
    -- But reset host_paused just in case, to isolate the round 2 test.
    UPDATE public.chats SET host_paused = false WHERE id = v_chat_id;

    -- Round 2 was created by carry-forward trigger; find it
    SELECT id INTO v_round2_id
    FROM public.rounds
    WHERE cycle_id = v_cycle_id AND custom_id = 2;

    -- Only agent submits a NEW proposition in round 2
    -- (The carried-forward human prop exists but should not count)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round2_id, v_agent_part_id, 'Agent round 2 idea')
    RETURNING id INTO v_agent_prop_id;

    UPDATE public.rounds SET phase = 'rating' WHERE id = v_round2_id;

    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round2_id, v_agent_prop_id, 1, 100.0);

    -- Complete round 2 — only new proposition is from agent
    UPDATE public.rounds
    SET winning_proposition_id = v_agent_prop_id,
        is_sole_winner = true
    WHERE id = v_round2_id;

    PERFORM set_config('test.chat4_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat4_id')::INT),
    TRUE,
    'Chat should auto-pause when only new propositions are from agents (carried-forward human prop does not count)'
);

-- ============================================================================
-- TEST 6: Human skip counts as participation → should NOT auto-pause
-- ============================================================================

DO $$
DECLARE
    v_host_id UUID := (SELECT creator_id FROM public.chats WHERE id = current_setting('test.chat_id')::INT);
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_host_part_id INT;
    v_agent_part_id INT;
    v_prop_id INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        confirmation_rounds_required
    ) VALUES (
        'Human Skip Test', 'Test', v_host_id,
        'manual', 300, 300,
        true, 5, 5,
        2
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false)
    RETURNING id INTO v_host_part_id;

    SELECT id INTO v_agent_part_id
    FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true
    LIMIT 1;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round_id;

    -- Agent proposes, human skips
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_agent_part_id, 'Agent proposal')
    RETURNING id INTO v_prop_id;

    INSERT INTO public.round_skips (round_id, participant_id)
    VALUES (v_round_id, v_host_part_id);

    INSERT INTO public.round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round_id, v_prop_id, 1, 100.0);

    UPDATE public.rounds
    SET winning_proposition_id = v_prop_id,
        is_sole_winner = true
    WHERE id = v_round_id;

    PERFORM set_config('test.chat5_id', v_chat_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT host_paused FROM public.chats WHERE id = current_setting('test.chat5_id')::INT),
    FALSE,
    'Chat should NOT auto-pause when human skipped (skip = active participation)'
);

-- ============================================================================
-- TEST 7: Auto-pause sets host_paused, is_chat_paused returns true
-- ============================================================================

SELECT is(
    (SELECT is_chat_paused(current_setting('test.chat_id')::INT)),
    TRUE,
    'is_chat_paused() returns true for auto-paused chat'
);

SELECT * FROM finish();
ROLLBACK;
