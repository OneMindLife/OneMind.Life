-- =============================================================================
-- Test: matches-mode (pairwise) voters are SCORED by calculate_voting_ranks.
-- Migration: 20260628131620_pairwise_voter_scoring.sql
-- =============================================================================
-- Background / bug this locks in:
--   calculate_voting_ranks(round_id) historically read ONLY grid_rankings, so
--   in matches (pairwise) rating mode — where votes live in
--   pairwise_comparisons and grid_rankings is empty — voters got no
--   voting_rank. The leaderboard then showed only proposers; pure voters were
--   unranked forever.
--
--   The new function scores pairwise voters too: a non-skip comparison is
--   "correct" when the chosen winner's global_score >= the loser's; a tie is
--   correct when the two scores are within epsilon. accuracy is normalized
--   across all voters exactly like the grid path, so the calculate_round_ranks
--   combine keeps working unchanged.
--
-- Fixture (matches mode, 3 propositions, global scores A=90 > B=50 > C=10):
--   P1  — proposes A AND votes (the proposer-who-also-voted): 2/3 correct
--   P2  — proposes B (no votes)
--   P3  — proposes C (no votes)
--   V_acc — vote-only, perfectly accurate: A>B, A>C, B>C → 3/3
--   V_bad — vote-only, perfectly wrong: B>A, C>A, C>B → 0/3
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

-- =============================================================================
-- SETUP
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Pairwise Voter Scoring Test', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1 INT; v_p2 INT; v_p3 INT; v_vacc INT; v_vbad INT;
  v_prop_a INT; v_prop_b INT; v_prop_c INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Pairwise Voter Scoring Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  -- Three proposers + two vote-only participants.
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P2', FALSE, 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'P3', FALSE, 'active') RETURNING id INTO v_p3;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'V_acc', FALSE, 'active') RETURNING id INTO v_vacc;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), 'V_bad', FALSE, 'active') RETURNING id INTO v_vbad;

  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1, 'Idea A') RETURNING id INTO v_prop_a;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2, 'Idea B') RETURNING id INTO v_prop_b;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3, 'Idea C') RETURNING id INTO v_prop_c;

  -- Final consensus scores: A best, C worst. (Insert directly so the test does
  -- not depend on the MOVDA blend; calculate_voting_ranks reads these.)
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score) VALUES
    (v_round_id, v_prop_a, 90.0),
    (v_round_id, v_prop_b, 50.0),
    (v_round_id, v_prop_c, 10.0);

  -- V_acc — perfectly accurate (chosen winner always >= loser): 3/3.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES
    (v_round_id, v_vacc, v_prop_a, v_prop_b),
    (v_round_id, v_vacc, v_prop_a, v_prop_c),
    (v_round_id, v_vacc, v_prop_b, v_prop_c);

  -- V_bad — perfectly wrong (chosen winner always < loser): 0/3.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES
    (v_round_id, v_vbad, v_prop_b, v_prop_a),
    (v_round_id, v_vbad, v_prop_c, v_prop_a),
    (v_round_id, v_vbad, v_prop_c, v_prop_b);

  -- P1 — proposer who also votes: A>B (ok), A>C (ok), C>B (wrong) → 2/3.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES
    (v_round_id, v_p1, v_prop_a, v_prop_b),
    (v_round_id, v_p1, v_prop_a, v_prop_c),
    (v_round_id, v_p1, v_prop_c, v_prop_b);

  PERFORM set_config('test.pv.round',  v_round_id::TEXT, TRUE);
  PERFORM set_config('test.pv.p1',     v_p1::TEXT, TRUE);
  PERFORM set_config('test.pv.vacc',   v_vacc::TEXT, TRUE);
  PERFORM set_config('test.pv.vbad',   v_vbad::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: precondition — no voting ranks stored yet.
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM user_voting_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT),
  0,
  '1: user_voting_ranks empty before store_round_ranks'
);

-- =============================================================================
-- Test 2: the full ranking pipeline runs without error.
-- store_round_ranks → calculate_voting_ranks + calculate_proposing_ranks
--                    + calculate_round_ranks, then persists all three tables.
-- =============================================================================
SELECT lives_ok(
  $$SELECT store_round_ranks(current_setting('test.pv.round')::BIGINT)$$,
  '2: store_round_ranks runs the matches-mode pipeline without error'
);

-- =============================================================================
-- Tests 3-5: every pairwise voter receives a non-null voting_rank.
-- =============================================================================
SELECT ok(
  (SELECT rank FROM user_voting_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.vacc')::BIGINT) IS NOT NULL,
  '3: accurate pairwise voter gets a non-null voting_rank'
);
SELECT ok(
  (SELECT rank FROM user_voting_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.vbad')::BIGINT) IS NOT NULL,
  '4: inaccurate pairwise voter gets a non-null voting_rank'
);
SELECT ok(
  (SELECT rank FROM user_voting_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.p1')::BIGINT) IS NOT NULL,
  '5: proposer who also voted gets a non-null voting_rank'
);

-- =============================================================================
-- Test 6: the accurate voter outranks the inaccurate one.
-- =============================================================================
SELECT cmp_ok(
  (SELECT rank FROM user_voting_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.vacc')::BIGINT),
  '>',
  (SELECT rank FROM user_voting_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.vbad')::BIGINT),
  '6: accurate voter''s voting_rank > inaccurate voter''s voting_rank'
);

-- =============================================================================
-- Test 7: normalization — best voter in the round = 100.
-- =============================================================================
SELECT is(
  (SELECT rank FROM user_voting_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.vacc')::BIGINT),
  100.0::REAL,
  '7: perfectly accurate voter normalizes to 100'
);

-- =============================================================================
-- Test 8: a VOTE-ONLY participant gets a final combined round rank.
-- (This is the core regression: pre-fix, V_acc had no voting_rank and so no
--  user_round_ranks row at all.)
-- =============================================================================
SELECT ok(
  (SELECT rank FROM user_round_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.vacc')::BIGINT) IS NOT NULL,
  '8: vote-only participant gets a non-null final round rank'
);

-- =============================================================================
-- Test 9: that vote-only participant has NO proposing_rank (didn't propose).
-- =============================================================================
SELECT ok(
  (SELECT proposing_rank FROM user_round_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND participant_id = current_setting('test.pv.vacc')::BIGINT) IS NULL,
  '9: vote-only participant has a NULL proposing_rank'
);

-- =============================================================================
-- Test 10: proposers still receive proposing_rank — the proposing path is
-- untouched. All three proposers (P1, P2, P3) have non-null proposing ranks.
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM user_proposing_ranks
   WHERE round_id = current_setting('test.pv.round')::BIGINT
     AND rank IS NOT NULL),
  3,
  '10: all three proposers still get a non-null proposing_rank'
);

SELECT * FROM finish();
ROLLBACK;
