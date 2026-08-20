-- The per-option reply-count badge must match what the user SEES when they open
-- the thread. The node board (get_node_bootstrap) shows every proposition in the
-- child round — human AND AI — but get_thread_reply_counts excluded AI/bot
-- authors, so the badge undercounted (said "1" when opening showed 2). Count all
-- non-carried replies regardless of author, so the badge equals the list.
-- (SEO stays human-only via its own get_seo_* RPCs — unaffected.)
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
  WHERE parent.round_id = p_round_id
  GROUP BY parent.id;
$$;

GRANT EXECUTE ON FUNCTION public.get_thread_reply_counts(bigint) TO anon, authenticated;

COMMENT ON FUNCTION public.get_thread_reply_counts(bigint) IS
  'For each proposition in a round, the count of ALL replies in its thread (human + AI, carried excluded) — matches the list shown when the thread is opened. Powers the per-option "content inside" badge.';
