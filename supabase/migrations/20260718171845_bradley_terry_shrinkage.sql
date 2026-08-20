-- Bradley-Terry low-sample shrinkage. The MM fit had NO regularization, so an
-- opinion that won its first few matchups got a near-certain win-prob (~95-99)
-- off 3-7 votes and leapfrogged opinions vetted over 40+ matchups. Fix: shrink
-- each score toward 50 (neutral / "unknown") in proportion to how few matchups
-- it has, so a thinly-voted opinion literally can't top a battle-tested one until
-- it earns the exposure:
--
--   shrunk = 50 + (raw - 50) * m / (m + K)
--
-- where m = that opinion's non-skip matchup count and K = the pseudo-count (how
-- many matchups it takes to trust the score halfway). K=10: well-voted opinions
-- (40+) barely move; a 3-vote opinion is pulled hard toward the middle. This
-- fixes rank AND score together (rank is the score sorted). Post-hoc shrinkage is
-- a pragmatic approximation of a Bayesian prior — monotonic, one interpretable
-- knob; a fuller version would add virtual games inside the MM fit.

CREATE OR REPLACE FUNCTION public.score_bradley_terry(p_round_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  it int;
  n_played int;
  k_shrink constant double precision := 10.0;  -- matchups to trust the score halfway
BEGIN
  DROP TABLE IF EXISTS _bt_items, _bt_w, _bt_pairs, _bt_p, _bt_m;
  CREATE TEMP TABLE _bt_items ON COMMIT DROP AS
    SELECT p.id AS prop_id FROM propositions p
    WHERE p.round_id = p_round_id
      AND EXISTS (SELECT 1 FROM pairwise_comparisons pc
                  WHERE pc.round_id = p_round_id AND pc.is_skip = false
                    AND (pc.winner_proposition_id = p.id OR pc.loser_proposition_id = p.id));
  SELECT count(*) INTO n_played FROM _bt_items;

  DELETE FROM proposition_global_scores WHERE round_id = p_round_id;

  IF n_played = 0 THEN
    RETURN;  -- no votes yet → no ranking
  ELSIF n_played = 1 THEN
    INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
    SELECT p_round_id, prop_id, 100.0::real, NOW() FROM _bt_items;
    -- other props (unplayed) stay unscored (absent) → render below the scored one
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

  -- Per-opinion matchup count (non-skip games played) — drives the shrinkage.
  CREATE TEMP TABLE _bt_m ON COMMIT DROP AS
    SELECT id, SUM(n) AS m FROM (
      SELECT a AS id, n FROM _bt_pairs
      UNION ALL
      SELECT b AS id, n FROM _bt_pairs
    ) x GROUP BY id;

  CREATE TEMP TABLE _bt_p ON COMMIT DROP AS
    SELECT prop_id, 1.0::double precision AS p FROM _bt_items;

  FOR it IN 1..200 LOOP
    WITH terms AS (
      SELECT pr.a id, pr.n / (pa.p + pb.p) t
        FROM _bt_pairs pr JOIN _bt_p pa ON pa.prop_id = pr.a JOIN _bt_p pb ON pb.prop_id = pr.b
      UNION ALL
      SELECT pr.b id, pr.n / (pa.p + pb.p) t
        FROM _bt_pairs pr JOIN _bt_p pa ON pa.prop_id = pr.a JOIN _bt_p pb ON pb.prop_id = pr.b
    ),
    denom AS (SELECT id, SUM(t) d FROM terms GROUP BY id),
    newp AS (SELECT w.prop_id, CASE WHEN d.d > 0 THEN w.w / d.d ELSE 1e-9 END np
             FROM _bt_w w JOIN denom d ON d.id = w.prop_id),
    norm AS (SELECT SUM(np) s FROM newp)
    UPDATE _bt_p SET p = GREATEST(n.np / (SELECT s FROM norm), 1e-12)
    FROM newp n WHERE _bt_p.prop_id = n.prop_id;
  END LOOP;

  -- Final score = avg win-prob against the field ×100, then SHRUNK toward 50 by
  -- matchup count so low-sample scores can't top well-vetted ones.
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
  SELECT p_round_id, pr.id,
         LEAST(100.0, GREATEST(0.0,
           50.0 + (raw.s - 50.0)
                  * COALESCE(mm.m, 0) / (COALESCE(mm.m, 0) + k_shrink)
         ))::real,
         NOW()
  FROM propositions pr
  CROSS JOIN LATERAL (
    SELECT COALESCE((
      SELECT AVG(pi.p / (pi.p + pj.p)) * 100.0
      FROM _bt_p pi, _bt_p pj
      WHERE pi.prop_id = pr.id AND pj.prop_id <> pr.id
    ), 0.0) AS s
  ) raw
  LEFT JOIN _bt_m mm ON mm.id = pr.id
  WHERE pr.round_id = p_round_id
    AND EXISTS (SELECT 1 FROM _bt_items i WHERE i.prop_id = pr.id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.score_bradley_terry(bigint) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.score_bradley_terry(bigint) IS
  'Bradley-Terry (MM fit) → proposition_global_scores (avg field win-prob ×100), SHRUNK toward 50 by matchup count (K=10, added 20260718170000) so low-sample opinions cannot top well-vetted ones.';
