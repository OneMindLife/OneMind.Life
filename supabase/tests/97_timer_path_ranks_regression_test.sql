-- Test: timer-based round completion must persist user_round_ranks.
--
-- Background / bug this locks in:
--   Two code paths complete a round:
--     1. Early-advance trigger → SQL `complete_round_with_winner`
--        (correctly calls `store_round_ranks`)
--     2. Timer expiry → `calculateWinnerAndComplete` in
--        `supabase/functions/process-timers/index.ts`
--        (historically did NOT call `store_round_ranks` — so rounds that
--         ended exactly at phase_ends_at had zero per-user ranks and the
--         leaderboard showed most participants as unranked forever).
--
--   Fix: edge function now calls `supabase.rpc('store_round_ranks', ...)`
--   after the round update. We can't run Deno here, but we can lock in
--   the SQL contracts the edge function relies on:
--     * `store_round_ranks(p_round_id)` by itself populates all three
--       per-user rank tables when called against a completed round.
--     * `complete_round_with_winner(p_round_id)` does the same end-to-end.
--     * Both are idempotent (safe to re-run / backfill).

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- =============================================================================
-- Fixture: 2-proposition round with ratings from 2 participants
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Timer Path Ranks Test', 'Q', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_for_store INT;
  v_round_for_complete INT;
  v_pa INT;
  v_pb INT;
  v_prop_a_store INT;
  v_prop_b_store INT;
  v_prop_a_complete INT;
  v_prop_b_complete INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Timer Path Ranks Test';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- Two independent rounds: one exercised with store_round_ranks alone
  -- (the edge-function path contract), one with complete_round_with_winner
  -- (the trigger path contract).
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating')
  RETURNING id INTO v_round_for_store;

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 2, 'rating')
  RETURNING id INTO v_round_for_complete;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Alice', TRUE, 'active')
  RETURNING id INTO v_pa;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Bob', FALSE, 'active')
  RETURNING id INTO v_pb;

  -- Round 1 propositions: one author each so the proposing rank has both.
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_for_store, v_pa, 'A idea 1')
  RETURNING id INTO v_prop_a_store;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_for_store, v_pb, 'B idea 1')
  RETURNING id INTO v_prop_b_store;

  -- Round 2 propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_for_complete, v_pa, 'A idea 2')
  RETURNING id INTO v_prop_a_complete;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_for_complete, v_pb, 'B idea 2')
  RETURNING id INTO v_prop_b_complete;

  -- Each rates the other's proposition so calculate_voting_ranks has pairs.
  -- Round 1:
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_pa, v_round_for_store, v_prop_b_store, 80);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_pb, v_round_for_store, v_prop_a_store, 30);

  -- Round 2:
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_pa, v_round_for_complete, v_prop_b_complete, 70);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_pb, v_round_for_complete, v_prop_a_complete, 40);

  -- Round 1: pre-compute MOVDA so store_round_ranks has scores to work with
  -- (mimics the edge-function timer path: movda runs FIRST, then ranks).
  PERFORM calculate_movda_scores_for_round(v_round_for_store);

  PERFORM set_config('test.round_store', v_round_for_store::TEXT, TRUE);
  PERFORM set_config('test.round_complete', v_round_for_complete::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: precondition — rank tables are empty before we call anything
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM user_round_ranks
   WHERE round_id = current_setting('test.round_store')::BIGINT),
  0,
  'user_round_ranks empty before store_round_ranks'
);

-- =============================================================================
-- Test 2: store_round_ranks(p_round_id) populates user_round_ranks.
--         This is exactly the contract the edge function now relies on.
-- =============================================================================
SELECT lives_ok(
  $$SELECT store_round_ranks(current_setting('test.round_store')::BIGINT)$$,
  'store_round_ranks runs without error'
);

SELECT cmp_ok(
  (SELECT COUNT(*)::INT FROM user_round_ranks
   WHERE round_id = current_setting('test.round_store')::BIGINT),
  '>', 0,
  'store_round_ranks populates user_round_ranks'
);

SELECT cmp_ok(
  (SELECT COUNT(*)::INT FROM user_voting_ranks
   WHERE round_id = current_setting('test.round_store')::BIGINT),
  '>', 0,
  'store_round_ranks populates user_voting_ranks'
);

SELECT cmp_ok(
  (SELECT COUNT(*)::INT FROM user_proposing_ranks
   WHERE round_id = current_setting('test.round_store')::BIGINT),
  '>', 0,
  'store_round_ranks populates user_proposing_ranks'
);

-- =============================================================================
-- Test 6: store_round_ranks is idempotent — safe backfill / replay.
--         ON CONFLICT DO UPDATE means re-running doesn't create duplicates.
-- =============================================================================
DO $$
DECLARE
  v_count_before INT;
  v_count_after INT;
BEGIN
  SELECT COUNT(*) INTO v_count_before FROM user_round_ranks
  WHERE round_id = current_setting('test.round_store')::BIGINT;
  PERFORM store_round_ranks(current_setting('test.round_store')::BIGINT);
  SELECT COUNT(*) INTO v_count_after FROM user_round_ranks
  WHERE round_id = current_setting('test.round_store')::BIGINT;
  PERFORM set_config('test.idempotent', (v_count_before = v_count_after)::TEXT, TRUE);
END $$;

SELECT is(
  current_setting('test.idempotent')::BOOLEAN,
  TRUE,
  'store_round_ranks is idempotent (no duplicates on re-run)'
);

-- =============================================================================
-- Test 7: complete_round_with_winner also populates user_round_ranks.
--         Locks in the early-advance trigger path as well.
-- =============================================================================
SELECT lives_ok(
  $$SELECT complete_round_with_winner(current_setting('test.round_complete')::BIGINT)$$,
  'complete_round_with_winner runs without error'
);

SELECT cmp_ok(
  (SELECT COUNT(*)::INT FROM user_round_ranks
   WHERE round_id = current_setting('test.round_complete')::BIGINT),
  '>', 0,
  'complete_round_with_winner populates user_round_ranks'
);

SELECT * FROM finish();
ROLLBACK;
