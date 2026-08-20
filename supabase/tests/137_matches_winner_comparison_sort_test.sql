-- =============================================================================
-- Test: MATCHES-mode winner = the head-to-head COMPARISON SORT (not Elo/MOVDA).
-- Migration: 20260714210000_matches_winner_comparison_sort.sql
-- =============================================================================
-- The bug this locks in: the wedge LIVE RANKING sorts by comparisonSort
-- (position from direct head-to-head vs neighbours, swap on any margin), but
-- the sealed winner used to be the Elo/MOVDA top score — so the idea shown
-- winning the sort could lose the seal. calculate_movda_scores_for_round now
-- dispatches matches-mode rounds to calculate_pairwise_comparison_scores, so
-- MAX(global_score) == the comparison-sort #1.
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(4);

-- ── Case 1: cumulative-INDEPENDENCE ──────────────────────────────────────────
-- A racks up 5 easy wins over the weak take C, but LOST head-to-head to B once.
-- Elo would reward A's pile of wins; the comparison sort must crown B (it beat A
-- directly). Position is relative, not cumulative.
INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('H2H Winner Test 1', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE
  v_chat INT; v_cycle INT; v_round INT;
  v_pa INT; v_pb INT; v_pc INT; v_a INT; v_b INT; v_c INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'H2H Winner Test 1';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  -- One proposer per take (the unique-new-per-round index allows 1 each).
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'PA', TRUE, 'active') RETURNING id INTO v_pa;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'PB', FALSE, 'active') RETURNING id INTO v_pb;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'PC', FALSE, 'active') RETURNING id INTO v_pc;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_pa, 'A') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_pb, 'B') RETURNING id INTO v_b;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_pc, 'C') RETURNING id INTO v_c;

  -- 5 distinct raters each pick A over C (one vote per pair per rater); one of
  -- them also picks B over A. So A beats C 5×, but B beat A head-to-head.
  INSERT INTO participants (chat_id, session_token, display_name, status)
    SELECT v_chat, gen_random_uuid(), 'R' || g, 'active' FROM generate_series(1, 5) g;
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    SELECT v_round, p.id, v_a, v_c
    FROM participants p WHERE p.chat_id = v_chat AND p.display_name LIKE 'R%';
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_pa, v_b, v_a);

  PERFORM calculate_movda_scores_for_round(v_round);

  PERFORM set_config('t.round', v_round::text, false);
  PERFORM set_config('t.a', v_a::text, false);
  PERFORM set_config('t.b', v_b::text, false);
  PERFORM set_config('t.c', v_c::text, false);
END $$;

SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
   WHERE round_id = current_setting('t.round')::int
   ORDER BY global_score DESC LIMIT 1),
  current_setting('t.b')::bigint,
  'winner = B: a direct head-to-head win outranks a pile of easy wins'
);

SELECT cmp_ok(
  (SELECT global_score FROM proposition_global_scores
     WHERE round_id = current_setting('t.round')::int AND proposition_id = current_setting('t.b')::bigint),
  '>',
  (SELECT global_score FROM proposition_global_scores
     WHERE round_id = current_setting('t.round')::int AND proposition_id = current_setting('t.a')::bigint),
  'B outscores A (position-relative, not cumulative)'
);

SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
   WHERE round_id = current_setting('t.round')::int
   ORDER BY global_score ASC LIMIT 1),
  current_setting('t.c')::bigint,
  'C is last (lost its only matchup)'
);

-- ── Case 2: transitive → the Condorcet winner takes #1 ───────────────────────
INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('H2H Winner Test 2', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE
  v_chat INT; v_cycle INT; v_round INT;
  v_px INT; v_py INT; v_pz INT; v_x INT; v_y INT; v_z INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'H2H Winner Test 2';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'PX', TRUE, 'active') RETURNING id INTO v_px;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'PY', FALSE, 'active') RETURNING id INTO v_py;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'PZ', FALSE, 'active') RETURNING id INTO v_pz;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_px, 'X') RETURNING id INTO v_x;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_py, 'Y') RETURNING id INTO v_y;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_pz, 'Z') RETURNING id INTO v_z;

  -- X beats everyone, Y beats Z → X > Y > Z.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_px, v_x, v_y),
           (v_round, v_px, v_x, v_z),
           (v_round, v_px, v_y, v_z);

  PERFORM calculate_movda_scores_for_round(v_round);
  PERFORM set_config('t2.round', v_round::text, false);
  PERFORM set_config('t2.x', v_x::text, false);
END $$;

SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
   WHERE round_id = current_setting('t2.round')::int
   ORDER BY global_score DESC LIMIT 1),
  current_setting('t2.x')::bigint,
  'transitive: the Condorcet winner (beats all) takes #1'
);

SELECT finish();
ROLLBACK;
