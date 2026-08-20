-- get_round_vote_count: how many REAL (non-skip) pairwise votes a round has.
-- DEFINER + open-by-id, mirroring get_round_voter_count (20260607180000) so the
-- client read is authoritative and not gated by the caller's (maybe not-yet-
-- committed) participant row / RLS.
--
-- Why: the host's "End voting" gate counted rating_completions, but a rater who
-- can't form a pair (they authored the only idea(s) available) is now also
-- marked complete — so a round with ZERO real votes could satisfy the gate and
-- be ended into a meaningless winner. The host gate now also requires >=1 real
-- vote, using this count.
CREATE OR REPLACE FUNCTION public.get_round_vote_count(p_round_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::int
  FROM pairwise_comparisons
  WHERE round_id = p_round_id
    AND is_skip = false;
$$;

GRANT EXECUTE ON FUNCTION public.get_round_vote_count(bigint) TO anon, authenticated;
