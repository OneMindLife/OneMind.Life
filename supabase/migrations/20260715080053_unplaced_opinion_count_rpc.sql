-- Repository mode "N to place" pull (Joel, 2026-07-15): how many opinions at a
-- level this participant hasn't weighed in on yet — i.e. others' opinions with
-- no pairwise comparison from this participant. A returner who already ranked
-- the old ones sees only the genuinely NEW ones; a newcomer sees the full list.
-- Own opinions and carried-forward duplicates are excluded (you don't place
-- your own). Drives the notification-style "N new opinions to place" prompt.
CREATE OR REPLACE FUNCTION public.get_unplaced_opinion_count(
  p_round_id bigint,
  p_participant_id bigint
) RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::int
  FROM public.propositions p
  WHERE p.round_id = p_round_id
    AND p.carried_from_id IS NULL
    AND p.participant_id IS DISTINCT FROM p_participant_id
    AND NOT EXISTS (
      SELECT 1 FROM public.pairwise_comparisons pc
      WHERE pc.round_id = p_round_id
        AND pc.participant_id = p_participant_id
        AND (pc.winner_proposition_id = p.id OR pc.loser_proposition_id = p.id)
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_unplaced_opinion_count(bigint, bigint)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_unplaced_opinion_count(bigint, bigint) IS
  'Repository mode: count of others'' opinions at a round this participant has not yet placed (no pairwise comparison involving them). Drives the "N to place" pull.';
