-- Tests that rating early advance excludes AI agents when rating_agent_count = 0
-- Bug: When agents don't rate, they were still counted in totalParticipants,
-- making early advance impossible (threshold exceeds possible raters).
BEGIN;
SELECT plan(6);

-- ============================================================================
-- TEST SETUP
-- ============================================================================

DO $$
DECLARE
    v_host_id UUID := gen_random_uuid();
    v_human2_id UUID := gen_random_uuid();
    v_human3_id UUID := gen_random_uuid();
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_host_part_id INT;
    v_human2_part_id INT;
    v_human3_part_id INT;
    v_agent_part_id INT;
    v_prop1_id INT;
    v_prop2_id INT;
    v_prop3_id INT;
    v_human_count INT;
    v_total_count INT;
BEGIN
    -- Create users
    INSERT INTO auth.users (id) VALUES (v_host_id), (v_human2_id), (v_human3_id);

    -- Create chat with agents enabled but rating_agent_count = 0
    -- Agents propose but do NOT rate
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        start_mode, proposing_duration_seconds, rating_duration_seconds,
        enable_agents, proposing_agent_count, rating_agent_count,
        proposing_minimum, rating_minimum,
        confirmation_rounds_required
    ) VALUES (
        'Agent No Rate Chat', 'Should agents rate?', v_host_id,
        'auto', 300, 300,
        true, 2, 0,  -- 2 agents propose, 0 agents rate
        3, 2,
        2
    ) RETURNING id INTO v_chat_id;

    -- 3 human participants
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status, is_agent)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active', false)
    RETURNING id INTO v_host_part_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, status, is_agent)
    VALUES (v_chat_id, v_human2_id, 'Human 2', 'active', false)
    RETURNING id INTO v_human2_part_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, status, is_agent)
    VALUES (v_chat_id, v_human3_id, 'Human 3', 'active', false)
    RETURNING id INTO v_human3_part_id;

    -- Get one of the auto-created agent participants
    SELECT id INTO v_agent_part_id
    FROM public.participants
    WHERE chat_id = v_chat_id AND is_agent = true
    LIMIT 1;

    -- Create cycle and round in rating phase
    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', now(), now() + interval '5 minutes')
    RETURNING id INTO v_round_id;

    -- Add propositions (3 humans + 1 agent)
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_part_id, 'Human 1 idea')
    RETURNING id INTO v_prop1_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_human2_part_id, 'Human 2 idea')
    RETURNING id INTO v_prop2_id;

    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_human3_part_id, 'Human 3 idea')
    RETURNING id INTO v_prop3_id;

    -- Count total active participants (includes agents)
    SELECT COUNT(*)::INT INTO v_total_count
    FROM public.participants
    WHERE chat_id = v_chat_id AND status = 'active';

    -- Count human-only participants
    SELECT COUNT(*)::INT INTO v_human_count
    FROM public.participants
    WHERE chat_id = v_chat_id AND status = 'active' AND is_agent = false;

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.host_part_id', v_host_part_id::TEXT, TRUE);
    PERFORM set_config('test.human2_part_id', v_human2_part_id::TEXT, TRUE);
    PERFORM set_config('test.prop1_id', v_prop1_id::TEXT, TRUE);
    PERFORM set_config('test.prop2_id', v_prop2_id::TEXT, TRUE);
    PERFORM set_config('test.prop3_id', v_prop3_id::TEXT, TRUE);
    PERFORM set_config('test.total_count', v_total_count::TEXT, TRUE);
    PERFORM set_config('test.human_count', v_human_count::TEXT, TRUE);
END $$;

-- ============================================================================
-- TEST 1: Total participant count includes agents
-- ============================================================================
SELECT is(
    current_setting('test.total_count')::INT > current_setting('test.human_count')::INT,
    true,
    'Total participants includes agents (more than human-only count)'
);

-- ============================================================================
-- TEST 2: Human count is exactly 3
-- ============================================================================
SELECT is(
    current_setting('test.human_count')::INT,
    3,
    'There are exactly 3 human participants'
);

-- ============================================================================
-- TEST 3: get_rating_eligible_count returns only humans when rating_agent_count = 0
-- ============================================================================
SELECT is(
    public.get_rating_eligible_count(current_setting('test.chat_id')::INT),
    3,
    'get_rating_eligible_count returns 3 (humans only) when rating_agent_count = 0'
);

-- ============================================================================
-- TEST 4: With 3 humans, 100% threshold capped to (3-1)=2 raters needed
-- After 2 humans rate, early advance should be possible
-- ============================================================================

-- Human 2 rates (rates prop1 and prop3, skips own prop2)
DO $$
BEGIN
    INSERT INTO public.grid_rankings (round_id, proposition_id, participant_id, grid_position)
    VALUES
        (current_setting('test.round_id')::INT, current_setting('test.prop1_id')::INT,
         current_setting('test.human2_part_id')::INT, 1),
        (current_setting('test.round_id')::INT, current_setting('test.prop3_id')::INT,
         current_setting('test.human2_part_id')::INT, 2);
END $$;

-- Host rates (rates prop2 and prop3, skips own prop1)
DO $$
BEGIN
    INSERT INTO public.grid_rankings (round_id, proposition_id, participant_id, grid_position)
    VALUES
        (current_setting('test.round_id')::INT, current_setting('test.prop2_id')::INT,
         current_setting('test.host_part_id')::INT, 1),
        (current_setting('test.round_id')::INT, current_setting('test.prop3_id')::INT,
         current_setting('test.host_part_id')::INT, 2);
END $$;

-- Count unique raters
SELECT is(
    (SELECT COUNT(DISTINCT participant_id)::INT
     FROM public.grid_rankings
     WHERE round_id = current_setting('test.round_id')::INT),
    2,
    '2 humans have rated'
);

-- ============================================================================
-- TEST 5: With correct eligible count (3 humans), threshold = min(3, 3-1) = 2
-- 2 raters >= 2 required → early advance SHOULD be possible
-- ============================================================================
SELECT is(
    (SELECT COUNT(DISTINCT participant_id)::INT
     FROM public.grid_rankings
     WHERE round_id = current_setting('test.round_id')::INT)
    >=
    LEAST(
        public.get_rating_eligible_count(current_setting('test.chat_id')::INT),
        public.get_rating_eligible_count(current_setting('test.chat_id')::INT) - 1
    ),
    true,
    'With correct eligible count, 2 raters meets threshold (humans-1=2)'
);

-- ============================================================================
-- TEST 6: BUG - Using total count (with agents), threshold would be too high
-- With 5 total (3 humans + 2 agents), threshold = min(5, 5-1) = 4
-- 2 raters < 4 required → early advance would be BLOCKED incorrectly
-- ============================================================================
SELECT is(
    (SELECT COUNT(DISTINCT participant_id)::INT
     FROM public.grid_rankings
     WHERE round_id = current_setting('test.round_id')::INT)
    >=
    LEAST(
        current_setting('test.total_count')::INT,
        current_setting('test.total_count')::INT - 1
    ),
    false,
    'BUG: Using total count (with non-rating agents), threshold is impossible to meet'
);

SELECT * FROM finish();
ROLLBACK;
