-- =============================================================================
-- TEST: User Ranking System
-- =============================================================================
-- Tests for the user ranking calculation system:
-- - Voting accuracy (pairwise comparison against MOVDA scores)
-- - Proposing performance (normalized proposition scores)
-- - Combined round rank ((voting + proposing) / 2)
-- =============================================================================

BEGIN;
SELECT plan(35);

-- =============================================================================
-- SETUP: Create test users and chat
-- =============================================================================

INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
VALUES
  ('b1111111-1111-1111-1111-111111111111', 'rank_host@test.com', 'authenticated', 'authenticated', now(), now()),
  ('b2222222-2222-2222-2222-222222222222', 'rank_user2@test.com', 'authenticated', 'authenticated', now(), now()),
  ('b3333333-3333-3333-3333-333333333333', 'rank_user3@test.com', 'authenticated', 'authenticated', now(), now()),
  ('b4444444-4444-4444-4444-444444444444', 'rank_user4@test.com', 'authenticated', 'authenticated', now(), now());

-- =============================================================================
-- SCHEMA TESTS (6 tests)
-- =============================================================================

-- Test 1: user_voting_ranks table exists
SELECT has_table('public', 'user_voting_ranks', 'user_voting_ranks table should exist');

-- Test 2: user_proposing_ranks table exists
SELECT has_table('public', 'user_proposing_ranks', 'user_proposing_ranks table should exist');

-- Test 3: user_round_ranks table exists
SELECT has_table('public', 'user_round_ranks', 'user_round_ranks table should exist');

-- Test 4: calculate_voting_ranks function exists
SELECT has_function('public', 'calculate_voting_ranks', ARRAY['bigint'], 'calculate_voting_ranks function should exist');

-- Test 5: calculate_proposing_ranks function exists
SELECT has_function('public', 'calculate_proposing_ranks', ARRAY['bigint'], 'calculate_proposing_ranks function should exist');

-- Test 6: store_round_ranks function exists
SELECT has_function('public', 'store_round_ranks', ARRAY['bigint'], 'store_round_ranks function should exist');

-- =============================================================================
-- VOTING RANK TESTS (7 tests)
-- =============================================================================

-- Create test data for voting rank tests
DO $$
DECLARE
  v_chat_id BIGINT;
  v_cycle_id BIGINT;
  v_round_id BIGINT;
  v_host_pid BIGINT;
  v_user2_pid BIGINT;
  v_user3_pid BIGINT;
  v_prop_a_id BIGINT;
  v_prop_b_id BIGINT;
  v_prop_c_id BIGINT;
BEGIN
  -- Create chat with high threshold to prevent auto-advance
  INSERT INTO chats (
    name, initial_message, creator_id, creator_session_token,
    invite_code, access_method, start_mode,
    rating_threshold_count, confirmation_rounds_required
  ) VALUES (
    'User Ranking Test', 'Testing user rankings',
    'b1111111-1111-1111-1111-111111111111',
    'c1111111-1111-1111-1111-111111111111',
    'RANKT1', 'code', 'manual', 999, 2
  ) RETURNING id INTO v_chat_id;

  -- Create cycle and round
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  -- Create participants
  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, 'b1111111-1111-1111-1111-111111111111', 'Host', 'active', true)
  RETURNING id INTO v_host_pid;

  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, 'b2222222-2222-2222-2222-222222222222', 'User2', 'active', false)
  RETURNING id INTO v_user2_pid;

  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, 'b3333333-3333-3333-3333-333333333333', 'User3', 'active', false)
  RETURNING id INTO v_user3_pid;

  -- Create propositions (by host)
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_host_pid, 'Proposition A') RETURNING id INTO v_prop_a_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_host_pid, 'Proposition B') RETURNING id INTO v_prop_b_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_host_pid, 'Proposition C') RETURNING id INTO v_prop_c_id;

  -- Store IDs for later tests
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.host_pid', v_host_pid::TEXT, TRUE);
  PERFORM set_config('test.user2_pid', v_user2_pid::TEXT, TRUE);
  PERFORM set_config('test.user3_pid', v_user3_pid::TEXT, TRUE);
  PERFORM set_config('test.prop_a_id', v_prop_a_id::TEXT, TRUE);
  PERFORM set_config('test.prop_b_id', v_prop_b_id::TEXT, TRUE);
  PERFORM set_config('test.prop_c_id', v_prop_c_id::TEXT, TRUE);

  -- User2 rates: A=100, B=50, C=0 (perfect ordering matching global)
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user2_pid, v_round_id, v_prop_a_id, 100);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user2_pid, v_round_id, v_prop_b_id, 50);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user2_pid, v_round_id, v_prop_c_id, 0);

  -- User3 rates: A=0, B=50, C=100 (opposite ordering)
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user3_pid, v_round_id, v_prop_a_id, 0);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user3_pid, v_round_id, v_prop_b_id, 50);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user3_pid, v_round_id, v_prop_c_id, 100);
END $$;

-- Calculate MOVDA scores first (this sets the global scores)
SELECT calculate_movda_scores_for_round(current_setting('test.round_id')::BIGINT, 0.5);

-- Test 7: Best voter gets 100 (User2 voted A>B>C which matches global - NORMALIZED)
SELECT is(
  (SELECT rank FROM calculate_voting_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.user2_pid')::BIGINT),
  100.0::REAL,
  'Best voter (matching global order) should get 100 (normalized)'
);

-- Test 8: Worst voter gets 0 (User3 voted C>B>A which is opposite - NORMALIZED)
SELECT is(
  (SELECT rank FROM calculate_voting_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.user3_pid')::BIGINT),
  0.0::REAL,
  'Worst voter should get 0 (normalized)'
);

-- Test 9: User who didn't vote has NULL rank (Host didn't vote)
SELECT is(
  (SELECT rank FROM calculate_voting_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.host_pid')::BIGINT),
  NULL::REAL,
  'User who did not vote should have NULL voting rank'
);

-- Test 10: User who only ranked 1 proposition gets 100 (no pairs)
DO $$
DECLARE
  v_round2_id BIGINT;
  v_user4_pid BIGINT;
  v_prop_d_id BIGINT;
BEGIN
  -- Create second round for single-prop test
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 2, 'rating') RETURNING id INTO v_round2_id;

  -- Add user4 participant
  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (current_setting('test.chat_id')::BIGINT, 'b4444444-4444-4444-4444-444444444444', 'User4', 'active', false)
  RETURNING id INTO v_user4_pid;

  -- Create proposition
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round2_id, current_setting('test.host_pid')::BIGINT, 'Proposition D')
  RETURNING id INTO v_prop_d_id;

  -- User4 ranks only one proposition
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user4_pid, v_round2_id, v_prop_d_id, 75);

  PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);
  PERFORM set_config('test.user4_pid', v_user4_pid::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT rank FROM calculate_voting_ranks(current_setting('test.round2_id')::BIGINT)
   WHERE participant_id = current_setting('test.user4_pid')::BIGINT),
  100.0::REAL,
  'User who ranked only 1 proposition should get 100 (no pairs to compare)'
);

-- Test 11: Ties - user A=B, global A=B should be correct
DO $$
DECLARE
  v_round3_id BIGINT;
  v_prop_e_id BIGINT;
  v_prop_f_id BIGINT;
BEGIN
  -- Create round for tie test
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 3, 'rating') RETURNING id INTO v_round3_id;

  -- Create two propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round3_id, current_setting('test.host_pid')::BIGINT, 'Prop E')
  RETURNING id INTO v_prop_e_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round3_id, current_setting('test.host_pid')::BIGINT, 'Prop F')
  RETURNING id INTO v_prop_f_id;

  -- Both users rank them exactly the same (50, 50) - creating a global tie
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user2_pid')::BIGINT, v_round3_id, v_prop_e_id, 50);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user2_pid')::BIGINT, v_round3_id, v_prop_f_id, 50);

  PERFORM set_config('test.round3_id', v_round3_id::TEXT, TRUE);
END $$;

SELECT calculate_movda_scores_for_round(current_setting('test.round3_id')::BIGINT, 0.5);

SELECT is(
  (SELECT rank FROM calculate_voting_ranks(current_setting('test.round3_id')::BIGINT)
   WHERE participant_id = current_setting('test.user2_pid')::BIGINT),
  100.0::REAL,
  'User ranking A=B when global A=B should get 100 (tie is correct)'
);

-- Test 12: correct_pairs and total_pairs are tracked
SELECT ok(
  (SELECT total_pairs FROM calculate_voting_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.user2_pid')::BIGINT) = 3,
  'User with 3 propositions ranked should have 3 pairs (A-B, A-C, B-C)'
);

-- Test 13: Empty round returns no voting ranks
DO $$
DECLARE
  v_round4_id BIGINT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 4, 'rating') RETURNING id INTO v_round4_id;
  PERFORM set_config('test.round4_id', v_round4_id::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT COUNT(*)::INT FROM calculate_voting_ranks(current_setting('test.round4_id')::BIGINT)),
  0,
  'Empty round should return no voting ranks'
);

-- =============================================================================
-- PROPOSING RANK TESTS (6 tests)
-- =============================================================================

-- Test 14: User with multiple propositions gets avg normalized
SELECT ok(
  (SELECT rank FROM calculate_proposing_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.host_pid')::BIGINT) IS NOT NULL,
  'User with propositions should have a proposing rank'
);

-- Test 15: User without propositions has NULL rank
SELECT is(
  (SELECT rank FROM calculate_proposing_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.user2_pid')::BIGINT),
  NULL::REAL,
  'User without propositions should have NULL proposing rank'
);

-- Test 16: Carryover propositions are excluded
DO $$
DECLARE
  v_round5_id BIGINT;
  v_prop_g_id BIGINT;
  v_prop_carried_id BIGINT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 5, 'rating') RETURNING id INTO v_round5_id;

  -- Original proposition
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round5_id, current_setting('test.user2_pid')::BIGINT, 'Original Prop G')
  RETURNING id INTO v_prop_g_id;

  -- Carryover proposition (should be excluded from proposing rank)
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round5_id, current_setting('test.user2_pid')::BIGINT, 'Carried Prop', v_prop_g_id)
  RETURNING id INTO v_prop_carried_id;

  PERFORM set_config('test.round5_id', v_round5_id::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT proposition_count FROM calculate_proposing_ranks(current_setting('test.round5_id')::BIGINT)
   WHERE participant_id = current_setting('test.user2_pid')::BIGINT),
  1,
  'Carryover propositions should be excluded - only 1 original counted'
);

-- Test 17: Single user with propositions gets 100
DO $$
DECLARE
  v_round6_id BIGINT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 6, 'rating') RETURNING id INTO v_round6_id;

  -- Only one user has propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round6_id, current_setting('test.host_pid')::BIGINT, 'Solo Prop');

  PERFORM set_config('test.round6_id', v_round6_id::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT rank FROM calculate_proposing_ranks(current_setting('test.round6_id')::BIGINT)
   WHERE participant_id = current_setting('test.host_pid')::BIGINT),
  100.0::REAL,
  'Single user with propositions gets 100 (only proposer)'
);

-- Test 18: avg_score is calculated correctly
SELECT ok(
  (SELECT avg_score FROM calculate_proposing_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.host_pid')::BIGINT) IS NOT NULL,
  'avg_score should be calculated for proposers'
);

-- Test 19: proposition_count tracks count
SELECT is(
  (SELECT proposition_count FROM calculate_proposing_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.host_pid')::BIGINT),
  3,
  'proposition_count should track number of propositions (3 for host)'
);

-- =============================================================================
-- COMBINED RANK TESTS (4 tests) - With Triple Normalization
-- =============================================================================

-- Test 20: Combined rank is normalized (best = 100, worst = 0)
DO $$
DECLARE
  v_round7_id BIGINT;
  v_prop_h_id BIGINT;
  v_prop_i_id BIGINT;
  v_prop_j_id BIGINT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 7, 'rating') RETURNING id INTO v_round7_id;

  -- Host, User2, and User3 all create propositions (for normalization to work)
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round7_id, current_setting('test.host_pid')::BIGINT, 'Prop H')
  RETURNING id INTO v_prop_h_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round7_id, current_setting('test.user2_pid')::BIGINT, 'Prop I')
  RETURNING id INTO v_prop_i_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round7_id, current_setting('test.user3_pid')::BIGINT, 'Prop J')
  RETURNING id INTO v_prop_j_id;

  -- User2 votes: H=100, I=50, J=0 (matches global order → best voter)
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user2_pid')::BIGINT, v_round7_id, v_prop_h_id, 100);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user2_pid')::BIGINT, v_round7_id, v_prop_i_id, 50);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user2_pid')::BIGINT, v_round7_id, v_prop_j_id, 0);

  -- User3 votes: H=0, I=50, J=100 (opposite of global → worst voter)
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user3_pid')::BIGINT, v_round7_id, v_prop_h_id, 0);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user3_pid')::BIGINT, v_round7_id, v_prop_i_id, 50);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user3_pid')::BIGINT, v_round7_id, v_prop_j_id, 100);

  PERFORM set_config('test.round7_id', v_round7_id::TEXT, TRUE);
END $$;

SELECT calculate_movda_scores_for_round(current_setting('test.round7_id')::BIGINT, 0.5);

-- Best performer gets 100 (normalized combined rank)
SELECT is(
  (SELECT MAX(crr.rank) FROM calculate_round_ranks(current_setting('test.round7_id')::BIGINT) crr),
  100.0::REAL,
  'Best performer should get normalized rank of 100'
);

-- Test 21: Worst performer gets 0 (normalized combined rank)
SELECT is(
  (SELECT MIN(crr.rank) FROM calculate_round_ranks(current_setting('test.round7_id')::BIGINT) crr),
  0.0::REAL,
  'Worst performer should get normalized rank of 0'
);

-- Test 22: voting_rank and proposing_rank are preserved (not normalized in output)
SELECT ok(
  (SELECT crr.voting_rank IS NOT NULL OR crr.proposing_rank IS NOT NULL
   FROM calculate_round_ranks(current_setting('test.round7_id')::BIGINT) crr
   LIMIT 1),
  'voting_rank and proposing_rank should be preserved in output'
);

-- Test 23: Neither voting nor proposing → not inserted
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM calculate_round_ranks(current_setting('test.round4_id')::BIGINT)
  ),
  'User who neither voted nor proposed should not appear in round ranks'
);

-- =============================================================================
-- INTEGRATION TESTS (4 tests)
-- =============================================================================

-- Test 24: store_round_ranks populates all tables
SELECT store_round_ranks(current_setting('test.round_id')::BIGINT);

SELECT ok(
  (SELECT COUNT(*) FROM user_voting_ranks WHERE round_id = current_setting('test.round_id')::BIGINT) > 0,
  'store_round_ranks should populate user_voting_ranks'
);

-- Test 25: store_round_ranks populates user_proposing_ranks
SELECT ok(
  (SELECT COUNT(*) FROM user_proposing_ranks WHERE round_id = current_setting('test.round_id')::BIGINT) > 0,
  'store_round_ranks should populate user_proposing_ranks'
);

-- Test 26: store_round_ranks populates user_round_ranks
SELECT ok(
  (SELECT COUNT(*) FROM user_round_ranks WHERE round_id = current_setting('test.round_id')::BIGINT) > 0,
  'store_round_ranks should populate user_round_ranks'
);

-- Test 27: Idempotent (calling twice = same result)
DO $$
DECLARE
  v_count_before INT;
  v_count_after INT;
BEGIN
  SELECT COUNT(*) INTO v_count_before FROM user_round_ranks WHERE round_id = current_setting('test.round_id')::BIGINT;
  PERFORM store_round_ranks(current_setting('test.round_id')::BIGINT);
  SELECT COUNT(*) INTO v_count_after FROM user_round_ranks WHERE round_id = current_setting('test.round_id')::BIGINT;

  IF v_count_before = v_count_after THEN
    RAISE NOTICE 'Idempotent check passed: before=%, after=%', v_count_before, v_count_after;
  ELSE
    RAISE EXCEPTION 'Idempotent check FAILED: before=%, after=%', v_count_before, v_count_after;
  END IF;
END $$;

SELECT pass('store_round_ranks is idempotent (calling twice produces same count)');

-- =============================================================================
-- COMPLETE_ROUND_WITH_WINNER INTEGRATION (4 tests)
-- =============================================================================

-- Create a fresh round for complete_round_with_winner test
DO $$
DECLARE
  v_round8_id BIGINT;
  v_prop_j_id BIGINT;
  v_prop_k_id BIGINT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 8, 'rating') RETURNING id INTO v_round8_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round8_id, current_setting('test.host_pid')::BIGINT, 'Prop J')
  RETURNING id INTO v_prop_j_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round8_id, current_setting('test.user2_pid')::BIGINT, 'Prop K')
  RETURNING id INTO v_prop_k_id;

  -- Add ratings
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user2_pid')::BIGINT, v_round8_id, v_prop_j_id, 100);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user2_pid')::BIGINT, v_round8_id, v_prop_k_id, 0);

  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user3_pid')::BIGINT, v_round8_id, v_prop_j_id, 80);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (current_setting('test.user3_pid')::BIGINT, v_round8_id, v_prop_k_id, 20);

  PERFORM set_config('test.round8_id', v_round8_id::TEXT, TRUE);
END $$;

-- Test 28: user_round_ranks empty before complete_round_with_winner
SELECT is(
  (SELECT COUNT(*)::INT FROM user_round_ranks WHERE round_id = current_setting('test.round8_id')::BIGINT),
  0,
  'user_round_ranks should be empty before complete_round_with_winner'
);

-- Call complete_round_with_winner
SELECT complete_round_with_winner(current_setting('test.round8_id')::BIGINT);

-- Test 29: complete_round_with_winner triggers user ranking calculation
SELECT ok(
  (SELECT COUNT(*) FROM user_round_ranks WHERE round_id = current_setting('test.round8_id')::BIGINT) > 0,
  'complete_round_with_winner should populate user_round_ranks'
);

-- Test 30: Voting ranks are populated by complete_round_with_winner
SELECT ok(
  (SELECT COUNT(*) FROM user_voting_ranks WHERE round_id = current_setting('test.round8_id')::BIGINT) > 0,
  'complete_round_with_winner should populate user_voting_ranks'
);

-- Test 31: Proposing ranks are populated by complete_round_with_winner
SELECT ok(
  (SELECT COUNT(*) FROM user_proposing_ranks WHERE round_id = current_setting('test.round8_id')::BIGINT) > 0,
  'complete_round_with_winner should populate user_proposing_ranks'
);

-- =============================================================================
-- EDGE CASE TESTS (4 tests)
-- =============================================================================

-- Test 32: Round with no ratings (but has propositions)
DO $$
DECLARE
  v_round9_id BIGINT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 99, 'rating') RETURNING id INTO v_round9_id;

  -- Create proposition but no ratings
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round9_id, current_setting('test.host_pid')::BIGINT, 'Unrated Prop');

  PERFORM set_config('test.round9_id', v_round9_id::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT COUNT(*)::INT FROM calculate_voting_ranks(current_setting('test.round9_id')::BIGINT)),
  0,
  'Round with no ratings should have no voting ranks'
);

-- Test 33: Round with no propositions
DO $$
DECLARE
  v_round10_id BIGINT;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (current_setting('test.cycle_id')::BIGINT, 100, 'rating') RETURNING id INTO v_round10_id;
  PERFORM set_config('test.round10_id', v_round10_id::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT COUNT(*)::INT FROM calculate_proposing_ranks(current_setting('test.round10_id')::BIGINT)),
  0,
  'Round with no propositions should have no proposing ranks'
);

-- Test 34: Multiple propositions per user with varying scores
SELECT ok(
  (SELECT proposition_count = 3 AND avg_score IS NOT NULL
   FROM calculate_proposing_ranks(current_setting('test.round_id')::BIGINT)
   WHERE participant_id = current_setting('test.host_pid')::BIGINT),
  'User with multiple propositions should have accurate count and avg_score'
);

-- Test 35: Rank values are within valid range (0-100)
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM user_round_ranks
    WHERE round_id = current_setting('test.round_id')::BIGINT
    AND (rank < 0 OR rank > 100)
  ),
  'All round ranks should be between 0 and 100'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
