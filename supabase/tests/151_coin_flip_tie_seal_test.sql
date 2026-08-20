-- =============================================================================
-- Test: COIN-FLIP TIE-BREAK for Instant mode (20260804120000_coin_flip_tie_seal)
-- =============================================================================
-- A tie in an Instant-mode chat (confirmation_rounds_required = 1) used to leave
-- is_sole_winner = FALSE and carry every tied idea into a fresh "tiebreaker"
-- round -- which then froze forever in an empty room (it needs NEW propositions
-- before voting can open). The fix: break the tie with a real coin flip -- pick
-- one tied-top idea at random, seal it as the sole winner, and let Instant mode
-- crown it immediately. No tiebreaker round is created.
--
-- Convergence mode (>= 2) is deliberately unchanged: a repeated mandate must not
-- be granted by a coin flip, so ties there still re-contest (see also
-- 102_convergence_tie_tolerance_test, whose chat is conf = 2).
--
-- Ties are produced with REAL pairwise votes (a 1-1 split), not hand-set scores,
-- because complete_round_with_winner recomputes scores from
-- pairwise_comparisons for a matches chat.
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- Build a matches chat with one 2-idea rating round tied 1-1, seal it, and
-- stash ids. p_conf selects Instant (1) vs Convergence (2).
CREATE OR REPLACE FUNCTION _seal_tied_round(p_conf int)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_chat int; v_cycle bigint; v_round bigint; v_a bigint; v_b bigint; v_p1 bigint; v_p2 bigint;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode, is_arena,
    confirmation_rounds_required, scoring_algorithm, start_mode, auto_start_participant_count)
  VALUES ('Coinflip '||p_conf, 'Q', gen_random_uuid(), 'matches', true, p_conf, 'bradley_terry', 'auto', 1)
  RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'P1', true, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, display_name, status)
    VALUES (v_chat, gen_random_uuid(), 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p1, 'A') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p2, 'B') RETURNING id INTO v_b;
  -- 1-1 split => exact tie at 50.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p1, v_a, v_b);
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p2, v_b, v_a);
  PERFORM complete_round_with_winner(v_round);
  PERFORM set_config('t.chat', v_chat::text, true);
  PERFORM set_config('t.cycle', v_cycle::text, true);
  PERFORM set_config('t.round', v_round::text, true);
  PERFORM set_config('t.a', v_a::text, true);
  PERFORM set_config('t.b', v_b::text, true);
END $fn$;

-- =============================================================================
-- A. Instant mode: tie is coin-flipped to a single sealed winner
-- =============================================================================
SELECT lives_ok($$SELECT _seal_tied_round(1)$$, 'Instant tie round seals without error');

SELECT is(
  (SELECT is_sole_winner FROM rounds WHERE id = current_setting('t.round')::bigint),
  TRUE,
  'Instant tie -> is_sole_winner = TRUE (coin-flip produced a decisive winner)');

SELECT is(
  (SELECT count(*)::int FROM round_winners WHERE round_id = current_setting('t.round')::bigint AND rank = 1),
  1,
  'Instant tie -> exactly ONE rank-1 winner (not both, so carry-forward is unambiguous)');

SELECT ok(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('t.round')::bigint)
    IN (current_setting('t.a')::bigint, current_setting('t.b')::bigint),
  'Instant tie -> the sealed winner is one of the two tied ideas');

SELECT ok(
  (SELECT completed_at IS NOT NULL FROM cycles WHERE id = current_setting('t.cycle')::bigint),
  'Instant tie -> the cycle SEALS immediately (permanent winner), no pending tiebreak');

SELECT is(
  (SELECT count(*)::int FROM rounds WHERE cycle_id = current_setting('t.cycle')::bigint),
  1,
  'Instant tie -> NO tiebreaker round created in the sealed cycle (the freeze cause)');

-- =============================================================================
-- B. Convergence mode: ties are UNCHANGED (still re-contest, no coin flip)
-- =============================================================================
SELECT lives_ok($$SELECT _seal_tied_round(2)$$, 'Convergence tie round seals without error');

SELECT is(
  (SELECT is_sole_winner FROM rounds WHERE id = current_setting('t.round')::bigint),
  FALSE,
  'Convergence tie -> is_sole_winner = FALSE (unchanged: no coin flip)');

SELECT ok(
  (SELECT completed_at IS NULL FROM cycles WHERE id = current_setting('t.cycle')::bigint),
  'Convergence tie -> cycle does NOT seal (idea must still repeat its win)');

-- =============================================================================
-- C. Instant mode, CLEAR winner (not a tie): coin flip does not fire
-- =============================================================================
DO $$
DECLARE v_chat int; v_cycle bigint; v_round bigint; v_a bigint; v_b bigint;
        v_p1 bigint; v_p2 bigint; v_p3 bigint; v_h bigint;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode, is_arena,
    confirmation_rounds_required, scoring_algorithm, start_mode, auto_start_participant_count)
  VALUES ('Coinflip clear', 'Q', gen_random_uuid(), 'matches', true, 1, 'bradley_terry', 'auto', 1)
  RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'H', true, 'active') RETURNING id INTO v_h;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_h, 'HI') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_h, 'LO') RETURNING id INTO v_b;
  INSERT INTO participants (chat_id, session_token, display_name, status)
    VALUES (v_chat, gen_random_uuid(), 'V1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, display_name, status)
    VALUES (v_chat, gen_random_uuid(), 'V2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, display_name, status)
    VALUES (v_chat, gen_random_uuid(), 'V3', 'active') RETURNING id INTO v_p3;
  -- 3 voters all pick HI over LO -> clear, non-tied winner.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p1, v_a, v_b), (v_round, v_p2, v_a, v_b), (v_round, v_p3, v_a, v_b);
  PERFORM complete_round_with_winner(v_round);
  PERFORM set_config('t.round', v_round::text, true);
  PERFORM set_config('t.a', v_a::text, true);
END $$;

SELECT is(
  (SELECT is_sole_winner FROM rounds WHERE id = current_setting('t.round')::bigint),
  TRUE,
  'Instant clear winner -> is_sole_winner = TRUE');

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('t.round')::bigint),
  current_setting('t.a')::bigint,
  'Instant clear winner -> the actually-strongest idea wins (coin flip did not fire)');

-- =============================================================================
-- D. The flip is RANDOM: over many tied rounds, BOTH ideas win at least once.
--    (A fixed/arbitrary pick would make one of these counts zero.)
-- =============================================================================
DO $$
DECLARE i int; v_a_wins int := 0; v_b_wins int := 0;
BEGIN
  FOR i IN 1..40 LOOP
    PERFORM _seal_tied_round(1);
    IF (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('t.round')::bigint)
        = current_setting('t.a')::bigint THEN
      v_a_wins := v_a_wins + 1;
    ELSE
      v_b_wins := v_b_wins + 1;
    END IF;
  END LOOP;
  PERFORM set_config('t.a_wins', v_a_wins::text, true);
  PERFORM set_config('t.b_wins', v_b_wins::text, true);
END $$;

SELECT ok(
  current_setting('t.a_wins')::int > 0 AND current_setting('t.b_wins')::int > 0,
  format('coin flip is random: over 40 ties, idea A won %s and idea B won %s (both > 0)',
         current_setting('t.a_wins'), current_setting('t.b_wins')));

SELECT * FROM finish();
ROLLBACK;
