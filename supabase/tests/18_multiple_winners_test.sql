-- =============================================================================
-- TEST: Multiple Round Winners Support
-- =============================================================================
-- Tests for the multiple winners feature including:
-- 1. round_winners junction table
-- 2. is_sole_winner column on rounds
-- 3. Consecutive SOLE wins tracking (ties don't count)
-- 4. Consensus only reached with sole wins
-- =============================================================================

BEGIN;

SELECT plan(26);

-- =============================================================================
-- SCHEMA TESTS
-- =============================================================================

SELECT has_table('public', 'round_winners', 'round_winners table should exist');
SELECT has_column('public', 'round_winners', 'round_id', 'round_winners should have round_id');
SELECT has_column('public', 'round_winners', 'proposition_id', 'round_winners should have proposition_id');
SELECT has_column('public', 'round_winners', 'rank', 'round_winners should have rank');
SELECT has_column('public', 'round_winners', 'global_score', 'round_winners should have global_score');

SELECT has_column('public', 'rounds', 'is_sole_winner', 'rounds should have is_sole_winner column');

SELECT has_function('public', 'get_round_winners', 'get_round_winners function should exist');

-- =============================================================================
-- TEST DATA SETUP
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Multi-Winner Test', 'Testing multiple winners', gen_random_uuid(), 2);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round1_id INT;
    v_round2_id INT;
    v_round3_id INT;
    v_participant1_id INT;
    v_participant2_id INT;
    v_prop_a_id INT;
    v_prop_b_id INT;
    v_prop_c_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Multi-Winner Test';

    -- Create cycle
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Create round 1
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating')
    RETURNING id INTO v_round1_id;

    -- Create participants
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'User 1', TRUE, 'active')
    RETURNING id INTO v_participant1_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'User 2', FALSE, 'active')
    RETURNING id INTO v_participant2_id;

    -- Create propositions
    INSERT INTO propositions (round_id, participant_id, content, created_at)
    VALUES (v_round1_id, v_participant1_id, 'Proposition A', NOW() - INTERVAL '10 minutes')
    RETURNING id INTO v_prop_a_id;

    INSERT INTO propositions (round_id, participant_id, content, created_at)
    VALUES (v_round1_id, v_participant2_id, 'Proposition B', NOW() - INTERVAL '5 minutes')
    RETURNING id INTO v_prop_b_id;

    INSERT INTO propositions (round_id, participant_id, content, created_at)
    VALUES (v_round1_id, v_participant1_id, 'Proposition C', NOW())
    RETURNING id INTO v_prop_c_id;

    -- Store IDs
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
    PERFORM set_config('test.round1_id', v_round1_id::TEXT, TRUE);
    PERFORM set_config('test.participant1_id', v_participant1_id::TEXT, TRUE);
    PERFORM set_config('test.participant2_id', v_participant2_id::TEXT, TRUE);
    PERFORM set_config('test.prop_a_id', v_prop_a_id::TEXT, TRUE);
    PERFORM set_config('test.prop_b_id', v_prop_b_id::TEXT, TRUE);
    PERFORM set_config('test.prop_c_id', v_prop_c_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST: SOLE WINNER SCENARIO
-- =============================================================================

-- Insert single winner into round_winners
INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
SELECT current_setting('test.round1_id')::INT, current_setting('test.prop_a_id')::INT, 1, 75.0;

SELECT is(
    (SELECT COUNT(*)::INT FROM round_winners WHERE round_id = current_setting('test.round1_id')::INT),
    1,
    'Round 1 should have 1 winner'
);

-- Set sole winner
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_a_id')::INT,
    is_sole_winner = TRUE
WHERE id = current_setting('test.round1_id')::INT;

SELECT is(
    (SELECT is_sole_winner FROM rounds WHERE id = current_setting('test.round1_id')::INT),
    TRUE,
    'Round 1 should be marked as sole winner'
);

-- Verify round 2 was created (trigger fired)
SELECT is(
    (SELECT COUNT(*)::INT FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
    2,
    'Round 2 should be created after round 1 winner set'
);

-- Store round 2 ID
DO $$
DECLARE
    v_round2_id INT;
BEGIN
    SELECT id INTO v_round2_id FROM rounds
    WHERE cycle_id = current_setting('test.cycle_id')::INT
    AND custom_id = 2;
    PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST: TIED WINNER SCENARIO (Round 2)
-- =============================================================================

-- Create propositions for round 2
DO $$
DECLARE
    v_prop_d_id INT;
    v_prop_e_id INT;
BEGIN
    INSERT INTO propositions (round_id, participant_id, content, created_at)
    VALUES (current_setting('test.round2_id')::INT, current_setting('test.participant1_id')::INT, 'Proposition D', NOW() - INTERVAL '5 minutes')
    RETURNING id INTO v_prop_d_id;

    INSERT INTO propositions (round_id, participant_id, content, created_at)
    VALUES (current_setting('test.round2_id')::INT, current_setting('test.participant2_id')::INT, 'Proposition E', NOW())
    RETURNING id INTO v_prop_e_id;

    PERFORM set_config('test.prop_d_id', v_prop_d_id::TEXT, TRUE);
    PERFORM set_config('test.prop_e_id', v_prop_e_id::TEXT, TRUE);
END $$;

-- Insert TWO tied winners for round 2
INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
VALUES
    (current_setting('test.round2_id')::INT, current_setting('test.prop_d_id')::INT, 1, 50.0),
    (current_setting('test.round2_id')::INT, current_setting('test.prop_e_id')::INT, 1, 50.0);

SELECT is(
    (SELECT COUNT(*)::INT FROM round_winners WHERE round_id = current_setting('test.round2_id')::INT),
    2,
    'Round 2 should have 2 tied winners'
);

-- Set tied winner (is_sole_winner = FALSE)
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_d_id')::INT,
    is_sole_winner = FALSE,
    phase = 'rating'
WHERE id = current_setting('test.round2_id')::INT;

SELECT is(
    (SELECT is_sole_winner FROM rounds WHERE id = current_setting('test.round2_id')::INT),
    FALSE,
    'Round 2 should be marked as NOT sole winner (tie)'
);

-- Verify round 3 was created (tie doesn't count toward consensus)
SELECT is(
    (SELECT COUNT(*)::INT FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
    3,
    'Round 3 should be created because tie does not count toward consensus'
);

-- Verify cycle is NOT complete (only 1 sole win, need 2)
SELECT is(
    (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
    NULL::BIGINT,
    'Cycle should NOT be complete (only 1 sole win, tie doesn''t count)'
);

-- =============================================================================
-- TEST: SOLE WIN AFTER TIE (Chain broken, starts fresh)
-- =============================================================================

DO $$
DECLARE
    v_round3_id INT;
    v_prop_f_id INT;
BEGIN
    SELECT id INTO v_round3_id FROM rounds
    WHERE cycle_id = current_setting('test.cycle_id')::INT
    AND custom_id = 3;
    PERFORM set_config('test.round3_id', v_round3_id::TEXT, TRUE);

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round3_id, current_setting('test.participant1_id')::INT, 'Proposition F')
    RETURNING id INTO v_prop_f_id;
    PERFORM set_config('test.prop_f_id', v_prop_f_id::TEXT, TRUE);
END $$;

-- Insert single winner for round 3
INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
SELECT current_setting('test.round3_id')::INT, current_setting('test.prop_f_id')::INT, 1, 80.0;

-- Set sole winner (same proposition as round 1 - Prop A - to test chain)
-- Actually let's use Prop A to test if chain counting works
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_a_id')::INT,
    is_sole_winner = TRUE,
    phase = 'rating'
WHERE id = current_setting('test.round3_id')::INT;

-- The chain should be: Round 1 (A sole) -> Round 2 (D tied, breaks chain) -> Round 3 (A sole)
-- So consecutive sole wins of A = 1 (only round 3), NOT 2

-- Round 4 should be created (need 2 consecutive sole wins, only have 1 after tie broke chain)
SELECT is(
    (SELECT COUNT(*)::INT FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT),
    4,
    'Round 4 should be created (tie broke consecutive wins chain)'
);

-- Cycle still not complete
SELECT is(
    (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
    NULL::BIGINT,
    'Cycle should NOT be complete (chain broken by tie)'
);

-- =============================================================================
-- TEST: TWO CONSECUTIVE SOLE WINS (Consensus reached)
-- =============================================================================

DO $$
DECLARE
    v_round4_id INT;
    v_prop_g_id INT;
BEGIN
    SELECT id INTO v_round4_id FROM rounds
    WHERE cycle_id = current_setting('test.cycle_id')::INT
    AND custom_id = 4;
    PERFORM set_config('test.round4_id', v_round4_id::TEXT, TRUE);

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round4_id, current_setting('test.participant1_id')::INT, 'Proposition G')
    RETURNING id INTO v_prop_g_id;
    PERFORM set_config('test.prop_g_id', v_prop_g_id::TEXT, TRUE);
END $$;

-- Insert single winner for round 4
INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
SELECT current_setting('test.round4_id')::INT, current_setting('test.prop_a_id')::INT, 1, 85.0;

-- Set sole winner (same as round 3 - Prop A)
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_a_id')::INT,
    is_sole_winner = TRUE,
    phase = 'rating'
WHERE id = current_setting('test.round4_id')::INT;

-- Now: Round 3 (A sole) -> Round 4 (A sole) = 2 consecutive sole wins
-- Consensus should be reached!

SELECT is(
    (SELECT winning_proposition_id FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
    current_setting('test.prop_a_id')::BIGINT,
    'Cycle should be complete with Prop A as winner (2 consecutive sole wins)'
);

SELECT isnt(
    (SELECT completed_at FROM cycles WHERE id = current_setting('test.cycle_id')::INT),
    NULL,
    'Cycle completed_at should be set'
);

-- =============================================================================
-- TEST: get_round_winners FUNCTION
-- =============================================================================

SELECT is(
    (SELECT COUNT(*)::INT FROM get_round_winners(current_setting('test.round1_id')::INT)),
    1,
    'get_round_winners should return 1 winner for round 1'
);

SELECT is(
    (SELECT COUNT(*)::INT FROM get_round_winners(current_setting('test.round2_id')::INT)),
    2,
    'get_round_winners should return 2 winners for round 2 (tie)'
);

SELECT ok(
    (SELECT content FROM get_round_winners(current_setting('test.round1_id')::INT) LIMIT 1) = 'Proposition A',
    'get_round_winners should return correct proposition content'
);

-- =============================================================================
-- TEST: UNIQUE CONSTRAINT
-- =============================================================================

SELECT throws_ok(
    format('INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (%s, %s, 1)',
           current_setting('test.round1_id'), current_setting('test.prop_a_id')),
    '23505',  -- unique_violation
    NULL,
    'Should not allow duplicate round_id + proposition_id'
);

-- =============================================================================
-- TEST: RANK CONSTRAINT
-- =============================================================================

SELECT throws_ok(
    format('INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (%s, %s, 0)',
           current_setting('test.round1_id'), current_setting('test.prop_b_id')),
    '23514',  -- check_violation
    NULL,
    'Rank must be >= 1'
);

-- =============================================================================
-- TEST: THREE-WAY TIE
-- =============================================================================

-- Create new chat for 3-way tie test
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Three-Way Tie Test', 'Testing 3-way tie', gen_random_uuid(), 2);

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_p1_id INT;
    v_p2_id INT;
    v_p3_id INT;
    v_prop1_id INT;
    v_prop2_id INT;
    v_prop3_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Three-Way Tie Test';
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active') RETURNING id INTO v_p1_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'Tie Prop 1') RETURNING id INTO v_prop1_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'Tie Prop 2') RETURNING id INTO v_prop2_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1_id, 'Tie Prop 3') RETURNING id INTO v_prop3_id;

    -- Insert 3 tied winners
    INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
    VALUES
        (v_round_id, v_prop1_id, 1, 50.0),
        (v_round_id, v_prop2_id, 1, 50.0),
        (v_round_id, v_prop3_id, 1, 50.0);

    PERFORM set_config('test.threeway_round_id', v_round_id::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT COUNT(*)::INT FROM round_winners WHERE round_id = current_setting('test.threeway_round_id')::INT),
    3,
    'Three-way tie should have 3 winners in round_winners'
);

SELECT is(
    (SELECT COUNT(*)::INT FROM get_round_winners(current_setting('test.threeway_round_id')::INT)),
    3,
    'get_round_winners should return 3 for three-way tie'
);

-- =============================================================================
-- TEST: BACKFILL VERIFICATION (existing rounds should have round_winners entries)
-- =============================================================================

-- All completed rounds should have at least one round_winners entry
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM rounds r
        WHERE r.winning_proposition_id IS NOT NULL
        AND r.cycle_id = current_setting('test.cycle_id')::INT
        AND NOT EXISTS (
            SELECT 1 FROM round_winners rw WHERE rw.round_id = r.id
        )
    ),
    'All completed rounds should have round_winners entries'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();

ROLLBACK;
