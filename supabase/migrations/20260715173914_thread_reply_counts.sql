-- Per-option "content inside" counts (Joel, 2026-07-15): for every proposition
-- in a round, how many human replies live in ITS thread (child cycle). Drives a
-- notification-style badge on each option card — "there's stuff to explore/vote
-- on in here" — like the Vote tab badge, but per option. One batch query.
CREATE OR REPLACE FUNCTION public.get_thread_reply_counts(p_round_id bigint)
RETURNS TABLE(proposition_id bigint, replies bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT parent.id AS proposition_id, count(cp.id) AS replies
  FROM propositions parent
  JOIN cycles cc ON cc.parent_proposition_id = parent.id
  JOIN rounds cr ON cr.cycle_id = cc.id
  JOIN propositions cp ON cp.round_id = cr.id
                      AND cp.carried_from_id IS NULL
                      AND cp.participant_id IS NOT NULL
  JOIN participants pt ON pt.id = cp.participant_id
                      AND pt.display_name <> 'AI'
                      AND COALESCE(pt.agent_role::text, 'off') = 'off'
  WHERE parent.round_id = p_round_id
  GROUP BY parent.id;
$$;

GRANT EXECUTE ON FUNCTION public.get_thread_reply_counts(bigint) TO anon, authenticated;

COMMENT ON FUNCTION public.get_thread_reply_counts(bigint) IS
  'For each proposition in a round, the count of human replies in its thread. Powers the per-option "content inside" badge.';
