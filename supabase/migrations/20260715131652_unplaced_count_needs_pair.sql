-- "N to place" dead-end fix (Joel, 2026-07-15): placing an opinion means
-- RANKING it, which needs a PAIR — two opinions this participant hasn't seen
-- yet. pickGlobalPair returns null the moment fewer than 2 fresh opinions
-- remain (its first line is `props.length < 2 => null`). The old count treated
-- a lone unplaced opinion (or a single-opinion child thread) as "1 to place",
-- so the banner said "1 opinion to place" but the picker had nothing to serve
-- ("no opinions to place"). Now the count returns 0 unless at least 2 placeable
-- opinions remain, so the banner never advertises an un-actionable placement.
CREATE OR REPLACE FUNCTION public.get_unplaced_opinion_count(
  p_round_id bigint,
  p_participant_id bigint
) RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN c >= 2 THEN c ELSE 0 END
  FROM (
    SELECT count(*)::int AS c
    FROM public.propositions p
    WHERE p.round_id = p_round_id
      AND p.carried_from_id IS NULL
      AND p.participant_id IS DISTINCT FROM p_participant_id
      AND NOT EXISTS (
        SELECT 1 FROM public.pairwise_comparisons pc
        WHERE pc.round_id = p_round_id
          AND pc.participant_id = p_participant_id
          AND (pc.winner_proposition_id = p.id OR pc.loser_proposition_id = p.id)
      )
  ) s;
$$;

GRANT EXECUTE ON FUNCTION public.get_unplaced_opinion_count(bigint, bigint)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_unplaced_opinion_count(bigint, bigint) IS
  'Repository mode: count of others'' opinions at a round this participant can still PLACE. Placing needs a pair, so returns 0 unless >=2 unplaced remain (matches pickGlobalPair, which needs 2 fresh takes). Drives the "N to place" pull.';
