-- Bradley-Terry: stop iterating once the ANSWER stops moving.
--
-- Measured on prod (2026-07-25, 200 takes / 37,660 votes / 17,698 distinct
-- pairs -- "everyone proposes, everyone votes to exhaustion"):
--
--   complete_round_with_winner   8,508 ms
--     +- score_bradley_terry     8,231 ms
--          +- one MM sweep          37 ms  x 200 fixed = 7,417 ms  (87% of seal)
--          +- final O(N^2) pass     24 ms
--     +- ranks / winners / next-round creation   ~300 ms
--
-- The loop ran a FIXED 200 sweeps regardless of round size, so a 12-vote round
-- paid the same 200 query plans as a 40,000-vote one. That latency sits between
-- "voting closed" and "next proposing phase exists" -- it is dead air for every
-- person in the room.
--
-- Why the exit test is on the SCORE and not on the fit:
--   The MM fit converges slowly. Measured at exhaustion scale, the max relative
--   change in the latent strengths was still 3.7e-4 after 200 sweeps, so the
--   textbook `EXIT WHEN delta < 1e-6` would never fire -- it would be a no-op
--   dressed up as an optimization. The DISPLAYED 0-100 score settles far
--   earlier (max difference vs the 200-sweep answer: 3.5 points at sweep 20,
--   1.2 at 50, 0.30 at 100; the winner was identical from sweep 5 onward). So
--   the loop now exits when the score itself stops moving, which is the only
--   quantity anyone sees or acts on.
--
-- Two changes:
--   1. Early exit: every 10 sweeps, recompute the shrunk 0-100 score and stop
--      when no opinion moved by more than 0.05 points since the last check.
--      The 200-sweep ceiling is unchanged, so this can never be slower than the
--      old behaviour by more than the checks themselves (~24 ms each).
--   2. Build the doubled edge list ONCE (_bt_edges) instead of re-deriving it
--      from _bt_pairs via UNION ALL inside every sweep -- that halves the joins
--      per sweep.
--
-- Behaviour is otherwise identical: same MM update, same k=10 shrinkage, same
-- 0-100 clamp, same handling of 0/1 played opinions, same output rows.
-- Equivalence against the old fixed-200 implementation is asserted in
-- supabase/tests/150_bradley_terry_early_exit_test.sql, which keeps a verbatim
-- copy of the old loop as a reference and compares winners and scores.

CREATE OR REPLACE FUNCTION public.score_bradley_terry(p_round_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  it int;
  n_played int;
  k_shrink      constant double precision := 10.0;  -- matchups to trust the score halfway
  c_max_iters   constant int              := 200;   -- unchanged ceiling
  c_check_every constant int              := 10;    -- sweeps between score checks
  c_tol         constant double precision := 0.05;  -- points on the 0-100 scale
  v_delta double precision;
BEGIN
  DROP TABLE IF EXISTS _bt_items, _bt_w, _bt_pairs, _bt_p, _bt_m, _bt_edges, _bt_chk, _bt_now;

  CREATE TEMP TABLE _bt_items ON COMMIT DROP AS
    SELECT p.id AS prop_id FROM propositions p
    WHERE p.round_id = p_round_id
      AND EXISTS (SELECT 1 FROM pairwise_comparisons pc
                  WHERE pc.round_id = p_round_id AND pc.is_skip = false
                    AND (pc.winner_proposition_id = p.id OR pc.loser_proposition_id = p.id));
  SELECT count(*) INTO n_played FROM _bt_items;

  DELETE FROM proposition_global_scores WHERE round_id = p_round_id;

  IF n_played = 0 THEN
    RETURN;
  ELSIF n_played = 1 THEN
    INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
    SELECT p_round_id, prop_id, 100.0::real, NOW() FROM _bt_items;
    RETURN;
  END IF;

  CREATE TEMP TABLE _bt_w ON COMMIT DROP AS
    SELECT i.prop_id, COALESCE(SUM(CASE
        WHEN pc.winner_proposition_id = i.prop_id AND pc.is_tie = false THEN 1.0
        WHEN pc.is_tie THEN 0.5 ELSE 0 END), 0)::double precision AS w
    FROM _bt_items i
    LEFT JOIN pairwise_comparisons pc ON pc.round_id = p_round_id AND pc.is_skip = false
      AND (pc.winner_proposition_id = i.prop_id OR pc.loser_proposition_id = i.prop_id)
    GROUP BY i.prop_id;

  CREATE TEMP TABLE _bt_pairs ON COMMIT DROP AS
    SELECT LEAST(pc.winner_proposition_id, pc.loser_proposition_id) a,
           GREATEST(pc.winner_proposition_id, pc.loser_proposition_id) b,
           COUNT(*)::double precision n
    FROM pairwise_comparisons pc
    WHERE pc.round_id = p_round_id AND pc.is_skip = false
    GROUP BY 1, 2;

  CREATE TEMP TABLE _bt_m ON COMMIT DROP AS
    SELECT id, SUM(n) AS m FROM (
      SELECT a AS id, n FROM _bt_pairs
      UNION ALL
      SELECT b AS id, n FROM _bt_pairs
    ) x GROUP BY id;

  CREATE TEMP TABLE _bt_p ON COMMIT DROP AS
    SELECT prop_id, 1.0::double precision AS p FROM _bt_items;

  -- Each opinion's matchups from ITS side, materialized once. The old loop
  -- rebuilt this shape with a UNION ALL over _bt_pairs (two scans, four joins)
  -- on every one of the 200 sweeps.
  CREATE TEMP TABLE _bt_edges ON COMMIT DROP AS
    SELECT a AS id, b AS other, n FROM _bt_pairs
    UNION ALL
    SELECT b AS id, a AS other, n FROM _bt_pairs;

  ANALYZE _bt_edges;
  ANALYZE _bt_p;
  ANALYZE _bt_w;

  -- Score snapshots for the convergence test: _bt_chk = as of the previous
  -- check, _bt_now = current. Created once and refilled, so the loop does not
  -- churn the catalog.
  CREATE TEMP TABLE _bt_chk (prop_id bigint PRIMARY KEY, score double precision) ON COMMIT DROP;
  CREATE TEMP TABLE _bt_now (prop_id bigint PRIMARY KEY, score double precision) ON COMMIT DROP;

  FOR it IN 1..c_max_iters LOOP
    WITH denom AS (
      SELECT e.id, SUM(e.n / (pi.p + pj.p)) AS d
      FROM _bt_edges e
      JOIN _bt_p pi ON pi.prop_id = e.id
      JOIN _bt_p pj ON pj.prop_id = e.other
      GROUP BY e.id
    ),
    newp AS (SELECT w.prop_id, CASE WHEN d.d > 0 THEN w.w / d.d ELSE 1e-9 END np
             FROM _bt_w w JOIN denom d ON d.id = w.prop_id),
    norm AS (SELECT SUM(np) s FROM newp)
    UPDATE _bt_p SET p = GREATEST(n.np / (SELECT s FROM norm), 1e-12)
    FROM newp n WHERE _bt_p.prop_id = n.prop_id;

    IF it % c_check_every = 0 THEN
      TRUNCATE _bt_now;
      INSERT INTO _bt_now (prop_id, score)
      SELECT raw.prop_id,
             LEAST(100.0, GREATEST(0.0,
               50.0 + (raw.s - 50.0) * COALESCE(mm.m, 0) / (COALESCE(mm.m, 0) + k_shrink)))
      FROM (
        -- ONE pass over the N^2 self-join, not a correlated subquery re-run per
        -- opinion. As a per-item LATERAL this check cost ~24 ms and made the
        -- early exit a net LOSS at mid scale (measured: 2,207 pairs went
        -- 1,833 ms -> 2,229 ms); as a single grouped pass it is a rounding error.
        SELECT pi.prop_id, AVG(pi.p / (pi.p + pj.p)) * 100.0 AS s
        FROM _bt_p pi
        CROSS JOIN _bt_p pj
        WHERE pj.prop_id <> pi.prop_id
        GROUP BY pi.prop_id
      ) raw
      LEFT JOIN _bt_m mm ON mm.id = raw.prop_id;

      -- NULL on the first check (nothing to compare against yet) -> keep going.
      SELECT MAX(ABS(n.score - c.score)) INTO v_delta
      FROM _bt_now n JOIN _bt_chk c ON c.prop_id = n.prop_id;

      TRUNCATE _bt_chk;
      INSERT INTO _bt_chk SELECT prop_id, score FROM _bt_now;

      EXIT WHEN v_delta IS NOT NULL AND v_delta < c_tol;
    END IF;
  END LOOP;

  -- Same single-pass form as the convergence check. Equivalent to the old
  -- per-row LATERAL: _bt_p holds exactly _bt_items, and n_played >= 2 here, so
  -- every opinion has at least one opponent and the COALESCE(...,0) fallback
  -- the old shape needed is unreachable.
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
  SELECT p_round_id, raw.prop_id,
         LEAST(100.0, GREATEST(0.0,
           50.0 + (raw.s - 50.0)
                  * COALESCE(mm.m, 0) / (COALESCE(mm.m, 0) + k_shrink)
         ))::real,
         NOW()
  FROM (
    SELECT pi.prop_id, AVG(pi.p / (pi.p + pj.p)) * 100.0 AS s
    FROM _bt_p pi
    CROSS JOIN _bt_p pj
    WHERE pj.prop_id <> pi.prop_id
    GROUP BY pi.prop_id
  ) raw
  LEFT JOIN _bt_m mm ON mm.id = raw.prop_id;
END;
$function$;

COMMENT ON FUNCTION public.score_bradley_terry(bigint) IS
  'Bradley-Terry (MM) fit for a matches round, scored 0-100 with k=10 low-sample '
  'shrinkage. Iterates until the displayed score stops moving (max 0.05 points '
  'per 10 sweeps) or 200 sweeps, whichever comes first -- the fit itself '
  'converges too slowly for a strength-based exit test to ever fire.';
