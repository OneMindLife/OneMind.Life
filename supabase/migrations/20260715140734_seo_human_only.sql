-- Human-only SEO content (Joel, 2026-07-15): the /opinions pages exist to feed
-- HUMAN judgment to search + AI answer-engines (humans power it, AI consumes it
-- — docs/ONEMIND_CONCEPT.md preference-oracle thesis). AI-authored opinions
-- must not pollute that data. Exclude the arena/global AI (display_name='AI')
-- and any seat-fill bot (agent_role <> 'off') from BOTH the eligibility index
-- and the content itself.

CREATE OR REPLACE FUNCTION public.get_seo_index()
RETURNS TABLE(code text, human_props bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT ch.invite_code,
         count(p.id) AS human_props
  FROM chats ch
  JOIN cycles c  ON c.chat_id = ch.id
  JOIN rounds r  ON r.cycle_id = c.id
  JOIN propositions p ON p.round_id = r.id
                     AND p.carried_from_id IS NULL
                     AND p.participant_id IS NOT NULL
  JOIN participants pt ON pt.id = p.participant_id
                      AND pt.display_name <> 'AI'
                      AND COALESCE(pt.agent_role::text, 'off') = 'off'
  WHERE ch.is_official = true
    AND ch.access_method = 'public'
    AND ch.is_arena = false
    AND ch.is_preview = false
    AND ch.telegram_chat_id IS NULL
    AND ch.ended_at IS NULL
  GROUP BY ch.invite_code
  HAVING count(p.id) >= 5;
$$;

CREATE OR REPLACE FUNCTION public.get_seo_chat(p_code text)
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
    'name', ch.name,
    'question', NULLIF(ch.initial_message, ''),
    'opinions', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object('id', s.id, 'content', s.content, 'score', s.score_int)
               ORDER BY s.score_raw DESC NULLS LAST, s.created_at
             )
      FROM (
        SELECT p.id,
               p.content,
               p.created_at,
               gs.global_score               AS score_raw,
               round(gs.global_score)::int    AS score_int
        FROM propositions p
        JOIN rounds r ON r.id = p.round_id
        JOIN cycles c ON c.id = r.cycle_id
        JOIN participants pt ON pt.id = p.participant_id
                            AND pt.display_name <> 'AI'
                            AND COALESCE(pt.agent_role::text, 'off') = 'off'
        LEFT JOIN proposition_global_scores gs
               ON gs.proposition_id = p.id AND gs.round_id = r.id
        WHERE c.chat_id = ch.id
          AND c.parent_proposition_id IS NULL   -- the main floor (not sub-threads)
          AND p.carried_from_id IS NULL
          AND p.participant_id IS NOT NULL
        ORDER BY gs.global_score DESC NULLS LAST, p.created_at
        LIMIT 300
      ) s
    ), '[]'::jsonb)
  )
  INTO v
  FROM chats ch
  WHERE ch.invite_code = upper(p_code)
    AND ch.is_official = true
    AND ch.access_method = 'public'
    AND ch.is_arena = false
    AND ch.is_preview = false
    AND ch.telegram_chat_id IS NULL
    AND ch.ended_at IS NULL;
  RETURN v;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_seo_index() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_seo_chat(text) TO anon, authenticated;

COMMENT ON FUNCTION public.get_seo_chat(text) IS
  'SEO/AEO: HUMAN main-floor opinions for a chat, ranked by head-to-head global_score (best first) with the score. AI/bot takes excluded. Powers the answer-first /opinions/<code> page.';
COMMENT ON FUNCTION public.get_seo_index() IS
  'SEO: official public chats with >=5 HUMAN opinions (AI/bots excluded), eligible for a static /opinions/<code> page.';
