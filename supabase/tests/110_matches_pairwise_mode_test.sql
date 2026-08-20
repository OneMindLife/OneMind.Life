-- =============================================================================
-- Tests for the matches (pairwise) rating mode — DB layer.
-- Migration: 20260529200000_matches_pairwise_mode.sql
-- =============================================================================
-- Coverage:
--   1.  pairwise_comparisons table exists
--   2.  propositions.comparison_count column (integer)
--   3.  sync_proposition_comparison_count_trg trigger exists
--   4.  chats.rating_mode CHECK rejects an invalid value
--   5.  chats.match_objective CHECK rejects an invalid value
--   6.  pc_distinct_props CHECK: winner = loser is rejected
--   7.  pc_has_rater CHECK: neither participant_id nor session_token is rejected
--   8.  unique-pair index: a duplicate unordered pair by the same rater throws
--   9.  INSERT increments comparison_count on BOTH propositions
--   10. a second comparison involving a prop accumulates its count
--   11. DELETE decrements comparison_count
--   12. DELETE clamps at 0 (GREATEST guard)
--   13. MOVDA blend (pure pairwise): a prop that beats all others is the
--       unique top global_score
--   14. MOVDA blend (tie): a tie is a margin-0 edge → both involved props ARE
--       scored (14a) and the tie pulls their ratings together vs a decisive
--       win on the same pair (14b)
--   15. MOVDA blend (mixed grid + pairwise): every involved proposition is
--       scored
--   16. **REGRESSION**: the comparison_count trigger must fire when the INSERT
--       comes from the `authenticated` role under RLS (SECURITY DEFINER guard
--       — same class of bug as the L1 rating_count trigger, see test 105/11).
--   18. Cross-round/chat injection guard.
--   19. propositions.is_skip column exists with default false. (column lives on
--       pairwise_comparisons; named per scope)
--   20. MOVDA blend (skip-only round): skip rows are excluded → no edges, no
--       global_scores.
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(22);

-- =============================================================================
-- SETUP: one chat / cycle / round, 4 participants each owning one proposition.
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Matches Pairwise Test', 'Test', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT; v_cycle_id INT; v_round_id INT;
  v_p1 INT; v_p2 INT; v_p3 INT; v_p4 INT;
  v_prop_a INT; v_prop_b INT; v_prop_c INT; v_prop_d INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Matches Pairwise Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES
    ('00000000-0000-0000-0000-0000000000a1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000a2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000a3'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000a4'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1'::UUID, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000a2'::UUID, 'P2', FALSE, 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000a3'::UUID, 'P3', FALSE, 'active') RETURNING id INTO v_p3;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000a4'::UUID, 'P4', FALSE, 'active') RETURNING id INTO v_p4;

  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p1, 'Prop A') RETURNING id INTO v_prop_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p2, 'Prop B') RETURNING id INTO v_prop_b;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p3, 'Prop C') RETURNING id INTO v_prop_c;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p4, 'Prop D') RETURNING id INTO v_prop_d;

  PERFORM set_config('test.mp.chat_id',  v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.mp.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.mp.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.mp.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.mp.prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.mp.prop_b', v_prop_b::TEXT, TRUE);
  PERFORM set_config('test.mp.prop_c', v_prop_c::TEXT, TRUE);
  PERFORM set_config('test.mp.prop_d', v_prop_d::TEXT, TRUE);
END $$;

-- =============================================================================
-- 1-3. Schema
-- =============================================================================
SELECT has_table('public', 'pairwise_comparisons', '1: pairwise_comparisons table exists');
SELECT col_type_is('public', 'propositions', 'comparison_count', 'integer', '2: propositions.comparison_count is integer');
SELECT has_trigger('public', 'pairwise_comparisons', 'sync_proposition_comparison_count_trg', '3: comparison_count sync trigger exists');

-- =============================================================================
-- 4-5. Config CHECK constraints
-- =============================================================================
SELECT throws_ok(
  format('UPDATE chats SET rating_mode = ''bogus'' WHERE id = %s', current_setting('test.mp.chat_id')),
  NULL, '4: chats.rating_mode rejects an invalid value'
);
SELECT throws_ok(
  format('UPDATE chats SET match_objective = ''bogus'' WHERE id = %s', current_setting('test.mp.chat_id')),
  NULL, '5: chats.match_objective rejects an invalid value'
);

-- =============================================================================
-- 6-8. Table constraints
-- =============================================================================
SELECT throws_ok(
  format('INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES (%s, %s, %s, %s)',
    current_setting('test.mp.round_id'), current_setting('test.mp.p1'),
    current_setting('test.mp.prop_a'), current_setting('test.mp.prop_a')),
  NULL, '6: winner = loser is rejected (pc_distinct_props)'
);
SELECT throws_ok(
  format('INSERT INTO pairwise_comparisons (round_id, winner_proposition_id, loser_proposition_id) VALUES (%s, %s, %s)',
    current_setting('test.mp.round_id'), current_setting('test.mp.prop_a'), current_setting('test.mp.prop_b')),
  NULL, '7: no rater identity is rejected (pc_has_rater)'
);

-- Seed one comparison, then attempt the reverse-order duplicate (same unordered pair, same rater) → unique index throws.
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
  VALUES (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT,
          current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT);
SELECT throws_ok(
  format('INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES (%s, %s, %s, %s)',
    current_setting('test.mp.round_id'), current_setting('test.mp.p1'),
    current_setting('test.mp.prop_b'), current_setting('test.mp.prop_a')),
  NULL, '8: duplicate unordered pair by same rater is rejected'
);

-- =============================================================================
-- 9-10. comparison_count increments (the row inserted above: A vs B)
-- =============================================================================
SELECT is(
  (SELECT comparison_count FROM propositions WHERE id = current_setting('test.mp.prop_a')::INT), 1,
  '9a: prop_a comparison_count = 1 after one comparison'
);
SELECT is(
  (SELECT comparison_count FROM propositions WHERE id = current_setting('test.mp.prop_b')::INT), 1,
  '9b: prop_b comparison_count = 1 (both sides counted)'
);
-- A second comparison involving A (A vs C)
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
  VALUES (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT,
          current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_c')::INT);
SELECT is(
  (SELECT comparison_count FROM propositions WHERE id = current_setting('test.mp.prop_a')::INT), 2,
  '10: prop_a comparison_count accumulates to 2'
);

-- =============================================================================
-- 11-12. DELETE decrements + clamps
-- =============================================================================
DELETE FROM pairwise_comparisons
  WHERE round_id = current_setting('test.mp.round_id')::INT
    AND winner_proposition_id = current_setting('test.mp.prop_a')::INT
    AND loser_proposition_id = current_setting('test.mp.prop_c')::INT;
SELECT is(
  (SELECT comparison_count FROM propositions WHERE id = current_setting('test.mp.prop_a')::INT), 1,
  '11: DELETE decrements prop_a comparison_count back to 1'
);
-- Corrupt prop_c to 0 then delete its remaining row → clamp (prop_c had count 0 already after the delete above; corrupt the A vs B loser side instead)
DO $$
BEGIN
  UPDATE propositions SET comparison_count = 0 WHERE id = current_setting('test.mp.prop_b')::INT;
  DELETE FROM pairwise_comparisons
    WHERE round_id = current_setting('test.mp.round_id')::INT
      AND winner_proposition_id = current_setting('test.mp.prop_a')::INT
      AND loser_proposition_id = current_setting('test.mp.prop_b')::INT;
END $$;
SELECT is(
  (SELECT comparison_count FROM propositions WHERE id = current_setting('test.mp.prop_b')::INT), 0,
  '12: DELETE never drives comparison_count negative (clamps at 0)'
);

-- =============================================================================
-- 13. MOVDA blend — pure pairwise. A beats B, C, D → A is the unique top score.
-- (Clear all pairwise rows first so only these three edges exist.)
-- =============================================================================
DELETE FROM pairwise_comparisons WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM proposition_global_scores WHERE round_id = current_setting('test.mp.round_id')::INT;
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT, current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT),
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT, current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_c')::INT),
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT, current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_d')::INT);
SELECT calculate_movda_scores_for_round(current_setting('test.mp.round_id')::BIGINT, 0.42::DOUBLE PRECISION);
SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
     WHERE round_id = current_setting('test.mp.round_id')::INT
     ORDER BY global_score DESC, proposition_id LIMIT 1),
  current_setting('test.mp.prop_a')::BIGINT,
  '13: pure-pairwise MOVDA makes the prop that beats all others the top score'
);

-- =============================================================================
-- 14. MOVDA blend — tie is a margin-0 edge. A tie now CREATES an edge (old
-- behavior: ties created none), so both involved props are scored. And because
-- the edge carries margin 0, it pulls the two ratings TOGETHER: the rating gap
-- after a tie is far smaller than after a decisive win on the same pair.
--
-- 14a: both involved props are scored.
-- 14b: the tie's rating gap is a small fraction of a decisive win's gap.
-- (Asserted on proposition_movda_ratings — the un-normalized layer; the 0-100
-- global_score normalization stretches any nonzero gap to {0,100}, so equality
-- of global_score is not the observable property here. The Elo win-probability
-- term keeps a single tie from equalizing exactly, but the margin-0 edge still
-- collapses the gap by ~2x+ vs a decisive win.)
-- =============================================================================
DELETE FROM pairwise_comparisons WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM proposition_global_scores WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM proposition_movda_ratings WHERE round_id = current_setting('test.mp.round_id')::INT;

-- Decisive baseline: A beats B (no tie) → measure the rating gap.
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id, is_tie) VALUES
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT, current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT, false);
SELECT calculate_movda_scores_for_round(current_setting('test.mp.round_id')::BIGINT, 0.42::DOUBLE PRECISION);
SELECT set_config('test.mp.decisive_gap',
  (SELECT (MAX(rating) - MIN(rating))::TEXT FROM proposition_movda_ratings
     WHERE round_id = current_setting('test.mp.round_id')::INT
       AND proposition_id IN (current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT)),
  FALSE);

-- Tie-only round on the SAME pair.
DELETE FROM pairwise_comparisons WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM proposition_global_scores WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM proposition_movda_ratings WHERE round_id = current_setting('test.mp.round_id')::INT;
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id, is_tie) VALUES
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT, current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT, true);
SELECT calculate_movda_scores_for_round(current_setting('test.mp.round_id')::BIGINT, 0.42::DOUBLE PRECISION);

SELECT is(
  (SELECT COUNT(*)::INT FROM proposition_global_scores
     WHERE round_id = current_setting('test.mp.round_id')::INT
       AND proposition_id IN (current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT)),
  2,
  '14a: a tie creates an edge, so both involved props are scored'
);
SELECT ok(
  (SELECT (MAX(rating) - MIN(rating)) FROM proposition_movda_ratings
     WHERE round_id = current_setting('test.mp.round_id')::INT
       AND proposition_id IN (current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT))
    < current_setting('test.mp.decisive_gap')::REAL / 2.0,
  '14b: a tie (margin-0 edge) pulls the two ratings together — gap < half the decisive-win gap'
);

-- =============================================================================
-- 15. MOVDA blend — mixed. grid edge (B>C) + pairwise edge (A>D) → all 4 scored.
-- =============================================================================
DELETE FROM pairwise_comparisons WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM proposition_global_scores WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM grid_rankings WHERE round_id = current_setting('test.mp.round_id')::INT;
-- grid: P2 ranks B above C
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position) VALUES
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p2')::INT, current_setting('test.mp.prop_b')::INT, 80.0),
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p2')::INT, current_setting('test.mp.prop_c')::INT, 20.0);
-- pairwise: P1 prefers A over D
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT, current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_d')::INT);
SELECT calculate_movda_scores_for_round(current_setting('test.mp.round_id')::BIGINT, 0.42::DOUBLE PRECISION);
SELECT is(
  (SELECT COUNT(*)::INT FROM proposition_global_scores WHERE round_id = current_setting('test.mp.round_id')::INT),
  4,
  '15: mixed grid + pairwise round scores all four involved propositions'
);

-- =============================================================================
-- 16. REGRESSION: comparison_count trigger fires under the authenticated role.
-- A fresh pair so the assertion does not depend on prior counter state.
-- =============================================================================
DO $$
DECLARE v_p5 INT; v_prop_e INT; v_prop_f INT;
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id)
    VALUES ('00000000-0000-0000-0000-0000000000a5'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (current_setting('test.mp.chat_id')::INT, gen_random_uuid(),
            '00000000-0000-0000-0000-0000000000a5'::UUID, 'P5', FALSE, 'active') RETURNING id INTO v_p5;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (current_setting('test.mp.round_id')::INT, v_p5, 'Prop E') RETURNING id INTO v_prop_e;
  -- another fresh prop owned by P5 via carried_from_id to dodge the unique-new-per-round index
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (current_setting('test.mp.round_id')::INT, v_p5, 'Prop F', current_setting('test.mp.prop_a')::INT) RETURNING id INTO v_prop_f;
  PERFORM set_config('test.mp.p5', v_p5::TEXT, TRUE);
  PERFORM set_config('test.mp.prop_e', v_prop_e::TEXT, TRUE);
  PERFORM set_config('test.mp.prop_f', v_prop_f::TEXT, TRUE);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000a5', 'role', 'authenticated')::TEXT, TRUE);

INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
VALUES (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p5')::INT,
        current_setting('test.mp.prop_e')::INT, current_setting('test.mp.prop_f')::INT);

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT is(
  (SELECT comparison_count FROM propositions WHERE id = current_setting('test.mp.prop_e')::INT), 1,
  '16: comparison_count trigger fires + increments when INSERT comes from the authenticated role under RLS'
);

-- =============================================================================
-- 18. Cross-round/chat injection guard: a comparison in round 1 that references
-- a proposition belonging to a DIFFERENT round is rejected.
-- =============================================================================
DO $$
DECLARE v_cycle2 INT; v_round2 INT; v_foreign_prop INT;
BEGIN
  INSERT INTO cycles (chat_id) VALUES (current_setting('test.mp.chat_id')::INT) RETURNING id INTO v_cycle2;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle2, 1, 'rating') RETURNING id INTO v_round2;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round2, current_setting('test.mp.p2')::INT, 'Foreign Prop') RETURNING id INTO v_foreign_prop;
  PERFORM set_config('test.mp.foreign_prop', v_foreign_prop::TEXT, TRUE);
END $$;

SELECT throws_ok(
  format('INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id) VALUES (%s, %s, %s, %s)',
    current_setting('test.mp.round_id'), current_setting('test.mp.p1'),
    current_setting('test.mp.foreign_prop'), current_setting('test.mp.prop_b')),
  NULL, '18: a comparison referencing a proposition from another round is rejected'
);

-- =============================================================================
-- 19. is_skip column exists with default false.
-- =============================================================================
SELECT has_column('public', 'pairwise_comparisons', 'is_skip', '19a: pairwise_comparisons.is_skip column exists');
SELECT col_default_is('public', 'pairwise_comparisons', 'is_skip', 'false', '19b: pairwise_comparisons.is_skip defaults to false');

-- =============================================================================
-- 20. MOVDA blend — skip-only round. Skip rows are excluded from MOVDA → no
-- edges, no global_scores.
-- =============================================================================
DELETE FROM pairwise_comparisons WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM grid_rankings WHERE round_id = current_setting('test.mp.round_id')::INT;
DELETE FROM proposition_global_scores WHERE round_id = current_setting('test.mp.round_id')::INT;
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id, is_skip) VALUES
  (current_setting('test.mp.round_id')::INT, current_setting('test.mp.p1')::INT, current_setting('test.mp.prop_a')::INT, current_setting('test.mp.prop_b')::INT, true);
SELECT calculate_movda_scores_for_round(current_setting('test.mp.round_id')::BIGINT, 0.42::DOUBLE PRECISION);
SELECT is(
  (SELECT COUNT(*)::INT FROM proposition_global_scores WHERE round_id = current_setting('test.mp.round_id')::INT),
  0,
  '20: a skip-only round produces no comparison edges and no scores'
);

SELECT * FROM finish();
ROLLBACK;
