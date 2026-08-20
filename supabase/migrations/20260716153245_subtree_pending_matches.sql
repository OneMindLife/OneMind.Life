-- For each proposition in a round, the total PENDING MATCHES this participant
-- still owes across its ENTIRE subtree (every descendant round), not just the
-- immediate child thread. matches per round = floor(unplaced / 2), summed.
-- Powers the per-option "votes waiting below" slot. Recurses cycles→rounds; the
-- depth cap mirrors the client walk. Trees are shallow today; if they deepen,
-- denormalize (see docs/PERFORMANCE_TESTING.md).
CREATE OR REPLACE FUNCTION public.get_subtree_pending_matches(
  p_round_id bigint,
  p_participant_id bigint
)
RETURNS TABLE(proposition_id bigint, matches bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH RECURSIVE desc_rounds AS (
    -- depth 1: immediate child rounds of each proposition in the target round
    SELECT parent.id AS root_id, cr.id AS rid, 1 AS depth
    FROM propositions parent
    JOIN cycles cc ON cc.parent_proposition_id = parent.id
    JOIN rounds cr ON cr.cycle_id = cc.id
    WHERE parent.round_id = p_round_id
    UNION ALL
    -- deeper: child rounds of the propositions inside a descendant round
    SELECT dr.root_id, cr2.id, dr.depth + 1
    FROM desc_rounds dr
    JOIN propositions cp ON cp.round_id = dr.rid
    JOIN cycles cc2 ON cc2.parent_proposition_id = cp.id
    JOIN rounds cr2 ON cr2.cycle_id = cc2.id
    WHERE dr.depth < 20
  ),
  per_round AS (
    SELECT DISTINCT dr.root_id, dr.rid FROM desc_rounds dr
  )
  SELECT pr.root_id AS proposition_id,
         sum(floor(u.unplaced / 2))::bigint AS matches
  FROM per_round pr
  CROSS JOIN LATERAL (
    SELECT count(*)::bigint AS unplaced
    FROM propositions cp
    WHERE cp.round_id = pr.rid
      AND cp.carried_from_id IS NULL
      AND cp.participant_id IS DISTINCT FROM p_participant_id
      AND NOT EXISTS (
        SELECT 1 FROM pairwise_comparisons pc
        WHERE pc.round_id = pr.rid
          AND pc.participant_id = p_participant_id
          AND (pc.winner_proposition_id = cp.id
               OR pc.loser_proposition_id = cp.id)
      )
  ) u
  GROUP BY pr.root_id
  HAVING sum(floor(u.unplaced / 2)) >= 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_subtree_pending_matches(bigint, bigint)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_subtree_pending_matches(bigint, bigint) IS
  'Per proposition in a round: total pending pairwise matches this participant owes across the WHOLE subtree (all descendant rounds), floor(unplaced/2) summed. Powers the per-option votes-waiting slot.';
