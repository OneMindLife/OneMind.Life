-- Cumulative social proof for a chat (Joel, 2026-07-15): people who've weighed
-- in, ideas contributed, judgments cast — all HUMAN, all cumulative (only grow),
-- so it's a safe "this place is alive" signal for cold traffic with none of the
-- ghost-town risk of a realtime "N here now" (which is 0-1 most of the time).
-- Powers the /g/<code> social-proof header (polled ~15s client-side for a live
-- tick — NOT a per-vote realtime subscription, which would re-create the
-- pairwise_comparisons cascade CLAUDE.md warns about). AI/bot excluded.
CREATE OR REPLACE FUNCTION public.get_chat_social_proof(p_chat_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'people', (
      SELECT count(DISTINCT pid) FROM (
        SELECT p.participant_id AS pid
        FROM propositions p
        JOIN rounds r ON r.id = p.round_id
        JOIN cycles c ON c.id = r.cycle_id
        JOIN participants pt ON pt.id = p.participant_id
        WHERE c.chat_id = p_chat_id
          AND p.carried_from_id IS NULL
          AND pt.display_name <> 'AI'
          AND COALESCE(pt.agent_role::text, 'off') = 'off'
        UNION
        SELECT pc.participant_id
        FROM pairwise_comparisons pc
        JOIN participants pt2 ON pt2.id = pc.participant_id
        WHERE pc.chat_id = p_chat_id
          AND pc.is_skip = false
          AND pt2.display_name <> 'AI'
          AND COALESCE(pt2.agent_role::text, 'off') = 'off'
      ) u
    ),
    'ideas', (
      SELECT count(*)
      FROM propositions p
      JOIN rounds r ON r.id = p.round_id
      JOIN cycles c ON c.id = r.cycle_id
      JOIN participants pt ON pt.id = p.participant_id
      WHERE c.chat_id = p_chat_id
        AND p.carried_from_id IS NULL
        AND pt.display_name <> 'AI'
        AND COALESCE(pt.agent_role::text, 'off') = 'off'
    ),
    'judgments', (
      SELECT count(*)
      FROM pairwise_comparisons pc
      WHERE pc.chat_id = p_chat_id AND pc.is_skip = false
    )
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_chat_social_proof(bigint) TO anon, authenticated;

COMMENT ON FUNCTION public.get_chat_social_proof(bigint) IS
  'Cumulative human social proof for a chat: {people, ideas, judgments}. Powers the /g/<code> alive-not-ghost-town header.';
