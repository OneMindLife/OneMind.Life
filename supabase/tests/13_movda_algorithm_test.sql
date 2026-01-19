-- =============================================================================
-- TEST: MOVDA Algorithm and Grid Rankings
-- =============================================================================
-- Tests for the MOVDA (Margin of Victory Diminishing Adjustments) scoring system
-- including grid rankings, score calculation, and helper functions.
-- =============================================================================

BEGIN;

SELECT plan(40);

-- =============================================================================
-- SCHEMA TESTS
-- =============================================================================

-- Test: movda_config table exists
SELECT has_table('public', 'movda_config', 'movda_config table should exist');

-- Test: proposition_movda_ratings table exists
SELECT has_table('public', 'proposition_movda_ratings', 'proposition_movda_ratings table should exist');

-- Test: grid_rankings table exists
SELECT has_table('public', 'grid_rankings', 'grid_rankings table should exist');

-- Test: proposition_global_scores table exists
SELECT has_table('public', 'proposition_global_scores', 'proposition_global_scores table should exist');

-- Test: movda_config has required columns
SELECT has_column('public', 'movda_config', 'k_factor', 'movda_config should have k_factor column');
SELECT has_column('public', 'movda_config', 'tau', 'movda_config should have tau column');
SELECT has_column('public', 'movda_config', 'gamma', 'movda_config should have gamma column');
SELECT has_column('public', 'movda_config', 'initial_rating', 'movda_config should have initial_rating column');

-- Test: grid_rankings has required columns
SELECT has_column('public', 'grid_rankings', 'participant_id', 'grid_rankings should have participant_id');
SELECT has_column('public', 'grid_rankings', 'session_token', 'grid_rankings should have session_token');
SELECT has_column('public', 'grid_rankings', 'round_id', 'grid_rankings should have round_id');
SELECT has_column('public', 'grid_rankings', 'proposition_id', 'grid_rankings should have proposition_id');
SELECT has_column('public', 'grid_rankings', 'grid_position', 'grid_rankings should have grid_position');

-- =============================================================================
-- MOVDA CONFIG SINGLETON TESTS
-- =============================================================================

-- Test: Default config exists
SELECT is(
    (SELECT COUNT(*) FROM movda_config),
    1::BIGINT,
    'movda_config should have exactly one row'
);

-- Test: Default values are correct
SELECT is(
    (SELECT k_factor FROM movda_config LIMIT 1),
    32.0::REAL,
    'Default k_factor should be 32.0'
);

SELECT is(
    (SELECT tau FROM movda_config LIMIT 1),
    400.0::REAL,
    'Default tau should be 400.0'
);

SELECT is(
    (SELECT gamma FROM movda_config LIMIT 1),
    100.0::REAL,
    'Default gamma should be 100.0'
);

SELECT is(
    (SELECT initial_rating FROM movda_config LIMIT 1),
    1500.0::REAL,
    'Default initial_rating should be 1500.0'
);

-- Test: Cannot insert second config row (singleton)
SELECT throws_ok(
    $$INSERT INTO movda_config (k_factor, tau, gamma, initial_rating, singleton) VALUES (16.0, 200.0, 50.0, 1000.0, TRUE)$$,
    '23505',  -- unique_violation
    NULL,
    'Should not allow second movda_config row'
);

-- =============================================================================
-- GRID RANKINGS CONSTRAINT TESTS
-- =============================================================================

-- Create test data for constraint tests using session tokens (like other tests)
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('MOVDA Test Chat', 'Testing MOVDA algorithm', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant_id INT;
  v_participant2_id INT;
  v_participant3_id INT;
  v_prop1_id INT;
  v_prop2_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'MOVDA Test Chat';

  -- Create cycle
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- Create round in rating phase
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating')
  RETURNING id INTO v_round_id;

  -- Create participants
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'User 1', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'User 2', FALSE, 'active')
  RETURNING id INTO v_participant2_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'User 3', FALSE, 'active')
  RETURNING id INTO v_participant3_id;

  -- Create propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_id, 'Test proposition 1')
  RETURNING id INTO v_prop1_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant_id, 'Test proposition 2')
  RETURNING id INTO v_prop2_id;

  -- Store IDs for later tests
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.participant_id', v_participant_id::TEXT, TRUE);
  PERFORM set_config('test.participant2_id', v_participant2_id::TEXT, TRUE);
  PERFORM set_config('test.participant3_id', v_participant3_id::TEXT, TRUE);
  PERFORM set_config('test.prop1_id', v_prop1_id::TEXT, TRUE);
  PERFORM set_config('test.prop2_id', v_prop2_id::TEXT, TRUE);
END $$;

-- Test: grid_position must be >= 0
SELECT throws_ok(
    format('INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position) VALUES (%s, %s, %s, -1)',
           current_setting('test.round_id'), current_setting('test.prop1_id'), current_setting('test.participant_id')),
    '23514',  -- check_violation
    NULL,
    'grid_position should not allow values below 0'
);

-- Test: grid_position must be <= 100
SELECT throws_ok(
    format('INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position) VALUES (%s, %s, %s, 101)',
           current_setting('test.round_id'), current_setting('test.prop1_id'), current_setting('test.participant_id')),
    '23514',  -- check_violation
    NULL,
    'grid_position should not allow values above 100'
);

-- Test: Valid grid_position at 0 is allowed
SELECT lives_ok(
    format('INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position) VALUES (%s, %s, %s, 0)',
           current_setting('test.round_id'), current_setting('test.prop1_id'), current_setting('test.participant2_id')),
    'grid_position of 0 should be allowed'
);

-- Test: Valid grid_position at 100 is allowed
SELECT lives_ok(
    format('INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position) VALUES (%s, %s, %s, 100)',
           current_setting('test.round_id'), current_setting('test.prop2_id'), current_setting('test.participant2_id')),
    'grid_position of 100 should be allowed'
);

-- Test: Must have either participant_id or session_token
SELECT throws_ok(
    format('INSERT INTO grid_rankings (round_id, proposition_id, participant_id, session_token, grid_position) VALUES (%s, %s, NULL, NULL, 50)',
           current_setting('test.round_id'), current_setting('test.prop1_id')),
    '23514',  -- check_violation
    NULL,
    'Must have either participant_id or session_token'
);

-- Test: Can use session_token for anonymous users
SELECT lives_ok(
    format('INSERT INTO grid_rankings (round_id, proposition_id, session_token, grid_position) VALUES (%s, %s, gen_random_uuid(), 50)',
           current_setting('test.round_id'), current_setting('test.prop1_id')),
    'session_token should work for anonymous users'
);

-- =============================================================================
-- MOVDA CALCULATION TESTS
-- =============================================================================

-- Note: MOVDA trigger was removed (it's now called only at phase end)
-- We test manual calculation via calculate_movda_scores_for_round()

-- Clean up existing grid rankings
DELETE FROM grid_rankings WHERE round_id = current_setting('test.round_id')::INT;
DELETE FROM proposition_global_scores WHERE round_id = current_setting('test.round_id')::INT;
DELETE FROM proposition_movda_ratings WHERE round_id = current_setting('test.round_id')::INT;

-- Create a third proposition for MOVDA tests
DO $$
DECLARE
  v_prop3_id INT;
BEGIN
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (current_setting('test.round_id')::INT, current_setting('test.participant_id')::INT, 'Test proposition 3')
  RETURNING id INTO v_prop3_id;
  PERFORM set_config('test.prop3_id', v_prop3_id::TEXT, TRUE);
END $$;

-- User 2 ranks: prop1=100, prop2=50, prop3=0
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round_id')::INT, current_setting('test.prop1_id')::INT, current_setting('test.participant2_id')::INT, 100;
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round_id')::INT, current_setting('test.prop2_id')::INT, current_setting('test.participant2_id')::INT, 50;
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round_id')::INT, current_setting('test.prop3_id')::INT, current_setting('test.participant2_id')::INT, 0;

-- User 3 ranks: prop1=80, prop2=60, prop3=20
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round_id')::INT, current_setting('test.prop1_id')::INT, current_setting('test.participant3_id')::INT, 80;
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round_id')::INT, current_setting('test.prop2_id')::INT, current_setting('test.participant3_id')::INT, 60;
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round_id')::INT, current_setting('test.prop3_id')::INT, current_setting('test.participant3_id')::INT, 20;

-- Test: MOVDA calculation creates ratings
SELECT lives_ok(
    format('SELECT calculate_movda_scores_for_round(%s, 0.5)', current_setting('test.round_id')),
    'calculate_movda_scores_for_round should execute successfully'
);

-- Test: Ratings were created for all propositions
SELECT is(
    (SELECT COUNT(*) FROM proposition_movda_ratings WHERE round_id = current_setting('test.round_id')::INT),
    3::BIGINT,
    'Should create ratings for all 3 propositions'
);

-- Test: Global scores were created
SELECT is(
    (SELECT COUNT(*) FROM proposition_global_scores WHERE round_id = current_setting('test.round_id')::INT),
    3::BIGINT,
    'Should create global scores for all 3 propositions'
);

-- Test: Global scores are in valid range (0-100)
SELECT ok(
    (SELECT MIN(global_score) >= 0 AND MAX(global_score) <= 100
     FROM proposition_global_scores WHERE round_id = current_setting('test.round_id')::INT),
    'Global scores should be in range 0-100'
);

-- Test: Highest ranked proposition has highest score
-- prop1 was ranked highest by both users
SELECT ok(
    (SELECT proposition_id FROM proposition_global_scores
     WHERE round_id = current_setting('test.round_id')::INT ORDER BY global_score DESC LIMIT 1) = current_setting('test.prop1_id')::INT,
    'Proposition 1 should have highest score (ranked best by all users)'
);

-- Test: Lowest ranked proposition has lowest score
-- prop3 was ranked lowest by both users
SELECT ok(
    (SELECT proposition_id FROM proposition_global_scores
     WHERE round_id = current_setting('test.round_id')::INT ORDER BY global_score ASC LIMIT 1) = current_setting('test.prop3_id')::INT,
    'Proposition 3 should have lowest score (ranked worst by all users)'
);

-- Test: Score spread covers full range (normalization)
SELECT ok(
    (SELECT MAX(global_score) - MIN(global_score) > 50
     FROM proposition_global_scores WHERE round_id = current_setting('test.round_id')::INT),
    'Score spread should be significant after normalization'
);

-- =============================================================================
-- HELPER FUNCTION TESTS
-- =============================================================================

-- Test: get_propositions_with_scores returns correct data
SELECT is(
    (SELECT COUNT(*) FROM get_propositions_with_scores(current_setting('test.round_id')::INT)),
    3::BIGINT,
    'get_propositions_with_scores should return all 3 propositions'
);

-- Test: get_propositions_with_scores includes rank
SELECT ok(
    (SELECT rank FROM get_propositions_with_scores(current_setting('test.round_id')::INT)
     WHERE proposition_id = current_setting('test.prop1_id')::INT) = 1,
    'Highest scored proposition should have rank 1'
);

-- Test: get_unranked_propositions returns correct data
-- User 1 (participant_id=1) hasn't ranked any propositions
SELECT is(
    (SELECT COUNT(*) FROM get_unranked_propositions(current_setting('test.round_id')::INT, current_setting('test.participant_id')::INT, NULL)),
    0::BIGINT,  -- User 1 created all propositions, so none to rank (excludes own)
    'get_unranked_propositions should exclude own propositions'
);

-- Test: get_unranked_propositions excludes already ranked
-- User 2 has ranked all propositions
SELECT is(
    (SELECT COUNT(*) FROM get_unranked_propositions(current_setting('test.round_id')::INT, current_setting('test.participant2_id')::INT, NULL)),
    0::BIGINT,
    'get_unranked_propositions should return 0 when all are ranked'
);

-- =============================================================================
-- EDGE CASE TESTS
-- =============================================================================

-- Create a new round for edge case tests
DO $$
DECLARE
  v_round2_id INT;
  v_prop4_id INT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::INT, 2, 'rating')
  RETURNING id INTO v_round2_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round2_id, current_setting('test.participant_id')::INT, 'Edge case prop 1')
  RETURNING id INTO v_prop4_id;

  PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
  PERFORM set_config('test.prop4_id', v_prop4_id::TEXT, TRUE);
END $$;

-- Test: MOVDA with single proposition
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round2_id')::INT, current_setting('test.prop4_id')::INT, current_setting('test.participant2_id')::INT, 50;

SELECT lives_ok(
    format('SELECT calculate_movda_scores_for_round(%s, 0.5)', current_setting('test.round2_id')),
    'MOVDA should handle single proposition'
);

-- Test: Single proposition - no comparisons means no scores (expected)
SELECT is(
    (SELECT COUNT(*) FROM proposition_global_scores
     WHERE round_id = current_setting('test.round2_id')::INT),
    0::BIGINT,
    'Single proposition with no comparisons should have no scores (no pairwise data)'
);

-- Test: MOVDA with tied rankings
DO $$
DECLARE
  v_round3_id INT;
  v_prop5_id INT;
  v_prop6_id INT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::INT, 3, 'rating')
  RETURNING id INTO v_round3_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round3_id, current_setting('test.participant_id')::INT, 'Tied prop 1')
  RETURNING id INTO v_prop5_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round3_id, current_setting('test.participant_id')::INT, 'Tied prop 2')
  RETURNING id INTO v_prop6_id;

  PERFORM set_config('test.round3_id', v_round3_id::TEXT, TRUE);
  PERFORM set_config('test.prop5_id', v_prop5_id::TEXT, TRUE);
  PERFORM set_config('test.prop6_id', v_prop6_id::TEXT, TRUE);
END $$;

-- Both users rank them the same
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round3_id')::INT, current_setting('test.prop5_id')::INT, current_setting('test.participant2_id')::INT, 50;
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round3_id')::INT, current_setting('test.prop6_id')::INT, current_setting('test.participant2_id')::INT, 50;
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round3_id')::INT, current_setting('test.prop5_id')::INT, current_setting('test.participant3_id')::INT, 50;
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
SELECT current_setting('test.round3_id')::INT, current_setting('test.prop6_id')::INT, current_setting('test.participant3_id')::INT, 50;

SELECT lives_ok(
    format('SELECT calculate_movda_scores_for_round(%s, 0.5)', current_setting('test.round3_id')),
    'MOVDA should handle tied rankings'
);

-- Test: Tied propositions - no comparisons when all at same position (no winner/loser)
SELECT is(
    (SELECT COUNT(*) FROM proposition_global_scores WHERE round_id = current_setting('test.round3_id')::INT),
    0::BIGINT,
    'Tied propositions at same position have no pairwise comparisons (no scores)'
);

-- =============================================================================
-- TRIGGER TESTS - REMOVED
-- =============================================================================
-- Note: The MOVDA trigger (trg_recalculate_movda_on_grid_insert) was removed.
-- MOVDA scores are now calculated only at rating phase end via:
-- - process-timers edge function (timer expiry)
-- - ChatService.completeRatingPhase() (manual advance)
-- This eliminates redundant calculations during active rating.

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();

ROLLBACK;
