-- Per-LEVEL social proof (Joel, 2026-07-15): {opinions, votes} scoped to a
-- single round, so the metric bar can sit BELOW the stack and describe only the
-- content inside THAT node — "N opinions · M votes" at the root, "N replies · M
-- votes" inside a thread. Human only (AI/bot excluded). At the root this is still
-- a big, alive number; inside a thin thread it's honestly small.
CREATE OR REPLACE FUNCTION public.get_round_social_proof(p_round_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'opinions', (
      SELECT count(*)
      FROM propositions p
      JOIN participants pt ON pt.id = p.participant_id
      WHERE p.round_id = p_round_id
        AND p.carried_from_id IS NULL
        AND pt.display_name <> 'AI'
        AND COALESCE(pt.agent_role::text, 'off') = 'off'
    ),
    'votes', (
      SELECT count(*)
      FROM pairwise_comparisons pc
      WHERE pc.round_id = p_round_id AND pc.is_skip = false
    )
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_round_social_proof(bigint) TO anon, authenticated;

COMMENT ON FUNCTION public.get_round_social_proof(bigint) IS
  'Per-level social proof {opinions, votes} for one round (human only). Powers the below-the-stack metric bar scoped to the current node.';
