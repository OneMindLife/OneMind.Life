-- Per-option "votes waiting for YOU inside" counts (Joel, 2026-07-15).
--
-- The reply-count badge (get_thread_reply_counts) answers "is there discussion
-- in this thread" — content presence, not personalized. It can't tell a voter
-- WHICH thread to open to find matches they still owe a judgment on. This is the
-- symmetric, personalized counterpart: for every proposition in a round, how
-- many placeable opinions sit in ITS child thread for THIS participant.
--
-- "Placeable" mirrors get_unplaced_opinion_count exactly: others' opinions
-- (not the voter's own, not carried) that the voter hasn't paired yet, and only
-- when >= 2 remain — because placing needs a PAIR, so a lone unplaced opinion
-- can't actually be voted (pickGlobalPair returns null under 2 fresh takes).
-- Threads with < 2 placeable are omitted, so the badge never advertises an
-- un-actionable vote. One batch query for the whole board.
CREATE OR REPLACE FUNCTION public.get_thread_unplaced_counts(
  p_round_id bigint,
  p_participant_id bigint
)
RETURNS TABLE(proposition_id bigint, unplaced bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT proposition_id, c AS unplaced
  FROM (
    SELECT parent.id AS proposition_id, count(cp.id) AS c
    FROM propositions parent
    JOIN cycles cc ON cc.parent_proposition_id = parent.id
    JOIN rounds cr ON cr.cycle_id = cc.id
    JOIN propositions cp ON cp.round_id = cr.id
                        AND cp.carried_from_id IS NULL
                        AND cp.participant_id IS DISTINCT FROM p_participant_id
                        AND NOT EXISTS (
                          SELECT 1 FROM pairwise_comparisons pc
                          WHERE pc.round_id = cr.id
                            AND pc.participant_id = p_participant_id
                            AND (pc.winner_proposition_id = cp.id
                                 OR pc.loser_proposition_id = cp.id)
                        )
    WHERE parent.round_id = p_round_id
    GROUP BY parent.id
  ) s
  WHERE c >= 2;
$$;

GRANT EXECUTE ON FUNCTION public.get_thread_unplaced_counts(bigint, bigint)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_thread_unplaced_counts(bigint, bigint) IS
  'For each proposition in a round, the count of placeable opinions (others'', unpaired, >=2) in its child thread for this participant. Powers the per-option "N to vote inside" attention badge; mirrors get_unplaced_opinion_count per thread.';
