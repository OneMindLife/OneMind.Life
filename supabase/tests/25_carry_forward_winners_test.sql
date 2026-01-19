-- =============================================================================
-- TEST: Carry Forward Winners for Consensus Tracking
-- =============================================================================
-- Tests for the carried_from_id column and get_root_proposition_id function
-- that enable consensus tracking across rounds
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(17);

-- =============================================================================
-- SCHEMA TESTS
-- =============================================================================

-- Test 1: propositions table has carried_from_id column
SELECT has_column('public', 'propositions', 'carried_from_id',
    'propositions table should have carried_from_id column');

-- Test 2: get_root_proposition_id function exists
SELECT has_function('public', 'get_root_proposition_id',
    'get_root_proposition_id function should exist');

-- =============================================================================
-- TEST DATA SETUP
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Carry Forward Test', 'Testing carry forward', gen_random_uuid(), 2);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round1_id INT;
    v_round2_id INT;
    v_round3_id INT;
    v_participant_id INT;
    v_prop_original_id INT;
    v_prop_carried1_id INT;
    v_prop_carried2_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Carry Forward Test';

    -- Create cycle
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO v_cycle_id;

    -- Create 3 rounds
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round1_id;

    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 2, 'rating')
    RETURNING id INTO v_round2_id;

    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 3, 'proposing')
    RETURNING id INTO v_round3_id;

    -- Create participant
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'Host', TRUE, 'active')
    RETURNING id INTO v_participant_id;

    -- Create original proposition in round 1
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_participant_id, 'Winning Idea')
    RETURNING id INTO v_prop_original_id;

    -- Create carried forward proposition in round 2 (references original)
    INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round2_id, v_participant_id, 'Winning Idea', v_prop_original_id)
    RETURNING id INTO v_prop_carried1_id;

    -- Create carried forward proposition in round 3 (references original, not intermediate)
    INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round3_id, v_participant_id, 'Winning Idea', v_prop_original_id)
    RETURNING id INTO v_prop_carried2_id;

    -- Store IDs for tests
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.round1_id', v_round1_id::TEXT, TRUE);
    PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
    PERFORM set_config('test.round3_id', v_round3_id::TEXT, TRUE);
    PERFORM set_config('test.prop_original_id', v_prop_original_id::TEXT, TRUE);
    PERFORM set_config('test.prop_carried1_id', v_prop_carried1_id::TEXT, TRUE);
    PERFORM set_config('test.prop_carried2_id', v_prop_carried2_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- GET_ROOT_PROPOSITION_ID TESTS
-- =============================================================================

-- Test 3: Root of original proposition is itself
SELECT is(
    get_root_proposition_id(current_setting('test.prop_original_id')::BIGINT),
    current_setting('test.prop_original_id')::BIGINT,
    'Root of original proposition should be itself'
);

-- Test 4: Root of first carried proposition is the original
SELECT is(
    get_root_proposition_id(current_setting('test.prop_carried1_id')::BIGINT),
    current_setting('test.prop_original_id')::BIGINT,
    'Root of carried proposition should be the original'
);

-- Test 5: Root of second carried proposition is also the original
SELECT is(
    get_root_proposition_id(current_setting('test.prop_carried2_id')::BIGINT),
    current_setting('test.prop_original_id')::BIGINT,
    'Root of second carried proposition should be the original'
);

-- =============================================================================
-- CHAIN TRACKING TESTS
-- =============================================================================

-- Test 6: Create a chain and verify root tracking
DO $$
DECLARE
    v_round3_id INT := current_setting('test.round3_id')::BIGINT;
    v_prop_carried2_id INT := current_setting('test.prop_carried2_id')::BIGINT;
    v_prop_chain_id INT;
BEGIN
    -- Create a proposition that references a carried proposition (chain of 2)
    INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    SELECT round_id, participant_id, content, v_prop_carried2_id
    FROM propositions WHERE id = v_prop_carried2_id
    RETURNING id INTO v_prop_chain_id;

    PERFORM set_config('test.prop_chain_id', v_prop_chain_id::TEXT, TRUE);
END $$;

-- Test 7: Even with a chain, root should still be the original
SELECT is(
    get_root_proposition_id(current_setting('test.prop_chain_id')::BIGINT),
    current_setting('test.prop_original_id')::BIGINT,
    'Root should trace back through the chain to original'
);

-- =============================================================================
-- CONSENSUS TRACKING WITH CARRIED FORWARD PROPOSITIONS
-- =============================================================================

-- Test 8: Set winner in round 1 (original proposition)
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_original_id')::BIGINT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.round1_id')::BIGINT;

SELECT is(
    (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round1_id')::BIGINT),
    current_setting('test.prop_original_id')::BIGINT,
    'Round 1 winner should be set to original proposition'
);

-- Test 9: Set winner in round 2 (carried forward proposition)
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_carried1_id')::BIGINT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.round2_id')::BIGINT;

SELECT is(
    (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round2_id')::BIGINT),
    current_setting('test.prop_carried1_id')::BIGINT,
    'Round 2 winner should be set to carried proposition'
);

-- Test 10: Both winners should have the same root
SELECT is(
    get_root_proposition_id(
        (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round1_id')::BIGINT)
    ),
    get_root_proposition_id(
        (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round2_id')::BIGINT)
    ),
    'Both round winners should have the same root proposition ID'
);

-- =============================================================================
-- EDGE CASES
-- =============================================================================

-- Test 11: Proposition without carried_from_id returns itself as root
DO $$
DECLARE
    v_round1_id INT := current_setting('test.round1_id')::BIGINT;
    v_standalone_id INT;
BEGIN
    INSERT INTO propositions (round_id, participant_id, content)
    SELECT round_id, participant_id, 'Standalone Idea'
    FROM propositions WHERE id = current_setting('test.prop_original_id')::BIGINT
    RETURNING id INTO v_standalone_id;

    PERFORM set_config('test.prop_standalone_id', v_standalone_id::TEXT, TRUE);
END $$;

SELECT is(
    get_root_proposition_id(current_setting('test.prop_standalone_id')::BIGINT),
    current_setting('test.prop_standalone_id')::BIGINT,
    'Standalone proposition root should be itself'
);

-- Test 12: carried_from_id can be NULL
SELECT ok(
    (SELECT carried_from_id IS NULL FROM propositions WHERE id = current_setting('test.prop_original_id')::BIGINT),
    'Original proposition should have NULL carried_from_id'
);

-- Test 13: carried_from_id is set correctly for carried propositions
SELECT is(
    (SELECT carried_from_id FROM propositions WHERE id = current_setting('test.prop_carried1_id')::BIGINT),
    current_setting('test.prop_original_id')::BIGINT,
    'Carried proposition should reference original'
);

-- =============================================================================
-- CONSENSUS REACHED WITH CARRIED FORWARD
-- =============================================================================

-- Create a fresh chat with confirmation_rounds_required = 2
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Consensus Carry Test', 'Testing consensus with carry forward', gen_random_uuid(), 2);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round1_id INT;
    v_participant_id INT;
    v_prop_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Consensus Carry Test';

    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO v_cycle_id;

    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round1_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'TestHost', TRUE, 'active')
    RETURNING id INTO v_participant_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_participant_id, 'Consensus Winner')
    RETURNING id INTO v_prop_id;

    PERFORM set_config('test.consensus_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.consensus_cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.consensus_round1_id', v_round1_id::TEXT, TRUE);
    PERFORM set_config('test.consensus_prop_id', v_prop_id::TEXT, TRUE);
END $$;

-- Test 14: First win creates next round
UPDATE rounds
SET winning_proposition_id = current_setting('test.consensus_prop_id')::BIGINT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.consensus_round1_id')::BIGINT;

SELECT is(
    (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.consensus_cycle_id')::BIGINT),
    2::BIGINT,
    'First win should create round 2'
);

-- Create carried forward proposition in round 2 and set as winner
DO $$
DECLARE
    v_cycle_id INT := current_setting('test.consensus_cycle_id')::BIGINT;
    v_original_prop_id INT := current_setting('test.consensus_prop_id')::BIGINT;
    v_round2_id INT;
    v_carried_prop_id INT;
BEGIN
    SELECT id INTO v_round2_id FROM rounds
    WHERE cycle_id = v_cycle_id AND custom_id = 2;

    -- Carry forward the winner
    INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    SELECT v_round2_id, participant_id, content, v_original_prop_id
    FROM propositions WHERE id = v_original_prop_id
    RETURNING id INTO v_carried_prop_id;

    -- Update round 2 phase to rating and set winner
    UPDATE rounds SET phase = 'rating' WHERE id = v_round2_id;
    UPDATE rounds
    SET winning_proposition_id = v_carried_prop_id,
        is_sole_winner = TRUE
    WHERE id = v_round2_id;

    PERFORM set_config('test.consensus_round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- Test 15: Second consecutive win with same root should reach consensus
SELECT is(
    (SELECT completed_at IS NOT NULL FROM cycles WHERE id = current_setting('test.consensus_cycle_id')::BIGINT),
    TRUE,
    'Cycle should be completed after 2 consecutive sole wins with same root'
);

-- =============================================================================
-- AUTOMATIC CARRY FORWARD IN TRIGGER TESTS
-- =============================================================================

-- Create a fresh chat to test automatic carry forward
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Auto Carry Test', 'Testing auto carry forward', gen_random_uuid(), 2);

DO $$
DECLARE
    v_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round1_id BIGINT;
    v_participant_id BIGINT;
    v_prop_id BIGINT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Auto Carry Test';

    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO v_cycle_id;

    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round1_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'AutoHost', TRUE, 'active')
    RETURNING id INTO v_participant_id;

    -- Create a proposition that will win
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_participant_id, 'Auto Winner Prop')
    RETURNING id INTO v_prop_id;

    -- Insert into round_winners (simulating rating completion)
    INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round1_id, v_prop_id, 1, 85.0);

    PERFORM set_config('test.auto_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.auto_cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.auto_round1_id', v_round1_id::TEXT, TRUE);
    PERFORM set_config('test.auto_prop_id', v_prop_id::TEXT, TRUE);
END $$;

-- Test 16: Setting winner triggers round creation
UPDATE rounds
SET winning_proposition_id = current_setting('test.auto_prop_id')::BIGINT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.auto_round1_id')::BIGINT;

SELECT is(
    (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.auto_cycle_id')::BIGINT),
    2::BIGINT,
    'Trigger should create round 2 when winner is set'
);

-- Test 17: Winner should be automatically carried forward to new round
SELECT is(
    (SELECT COUNT(*) FROM propositions p
     JOIN rounds r ON p.round_id = r.id
     WHERE r.cycle_id = current_setting('test.auto_cycle_id')::BIGINT
     AND r.custom_id = 2
     AND p.carried_from_id IS NOT NULL),
    1::BIGINT,
    'Winner should be automatically carried forward to round 2'
);

-- Test 18: Carried proposition should reference the original
SELECT is(
    (SELECT p.carried_from_id FROM propositions p
     JOIN rounds r ON p.round_id = r.id
     WHERE r.cycle_id = current_setting('test.auto_cycle_id')::BIGINT
     AND r.custom_id = 2
     AND p.carried_from_id IS NOT NULL
     LIMIT 1),
    current_setting('test.auto_prop_id')::BIGINT,
    'Carried proposition should reference original proposition'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
