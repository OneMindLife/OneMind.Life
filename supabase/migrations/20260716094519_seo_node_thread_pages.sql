-- Per-thread SEO pages (Joel, 2026-07-16): the root /opinions/<code> page bundles
-- every top-level opinion (74 unrelated topics on GLOBAL) onto ONE page — SEO-
-- diluted. Each opinion's REPLY THREAD is its own topical discussion. Index each
-- sub-thread as /opinions/<code>/<parentPropId>: headline = the opinion being
-- discussed, body = its replies ranked head-to-head. Human-only (same policy as
-- get_seo_chat) so AI takes never form or headline a page. See
-- docs/SEO_CONTENT_STRATEGY.md + docs/ONEMIND_CONCEPT.md (preference-oracle).

-- Which sub-threads are worth a static page: a HUMAN-authored parent opinion in
-- an eligible official public chat, whose reply thread has >=2 HUMAN replies
-- (enough to rank head-to-head and clear thin-content).
CREATE OR REPLACE FUNCTION public.get_seo_node_index()
RETURNS TABLE(code text, node bigint, parent text, replies bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT ch.invite_code,
         parent.id      AS node,
         parent.content AS parent,
         count(rep.id)  AS replies
  FROM chats ch
  JOIN cycles pc  ON pc.chat_id = ch.id AND pc.parent_proposition_id IS NOT NULL
  JOIN propositions parent ON parent.id = pc.parent_proposition_id
  JOIN participants ppt ON ppt.id = parent.participant_id
                       AND ppt.display_name <> 'AI'
                       AND COALESCE(ppt.agent_role::text, 'off') = 'off'
  JOIN rounds rr ON rr.cycle_id = pc.id
  JOIN propositions rep ON rep.round_id = rr.id
                       AND rep.carried_from_id IS NULL
                       AND rep.participant_id IS NOT NULL
  JOIN participants rpt ON rpt.id = rep.participant_id
                       AND rpt.display_name <> 'AI'
                       AND COALESCE(rpt.agent_role::text, 'off') = 'off'
  WHERE ch.is_official = true
    AND ch.access_method = 'public'
    AND ch.is_arena = false
    AND ch.is_preview = false
    AND ch.telegram_chat_id IS NULL
    AND ch.ended_at IS NULL
  GROUP BY ch.invite_code, parent.id, parent.content
  HAVING count(rep.id) >= 2;
$$;

-- One sub-thread's content: the parent opinion + its HUMAN replies ranked by
-- head-to-head global_score (best first). Works for any proposition that has a
-- child cycle in an eligible chat.
CREATE OR REPLACE FUNCTION public.get_seo_node(p_code text, p_node bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v jsonb;
BEGIN
  SELECT jsonb_build_object(
    'code', ch.invite_code,
    'node', parent.id,
    'parent', parent.content,
    'opinions', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object('id', s.id, 'content', s.content, 'score', s.score_int)
               ORDER BY s.score_raw DESC NULLS LAST, s.created_at
             )
      FROM (
        SELECT rep.id,
               rep.content,
               rep.created_at,
               gs.global_score            AS score_raw,
               round(gs.global_score)::int AS score_int
        FROM cycles pc
        JOIN rounds rr ON rr.cycle_id = pc.id
        JOIN propositions rep ON rep.round_id = rr.id
                             AND rep.carried_from_id IS NULL
                             AND rep.participant_id IS NOT NULL
        JOIN participants rpt ON rpt.id = rep.participant_id
                             AND rpt.display_name <> 'AI'
                             AND COALESCE(rpt.agent_role::text, 'off') = 'off'
        LEFT JOIN proposition_global_scores gs
               ON gs.proposition_id = rep.id AND gs.round_id = rr.id
        WHERE pc.parent_proposition_id = parent.id
        ORDER BY gs.global_score DESC NULLS LAST, rep.created_at
        LIMIT 300
      ) s
    ), '[]'::jsonb)
  )
  INTO v
  FROM chats ch
  JOIN propositions parent ON parent.id = p_node
  JOIN rounds pr  ON pr.id = parent.round_id
  JOIN cycles pcy ON pcy.id = pr.cycle_id AND pcy.chat_id = ch.id
  WHERE ch.invite_code = upper(p_code)
    AND ch.is_official = true
    AND ch.access_method = 'public'
    AND ch.is_arena = false
    AND ch.is_preview = false
    AND ch.telegram_chat_id IS NULL
    AND ch.ended_at IS NULL;
  RETURN v;  -- NULL when the code/node is not eligible
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_seo_node_index() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_seo_node(text, bigint) TO anon, authenticated;

COMMENT ON FUNCTION public.get_seo_node_index() IS
  'SEO: sub-threads (parentPropId) with a HUMAN parent + >=2 HUMAN replies in eligible official public chats — each gets a static /opinions/<code>/<node> page.';
COMMENT ON FUNCTION public.get_seo_node(text, bigint) IS
  'SEO/AEO: one sub-thread — the parent opinion + its HUMAN replies ranked head-to-head. Powers /opinions/<code>/<node>.';
