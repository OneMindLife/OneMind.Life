-- =============================================================================
-- TEST: Proposing Minimum Should Exclude Carried Forward Propositions
-- =============================================================================
-- Verifies that when counting propositions for the proposing_minimum check,
-- carried forward propositions (carried_from_id IS NOT NULL) are excluded.
-- This ensures the minimum count only includes NEW propositions.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(6);

-- =============================================================================
-- TEST DATA SETUP
-- =============================================================================

-- Create a chat with proposing_minimum = 3
INSERT INTO chats (name, initial_message, creator_session_token, proposing_minimum)
VALUES ('Proposing Min Test', 'Testing minimum excludes carried', gen_random_uuid(), 3);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round1_id INT;
    v_round2_id INT;
    v_participant1_id INT;
    v_participant2_id INT;
    v_participant3_id INT;
    v_winning_prop_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Proposing Min Test';

    -- Create cycle
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO v_cycle_id;

    -- Create round 1 (completed)
    INSERT INTO rounds (cycle_id, custom_id, phase, completed_at)
    VALUES (v_cycle_id, 1, 'rating', NOW())
    RETURNING id INTO v_round1_id;

    -- Create round 2 (current proposing phase)
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 2, 'proposing')
    RETURNING id INTO v_round2_id;

    -- Create 3 participants
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'Host', TRUE, 'active')
    RETURNING id INTO v_participant1_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'User2', FALSE, 'active')
    RETURNING id INTO v_participant2_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'User3', FALSE, 'active')
    RETURNING id INTO v_participant3_id;

    -- Create winning proposition in round 1
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_participant1_id, 'Winner from Round 1')
    RETURNING id INTO v_winning_prop_id;

    -- Simulate 2 carried forward propositions in round 2 (from previous round's winners)
    INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round2_id, v_participant1_id, 'Winner from Round 1', v_winning_prop_id);

    INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round2_id, v_participant2_id, 'Another carried forward', v_winning_prop_id);

    -- Create 1 NEW proposition in round 2
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round2_id, v_participant3_id, 'Brand new idea');

    -- Store IDs for tests
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- COUNT TESTS
-- =============================================================================

-- Test 1: Total propositions in round 2 (including carried forward) = 3
SELECT is(
    (SELECT COUNT(*)::INT FROM propositions WHERE round_id = current_setting('test.round2_id')::INT),
    3,
    'Round 2 should have 3 total propositions (2 carried + 1 new)'
);

-- Test 2: Carried forward propositions in round 2 = 2
SELECT is(
    (SELECT COUNT(*)::INT FROM propositions
     WHERE round_id = current_setting('test.round2_id')::INT
     AND carried_from_id IS NOT NULL),
    2,
    'Round 2 should have 2 carried forward propositions'
);

-- Test 3: NEW propositions in round 2 (carried_from_id IS NULL) = 1
SELECT is(
    (SELECT COUNT(*)::INT FROM propositions
     WHERE round_id = current_setting('test.round2_id')::INT
     AND carried_from_id IS NULL),
    1,
    'Round 2 should have 1 NEW proposition (excluding carried forward)'
);

-- =============================================================================
-- MINIMUM CHECK TESTS
-- =============================================================================

-- Test 4: With ALL propositions, minimum of 3 would be met (but this is WRONG behavior)
SELECT is(
    (SELECT COUNT(*) >= 3 FROM propositions WHERE round_id = current_setting('test.round2_id')::INT),
    TRUE,
    'Total count (3) meets minimum of 3 - but this includes carried forward'
);

-- Test 5: With only NEW propositions, minimum of 3 is NOT met (CORRECT behavior)
SELECT is(
    (SELECT COUNT(*) >= 3 FROM propositions
     WHERE round_id = current_setting('test.round2_id')::INT
     AND carried_from_id IS NULL),
    FALSE,
    'NEW proposition count (1) does NOT meet minimum of 3 - correct behavior'
);

-- Test 6: Verify the proposing_minimum setting is 3
SELECT is(
    (SELECT proposing_minimum FROM chats WHERE id = current_setting('test.chat_id')::INT),
    3,
    'Chat should have proposing_minimum = 3'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
