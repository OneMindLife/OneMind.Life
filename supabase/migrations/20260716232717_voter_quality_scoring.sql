-- Data-quality assay for the pairwise-preference mine. For each voter in a chat,
-- measures how CONSISTENT their judgments are (the core signal that separates
-- real judgment from mash-to-unlock) plus how FAST they vote.
--
-- Consistency = intransitive 3-cycles. Among the triangles a voter fully judged
-- (all 3 pairs of {a,b,c}), a cycle A>B, B>C, C>A is a logical contradiction —
-- the mathematical fingerprint of random clicking. A careful voter's cyclic
-- ratio ≈ 0; pure random ≈ 0.25 (a random 3-tournament is cyclic 1/4 of the
-- time). Ties and skips are excluded (they aren't strict preferences).
--
-- NOTE (2026-07-16): running this on GLOBAL returned ZERO triangles across 775
-- votes — because pickGlobalPair only ever pairs UNSEEN items, so each voter's
-- comparisons are a disjoint matching (no shared items → no triangles → no
-- measurable consistency). The assay is correct; it revealed the router injects
-- no redundancy. Quality becomes measurable once the router mixes in
-- overlapping / repeated / gold pairs.
CREATE OR REPLACE FUNCTION public.get_chat_voter_quality(p_chat_id bigint)
RETURNS TABLE(
  participant_id   bigint,
  votes            int,      -- strict pairwise votes cast (excl. ties/skips)
  triangles        int,      -- triples where all 3 pairs were judged
  cyclic           int,      -- of those, how many are intransitive cycles
  inconsistency    numeric,  -- cyclic / triangles: 0 = perfect, ~0.25 = random
  median_gap_sec   numeric,  -- median seconds between consecutive votes
  suspect          boolean   -- heuristic flag: high inconsistency or very fast
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH cmp AS (
    SELECT pc.participant_id, pc.round_id, pc.created_at,
           LEAST(pc.winner_proposition_id, pc.loser_proposition_id)    AS lo,
           GREATEST(pc.winner_proposition_id, pc.loser_proposition_id) AS hi,
           (pc.winner_proposition_id < pc.loser_proposition_id)        AS lo_wins
    FROM pairwise_comparisons pc
    WHERE pc.chat_id = p_chat_id
      AND pc.is_tie IS NOT TRUE
      AND COALESCE(pc.is_skip, false) = false
      AND pc.participant_id IS NOT NULL
  ),
  pref AS (  -- one directed judgment per (voter, round, unordered pair)
    SELECT DISTINCT participant_id, round_id, lo, hi, lo_wins FROM cmp
  ),
  tri AS (   -- triangles a<b<c fully judged by the voter within one round
    SELECT ab.participant_id,
           CASE
             WHEN (ab.lo_wins AND bc.lo_wins AND NOT ac.lo_wins)
               OR (NOT ab.lo_wins AND NOT bc.lo_wins AND ac.lo_wins)
             THEN 1 ELSE 0
           END AS is_cyclic
    FROM pref ab
    JOIN pref bc ON bc.participant_id = ab.participant_id
                AND bc.round_id       = ab.round_id
                AND bc.lo             = ab.hi
    JOIN pref ac ON ac.participant_id = ab.participant_id
                AND ac.round_id       = ab.round_id
                AND ac.lo             = ab.lo
                AND ac.hi             = bc.hi
  ),
  gaps AS (
    SELECT participant_id,
           EXTRACT(EPOCH FROM (created_at
             - lag(created_at) OVER (PARTITION BY participant_id ORDER BY created_at))) AS gap
    FROM cmp
  ),
  per_voter AS (
    SELECT c.participant_id,
           count(*)                                               AS votes,
           (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY g.gap)::numeric, 1)
              FROM gaps g WHERE g.participant_id = c.participant_id AND g.gap IS NOT NULL) AS median_gap_sec
    FROM cmp c
    GROUP BY c.participant_id
  ),
  per_tri AS (
    SELECT participant_id, count(*) AS triangles, sum(is_cyclic) AS cyclic
    FROM tri GROUP BY participant_id
  )
  SELECT pv.participant_id,
         pv.votes::int,
         COALESCE(pt.triangles, 0)::int,
         COALESCE(pt.cyclic, 0)::int,
         round(COALESCE(pt.cyclic, 0)::numeric / NULLIF(pt.triangles, 0), 3) AS inconsistency,
         pv.median_gap_sec,
         (COALESCE(pt.cyclic, 0)::numeric / NULLIF(pt.triangles, 0) > 0.2)
           OR (pv.median_gap_sec IS NOT NULL AND pv.median_gap_sec < 3.5) AS suspect
  FROM per_voter pv
  LEFT JOIN per_tri pt ON pt.participant_id = pv.participant_id;
$$;

REVOKE ALL ON FUNCTION public.get_chat_voter_quality(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_chat_voter_quality(bigint) TO service_role;

COMMENT ON FUNCTION public.get_chat_voter_quality(bigint) IS
  'Per-voter data-quality assay: intransitive 3-cycle ratio (careless-clicking fingerprint) + median voting speed, from pairwise_comparisons. service_role only (analytics).';
