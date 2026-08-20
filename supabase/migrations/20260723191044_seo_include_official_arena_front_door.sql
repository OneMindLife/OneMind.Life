-- The SEO content engine (get_seo_index / get_seo_chat) excluded is_arena chats.
-- That predates 2026-07-20, when the front door itself became the phased arena
-- room GLOBAL (is_arena = true for timer-advance). The exclusion silently turned
-- OFF all opinion pages: get_seo_index returned [], the sitemap lost every
-- /opinions/* URL, and /opinions/GLOBAL rendered an empty fallback. Both funcs
-- already gate on is_official = true, which is the real trust boundary, so the
-- arena flag is redundant here. Drop it so the official front door qualifies.

CREATE OR REPLACE FUNCTION public.get_seo_index()
 RETURNS TABLE(code text, human_props bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    AND ch.is_preview = false
    AND ch.telegram_chat_id IS NULL
    AND ch.ended_at IS NULL
  GROUP BY ch.invite_code
  HAVING count(p.id) >= 5;
$function$;

CREATE OR REPLACE FUNCTION public.get_seo_chat(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    AND ch.is_preview = false
    AND ch.telegram_chat_id IS NULL
    AND ch.ended_at IS NULL;
  RETURN v;
END;
$function$;
