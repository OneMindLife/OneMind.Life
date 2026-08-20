-- =============================================================================
-- Test: Bradley-Terry EARLY EXIT (20260726150000_bradley_terry_early_exit)
-- =============================================================================
-- score_bradley_terry used to run a FIXED 200 MM sweeps for every round, which
-- put 8.5s between "voting closed" and "next proposing phase exists" at
-- exhaustion scale (measured on prod 2026-07-25). It now stops once the
-- DISPLAYED 0-100 score stops moving.
--
-- The risk this test exists to kill: an early exit that changes the ANSWER.
-- So the old fixed-200 loop is reproduced verbatim as
-- `_ref_score_bradley_terry_200` and the two are compared on identical data --
-- same winner, same ordering, scores within tolerance. If someone later tunes
-- c_tol or c_check_every too aggressively, this fails.
--
-- Also locks the invariants the fast path must not break: skips excluded, ties
-- worth half, 0/1-played rounds, bounds, idempotency, and the k=10 shrinkage
-- (which 149_bradley_terry_shrinkage_test covers from the product angle).
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(14);

-- ── Reference implementation: the OLD loop, verbatim, fixed 200 sweeps ───────
CREATE OR REPLACE FUNCTION _ref_score_bradley_terry_200(p_round_id bigint)
RETURNS TABLE(proposition_id bigint, global_score real)
LANGUAGE plpgsql
AS $ref$
DECLARE
  it int;
  n_played int;
  k_shrink constant double precision := 10.0;
BEGIN
  DROP TABLE IF EXISTS _r_items, _r_w, _r_pairs, _r_p, _r_m;
  CREATE TEMP TABLE _r_items ON COMMIT DROP AS
    SELECT p.id AS prop_id FROM propositions p
    WHERE p.round_id = p_round_id
      AND EXISTS (SELECT 1 FROM pairwise_comparisons pc
                  WHERE pc.round_id = p_round_id AND pc.is_skip = false
                    AND (pc.winner_proposition_id = p.id OR pc.loser_proposition_id = p.id));
  SELECT count(*) INTO n_played FROM _r_items;
  IF n_played = 0 THEN RETURN;
  ELSIF n_played = 1 THEN
    RETURN QUERY SELECT prop_id, 100.0::real FROM _r_items; RETURN;
  END IF;

  CREATE TEMP TABLE _r_w ON COMMIT DROP AS
    SELECT i.prop_id, COALESCE(SUM(CASE
        WHEN pc.winner_proposition_id = i.prop_id AND pc.is_tie = false THEN 1.0
        WHEN pc.is_tie THEN 0.5 ELSE 0 END), 0)::double precision AS w
    FROM _r_items i
    LEFT JOIN pairwise_comparisons pc ON pc.round_id = p_round_id AND pc.is_skip = false
      AND (pc.winner_proposition_id = i.prop_id OR pc.loser_proposition_id = i.prop_id)
    GROUP BY i.prop_id;
  CREATE TEMP TABLE _r_pairs ON COMMIT DROP AS
    SELECT LEAST(pc.winner_proposition_id, pc.loser_proposition_id) a,
           GREATEST(pc.winner_proposition_id, pc.loser_proposition_id) b,
           COUNT(*)::double precision n
    FROM pairwise_comparisons pc
    WHERE pc.round_id = p_round_id AND pc.is_skip = false GROUP BY 1, 2;
  CREATE TEMP TABLE _r_m ON COMMIT DROP AS
    SELECT id, SUM(n) AS m FROM (
      SELECT a AS id, n FROM _r_pairs UNION ALL SELECT b AS id, n FROM _r_pairs) x GROUP BY id;
  CREATE TEMP TABLE _r_p ON COMMIT DROP AS
    SELECT prop_id, 1.0::double precision AS p FROM _r_items;

  FOR it IN 1..200 LOOP
    WITH terms AS (
      SELECT pr.a id, pr.n / (pa.p + pb.p) t
        FROM _r_pairs pr JOIN _r_p pa ON pa.prop_id = pr.a JOIN _r_p pb ON pb.prop_id = pr.b
      UNION ALL
      SELECT pr.b id, pr.n / (pa.p + pb.p) t
        FROM _r_pairs pr JOIN _r_p pa ON pa.prop_id = pr.a JOIN _r_p pb ON pb.prop_id = pr.b),
    denom AS (SELECT id, SUM(t) d FROM terms GROUP BY id),
    newp AS (SELECT w.prop_id, CASE WHEN d.d > 0 THEN w.w / d.d ELSE 1e-9 END np
             FROM _r_w w JOIN denom d ON d.id = w.prop_id),
    norm AS (SELECT SUM(np) s FROM newp)
    UPDATE _r_p SET p = GREATEST(n.np / (SELECT s FROM norm), 1e-12)
    FROM newp n WHERE _r_p.prop_id = n.prop_id;
  END LOOP;

  RETURN QUERY
  SELECT pr.id,
         LEAST(100.0, GREATEST(0.0,
           50.0 + (raw.s - 50.0) * COALESCE(mm.m, 0) / (COALESCE(mm.m, 0) + k_shrink)))::real
  FROM propositions pr
  CROSS JOIN LATERAL (
    SELECT COALESCE((SELECT AVG(pi.p / (pi.p + pj.p)) * 100.0
                     FROM _r_p pi, _r_p pj
                     WHERE pi.prop_id = pr.id AND pj.prop_id <> pr.id), 0.0) AS s) raw
  LEFT JOIN _r_m mm ON mm.id = pr.id
  WHERE pr.round_id = p_round_id
    AND EXISTS (SELECT 1 FROM _r_items i WHERE i.prop_id = pr.id);
END;
$ref$;

-- ── Fixture builder: a round with n takes and a transitive strength order ────
-- Take k beats take j whenever k > j, with `reps` raters per pair. That gives a
-- known ground-truth ordering the fit must recover, plus enough distinct pairs
-- to exercise the iteration.
CREATE OR REPLACE FUNCTION _mk_round(p_name text, p_takes int, p_reps int)
RETURNS bigint LANGUAGE plpgsql AS $mk$
DECLARE v_chat int; v_cycle int; v_round bigint;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
  VALUES (p_name, 'Q', gen_random_uuid(), 'matches') RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'P', TRUE, 'active');
  INSERT INTO propositions (round_id, participant_id, content)
  SELECT v_round, (SELECT id FROM participants WHERE chat_id = v_chat LIMIT 1), 'T' || lpad(g::text, 4, '0')
  FROM generate_series(1, p_takes) g;
  INSERT INTO participants (chat_id, session_token, display_name, status)
  SELECT v_chat, gen_random_uuid(), 'R' || g, 'active' FROM generate_series(1, p_reps) g;

  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
  SELECT v_round, r.id, hi.id, lo.id
  FROM (SELECT id, content FROM propositions WHERE round_id = v_round) hi
  JOIN (SELECT id, content FROM propositions WHERE round_id = v_round) lo ON lo.content < hi.content
  CROSS JOIN (SELECT id FROM participants WHERE chat_id = v_chat AND display_name LIKE 'R%') r
  ON CONFLICT DO NOTHING;
  RETURN v_round;
END;
$mk$;

-- =============================================================================
-- 1. EQUIVALENCE vs the old fixed-200 loop
-- =============================================================================
DO $$
DECLARE v_round bigint;
BEGIN
  v_round := _mk_round('BT EarlyExit Equivalence', 12, 3);
  CREATE TEMP TABLE ref_scores ON COMMIT DROP AS
    SELECT * FROM _ref_score_bradley_terry_200(v_round);
  PERFORM score_bradley_terry(v_round);
  CREATE TEMP TABLE new_scores ON COMMIT DROP AS
    SELECT proposition_id, global_score FROM proposition_global_scores WHERE round_id = v_round;
  PERFORM set_config('test.round', v_round::text, true);
END $$;

SELECT is(
  (SELECT count(*) FROM new_scores)::int,
  (SELECT count(*) FROM ref_scores)::int,
  'early-exit scores every opinion the fixed-200 reference scored');

SELECT ok(
  (SELECT MAX(ABS(n.global_score - r.global_score))
   FROM new_scores n JOIN ref_scores r ON r.proposition_id = n.proposition_id) < 0.5,
  'every score is within 0.5 points of the fixed-200 reference');

SELECT is(
  (SELECT proposition_id FROM new_scores ORDER BY global_score DESC, proposition_id LIMIT 1),
  (SELECT proposition_id FROM ref_scores ORDER BY global_score DESC, proposition_id LIMIT 1),
  'early exit picks the same winner as the fixed-200 reference');

SELECT is(
  (SELECT count(*)::int FROM (
     SELECT n.proposition_id,
            rank() OVER (ORDER BY n.global_score DESC) rn,
            rank() OVER (ORDER BY r.global_score DESC) rr
     FROM new_scores n JOIN ref_scores r ON r.proposition_id = n.proposition_id) x
   WHERE rn <> rr),
  0,
  'early exit preserves the full ranking, not just the winner');

-- =============================================================================
-- 2. Ground truth: the fit recovers a known transitive order
-- =============================================================================
SELECT is(
  (SELECT p.content FROM new_scores n JOIN propositions p ON p.id = n.proposition_id
   ORDER BY n.global_score DESC LIMIT 1),
  'T0012',
  'the take that beat everything scores highest');

SELECT is(
  (SELECT p.content FROM new_scores n JOIN propositions p ON p.id = n.proposition_id
   ORDER BY n.global_score ASC LIMIT 1),
  'T0001',
  'the take that lost everything scores lowest');

SELECT ok(
  (SELECT bool_and(ok) FROM (
     SELECT n.global_score >= LEAD(n.global_score) OVER (ORDER BY p.content DESC) IS NOT FALSE AS ok
     FROM new_scores n JOIN propositions p ON p.id = n.proposition_id) x),
  'scores are monotone in the known strength order');

-- =============================================================================
-- 3. Bounds, idempotency, degenerate rounds
-- =============================================================================
SELECT ok(
  (SELECT bool_and(global_score >= 0 AND global_score <= 100) FROM new_scores),
  'all scores stay within 0..100');

DO $$
DECLARE v_round bigint := current_setting('test.round')::bigint;
BEGIN
  PERFORM score_bradley_terry(v_round);
  CREATE TEMP TABLE rerun_scores ON COMMIT DROP AS
    SELECT proposition_id, global_score FROM proposition_global_scores WHERE round_id = v_round;
END $$;

SELECT is(
  (SELECT count(*)::int FROM new_scores n
   JOIN rerun_scores r ON r.proposition_id = n.proposition_id
   WHERE n.global_score IS DISTINCT FROM r.global_score),
  0,
  'scoring the same round twice is deterministic');

-- Zero comparisons -> no score rows at all.
DO $$
DECLARE v_chat int; v_cycle int; v_round bigint;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
  VALUES ('BT EarlyExit Empty', 'Q', gen_random_uuid(), 'matches') RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'P', TRUE, 'active');
  INSERT INTO propositions (round_id, participant_id, content)
  SELECT v_round, (SELECT id FROM participants WHERE chat_id = v_chat LIMIT 1), 'E' || g
  FROM generate_series(1, 3) g;
  PERFORM score_bradley_terry(v_round);
  PERFORM set_config('test.empty_round', v_round::text, true);
END $$;

SELECT is(
  (SELECT count(*)::int FROM proposition_global_scores
   WHERE round_id = current_setting('test.empty_round')::bigint),
  0,
  'a round with no comparisons produces no scores');

-- =============================================================================
-- 4. Skips are not votes; ties are worth half
-- =============================================================================
DO $$
DECLARE v_chat int; v_cycle int; v_round bigint; v_a bigint; v_b bigint; v_c bigint; v_p int;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
  VALUES ('BT EarlyExit Skips', 'Q', gen_random_uuid(), 'matches') RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'P', TRUE, 'active') RETURNING id INTO v_p;
  INSERT INTO propositions (round_id, participant_id, content) VALUES
    (v_round, v_p, 'A') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES
    (v_round, v_p, 'B') RETURNING id INTO v_b;
  INSERT INTO propositions (round_id, participant_id, content) VALUES
    (v_round, v_p, 'C') RETURNING id INTO v_c;
  INSERT INTO participants (chat_id, session_token, display_name, status)
  SELECT v_chat, gen_random_uuid(), 'R' || g, 'active' FROM generate_series(1, 4) g;

  -- A beats B four times; C only ever appears in SKIPPED matches.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
  SELECT v_round, r.id, v_a, v_b FROM participants r
  WHERE r.chat_id = v_chat AND r.display_name LIKE 'R%';
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id, is_skip)
  SELECT v_round, r.id, v_c, v_a, true FROM participants r
  WHERE r.chat_id = v_chat AND r.display_name LIKE 'R%';

  PERFORM score_bradley_terry(v_round);
  PERFORM set_config('test.skip_round', v_round::text, true);
  PERFORM set_config('test.skip_c', v_c::text, true);
  PERFORM set_config('test.skip_a', v_a::text, true);
  PERFORM set_config('test.skip_b', v_b::text, true);
END $$;

SELECT is(
  (SELECT count(*)::int FROM proposition_global_scores
   WHERE round_id = current_setting('test.skip_round')::bigint
     AND proposition_id = current_setting('test.skip_c')::bigint),
  0,
  'an opinion seen only in skipped matches is not scored');

SELECT ok(
  (SELECT s_a.global_score > s_b.global_score
   FROM proposition_global_scores s_a, proposition_global_scores s_b
   WHERE s_a.round_id = current_setting('test.skip_round')::bigint
     AND s_a.proposition_id = current_setting('test.skip_a')::bigint
     AND s_b.round_id = current_setting('test.skip_round')::bigint
     AND s_b.proposition_id = current_setting('test.skip_b')::bigint),
  'the winner of every real matchup outscores the loser');

-- Symmetric ties -> equal scores.
DO $$
DECLARE v_chat int; v_cycle int; v_round bigint; v_a bigint; v_b bigint; v_p int;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
  VALUES ('BT EarlyExit Ties', 'Q', gen_random_uuid(), 'matches') RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'P', TRUE, 'active') RETURNING id INTO v_p;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p, 'TA') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p, 'TB') RETURNING id INTO v_b;
  INSERT INTO participants (chat_id, session_token, display_name, status)
  SELECT v_chat, gen_random_uuid(), 'R' || g, 'active' FROM generate_series(1, 6) g;
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id, is_tie)
  SELECT v_round, r.id, v_a, v_b, true FROM participants r
  WHERE r.chat_id = v_chat AND r.display_name LIKE 'R%';
  PERFORM score_bradley_terry(v_round);
  PERFORM set_config('test.tie_round', v_round::text, true);
END $$;

SELECT ok(
  (SELECT MAX(global_score) - MIN(global_score) < 0.001
   FROM proposition_global_scores WHERE round_id = current_setting('test.tie_round')::bigint),
  'two opinions that only ever tied score identically');

-- =============================================================================
-- 5. The seal path still produces a winner (the thing users wait on)
-- =============================================================================
DO $$
DECLARE v_round bigint;
BEGIN
  v_round := _mk_round('BT EarlyExit Seal', 8, 3);
  PERFORM complete_round_with_winner(v_round);
  PERFORM set_config('test.seal_round', v_round::text, true);
END $$;

SELECT is(
  (SELECT p.content FROM rounds r JOIN propositions p ON p.id = r.winning_proposition_id
   WHERE r.id = current_setting('test.seal_round')::bigint),
  'T0008',
  'complete_round_with_winner crowns the strongest take through the fast path');

ROLLBACK;
