-- SEO content feed for the wedge's build-time static generation.
-- Build runs as anon (no auth.uid), so these SECURITY DEFINER RPCs expose only
-- public-safe fields for OFFICIAL, public, non-arena/preview/telegram, active
-- chats with enough content to not be thin. See docs/SEO_CONTENT_STRATEGY.md.

-- Which chats get a crawlable /opinions/<code> page (generateStaticParams).
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
  WHERE ch.is_official = true
    AND ch.access_method = 'public'
    AND ch.is_arena = false
    AND ch.is_preview = false
    AND ch.telegram_chat_id IS NULL
    AND ch.ended_at IS NULL
  GROUP BY ch.invite_code
  HAVING count(p.id) >= 5;  -- enough opinions to be a substantial page
$$;

-- Full public-safe content for one chat's SEO page: the question + every human
-- opinion (text only; no author identity — the chat is anonymous by design).
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
    'question', NULLIF(ch.initial_message, ''),  -- NULL for open-floor chats
    'opinions', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object('id', p.id, 'content', p.content)
               ORDER BY p.created_at
             )
      FROM propositions p
      JOIN rounds r ON r.id = p.round_id
      JOIN cycles c ON c.id = r.cycle_id
      WHERE c.chat_id = ch.id
        AND p.carried_from_id IS NULL
        AND p.participant_id IS NOT NULL
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
  RETURN v;  -- NULL when the code is not an eligible SEO chat
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_seo_index() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_seo_chat(text) TO anon, authenticated;

COMMENT ON FUNCTION public.get_seo_index() IS
  'SEO: eligible official public chats (>=5 human opinions) for wedge static /opinions/<code> generation.';
COMMENT ON FUNCTION public.get_seo_chat(text) IS
  'SEO: public-safe content (question + anonymous opinions) for one chat''s static SEO page.';
