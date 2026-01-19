-- =============================================================================
-- TEST: Tie-Breaker Scenarios for Winner Determination
-- =============================================================================
-- Tests for tie-breaker logic when propositions have equal or near-equal scores.
-- The tie-breaker policy is: oldest proposition wins (first submitted).
--
-- Note: MOVDA's percentile normalization with N propositions spreads scores
-- across 0-100, so with only 2 propositions even small differences become 0/100.
-- These tests focus on the tie-breaker LOGIC, not MOVDA score equality.
-- =============================================================================

BEGIN;

SELECT plan(11);

-- =============================================================================
-- TEST DATA SETUP
-- =============================================================================

-- Create test chat
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Tie-Breaker Test Chat', 'Testing tie-breaker scenarios', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant1_id INT;
  v_participant2_id INT;
  v_prop_a_id INT;
  v_prop_b_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Tie-Breaker Test Chat';

  -- Create cycle
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- Create round in rating phase
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating')
  RETURNING id INTO v_round_id;

  -- Create two participants
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'User 1', TRUE, 'active')
  RETURNING id INTO v_participant1_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'User 2', FALSE, 'active')
  RETURNING id INTO v_participant2_id;

  -- Create proposition A first (will be older)
  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_round_id, v_participant1_id, 'Proposition A', NOW() - INTERVAL '10 minutes')
  RETURNING id INTO v_prop_a_id;

  -- Create proposition B second (will be newer)
  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_round_id, v_participant2_id, 'Proposition B', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_prop_b_id;

  -- Store IDs for later tests
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.participant1_id', v_participant1_id::TEXT, TRUE);
  PERFORM set_config('test.participant2_id', v_participant2_id::TEXT, TRUE);
  PERFORM set_config('test.prop_a_id', v_prop_a_id::TEXT, TRUE);
  PERFORM set_config('test.prop_b_id', v_prop_b_id::TEXT, TRUE);
END $$;

-- Note: MOVDA trigger was removed (it's now called only at phase end)
-- No need to disable trigger for controlled testing

-- =============================================================================
-- TEST: TIE-BREAKER FUNCTION (Tests the selection logic directly)
-- =============================================================================

-- Create test function that simulates tie-breaker logic
CREATE OR REPLACE FUNCTION test_get_winner_with_tiebreaker(
    p_round_id BIGINT,
    p_tolerance REAL DEFAULT 0.001
)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_winner_id BIGINT;
    v_top_score REAL;
BEGIN
    -- Get top score
    SELECT global_score INTO v_top_score
    FROM proposition_global_scores
    WHERE round_id = p_round_id
    ORDER BY global_score DESC
    LIMIT 1;

    -- Get oldest proposition among those within tolerance of top score
    SELECT p.id INTO v_winner_id
    FROM propositions p
    JOIN proposition_global_scores pgs ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
    WHERE ABS(pgs.global_score - v_top_score) <= p_tolerance
    ORDER BY p.created_at ASC
    LIMIT 1;

    RETURN v_winner_id;
END;
$$;

-- =============================================================================
-- TEST: PROPOSITION CREATION ORDER
-- =============================================================================

-- Test: Proposition A was created first
SELECT ok(
    (SELECT created_at FROM propositions WHERE id = current_setting('test.prop_a_id')::INT)
    < (SELECT created_at FROM propositions WHERE id = current_setting('test.prop_b_id')::INT),
    'Proposition A should have earlier created_at than Proposition B'
);

-- =============================================================================
-- TEST: EXACT TIE WITH MANUAL SCORES
-- =============================================================================

-- Insert identical scores manually to test tie-breaker
INSERT INTO proposition_global_scores (round_id, proposition_id, global_score)
VALUES
    (current_setting('test.round_id')::INT, current_setting('test.prop_a_id')::INT, 50.0),
    (current_setting('test.round_id')::INT, current_setting('test.prop_b_id')::INT, 50.0);

-- Test: Both have scores
SELECT is(
    (SELECT COUNT(*)::INT FROM proposition_global_scores WHERE round_id = current_setting('test.round_id')::INT),
    2,
    'Both propositions should have global scores'
);

-- Test: Scores are exactly equal
SELECT is(
    (SELECT global_score FROM proposition_global_scores
     WHERE round_id = current_setting('test.round_id')::INT
     AND proposition_id = current_setting('test.prop_a_id')::INT),
    (SELECT global_score FROM proposition_global_scores
     WHERE round_id = current_setting('test.round_id')::INT
     AND proposition_id = current_setting('test.prop_b_id')::INT),
    'Both propositions should have identical scores (50.0)'
);

-- Test: Tie-breaker selects oldest proposition (A)
SELECT is(
    test_get_winner_with_tiebreaker(current_setting('test.round_id')::INT),
    current_setting('test.prop_a_id')::BIGINT,
    'Exact tie: tie-breaker should select Proposition A (older)'
);

-- =============================================================================
-- TEST: NEAR-TIE WITHIN TOLERANCE
-- =============================================================================

-- Update scores to be within tolerance (0.001)
UPDATE proposition_global_scores
SET global_score = 50.0005
WHERE round_id = current_setting('test.round_id')::INT
AND proposition_id = current_setting('test.prop_b_id')::INT;

-- Test: Tie-breaker still selects oldest when within tolerance
SELECT is(
    test_get_winner_with_tiebreaker(current_setting('test.round_id')::INT, 0.001),
    current_setting('test.prop_a_id')::BIGINT,
    'Near-tie within tolerance: should select Proposition A (older)'
);

-- =============================================================================
-- TEST: CLEAR WINNER (OUTSIDE TOLERANCE)
-- =============================================================================

-- Update B to have clearly higher score
UPDATE proposition_global_scores
SET global_score = 75.0
WHERE round_id = current_setting('test.round_id')::INT
AND proposition_id = current_setting('test.prop_b_id')::INT;

-- Test: Higher-scored proposition wins (regardless of age)
SELECT is(
    test_get_winner_with_tiebreaker(current_setting('test.round_id')::INT, 0.001),
    current_setting('test.prop_b_id')::BIGINT,
    'Clear winner: higher-scored Proposition B wins despite being newer'
);

-- =============================================================================
-- TEST: THREE-WAY TIE
-- =============================================================================

DO $$
DECLARE
  v_round2_id INT;
  v_prop_x_id INT;
  v_prop_y_id INT;
  v_prop_z_id INT;
BEGIN
  -- Create new round
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::INT, 2, 'rating')
  RETURNING id INTO v_round2_id;

  -- Create three propositions with different timestamps
  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_round2_id, current_setting('test.participant1_id')::INT, 'Proposition X', NOW() - INTERVAL '30 minutes')
  RETURNING id INTO v_prop_x_id;

  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_round2_id, current_setting('test.participant2_id')::INT, 'Proposition Y', NOW() - INTERVAL '20 minutes')
  RETURNING id INTO v_prop_y_id;

  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_round2_id, current_setting('test.participant1_id')::INT, 'Proposition Z', NOW() - INTERVAL '10 minutes')
  RETURNING id INTO v_prop_z_id;

  -- Insert identical scores for all three
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score)
  VALUES
      (v_round2_id, v_prop_x_id, 33.33),
      (v_round2_id, v_prop_y_id, 33.33),
      (v_round2_id, v_prop_z_id, 33.33);

  -- Store IDs
  PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
  PERFORM set_config('test.prop_x_id', v_prop_x_id::TEXT, TRUE);
  PERFORM set_config('test.prop_y_id', v_prop_y_id::TEXT, TRUE);
  PERFORM set_config('test.prop_z_id', v_prop_z_id::TEXT, TRUE);
END $$;

-- Test: All three have scores
SELECT is(
    (SELECT COUNT(*)::INT FROM proposition_global_scores WHERE round_id = current_setting('test.round2_id')::INT),
    3,
    'All three propositions should have global scores'
);

-- Test: Three-way tie-breaker selects oldest (X)
SELECT is(
    test_get_winner_with_tiebreaker(current_setting('test.round2_id')::INT),
    current_setting('test.prop_x_id')::BIGINT,
    'Three-way tie: should select Proposition X (oldest)'
);

-- =============================================================================
-- TEST: MOVDA INTEGRATION (actual algorithm produces scores)
-- =============================================================================

DO $$
DECLARE
  v_round3_id INT;
  v_prop_winner_id INT;
  v_prop_loser_id INT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::INT, 3, 'rating')
  RETURNING id INTO v_round3_id;

  -- Create propositions
  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_round3_id, current_setting('test.participant1_id')::INT, 'Clear Loser', NOW() - INTERVAL '10 minutes')
  RETURNING id INTO v_prop_loser_id;

  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_round3_id, current_setting('test.participant2_id')::INT, 'Clear Winner', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_prop_winner_id;

  -- Both users strongly prefer "Clear Winner"
  INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
  VALUES
    (v_round3_id, v_prop_winner_id, current_setting('test.participant1_id')::INT, 100),
    (v_round3_id, v_prop_loser_id, current_setting('test.participant1_id')::INT, 0),
    (v_round3_id, v_prop_winner_id, current_setting('test.participant2_id')::INT, 100),
    (v_round3_id, v_prop_loser_id, current_setting('test.participant2_id')::INT, 0);

  PERFORM set_config('test.round3_id', v_round3_id::TEXT, TRUE);
  PERFORM set_config('test.prop_winner_id', v_prop_winner_id::TEXT, TRUE);
  PERFORM set_config('test.prop_loser_id', v_prop_loser_id::TEXT, TRUE);
END $$;

SELECT lives_ok(
    format('SELECT calculate_movda_scores_for_round(%s)', current_setting('test.round3_id')),
    'MOVDA calculation should succeed'
);

-- Test: Clear winner has score of 100 (percentile max)
SELECT is(
    (SELECT global_score FROM proposition_global_scores
     WHERE round_id = current_setting('test.round3_id')::INT
     AND proposition_id = current_setting('test.prop_winner_id')::INT),
    100.0::REAL,
    'Clear winner should have score of 100 (percentile max)'
);

-- Test: When no tie, higher-scored proposition wins regardless of age
SELECT is(
    test_get_winner_with_tiebreaker(current_setting('test.round3_id')::INT),
    current_setting('test.prop_winner_id')::BIGINT,
    'MOVDA: Clear winner (newer) wins based on score, not age'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

-- Drop test function
DROP FUNCTION IF EXISTS test_get_winner_with_tiebreaker(BIGINT, REAL);

SELECT * FROM finish();

ROLLBACK;
