-- Answer-first SEO content (Joel, 2026-07-15): return the chat's MAIN FLOOR
-- opinions RANKED by head-to-head global_score (best first), not by created_at,
-- and carry the score. This lets /opinions/<code> lead with "the group's top
-- take — ranked #1 of N", the extractable answer that both search snippets and
-- AI answer-engines (ChatGPT/Perplexity/AI Overviews) lift. Root-cycle only
-- (parent_proposition_id IS NULL) so the page is one coherent ranked floor, not
-- a flat mix of every sub-thread. See docs/SEO_CONTENT_STRATEGY.md +
-- docs/ONEMIND_CONCEPT.md (preference-oracle-for-AI thesis).
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
  RETURN v;  -- NULL when the code is not an eligible SEO chat
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_seo_chat(text) TO anon, authenticated;

COMMENT ON FUNCTION public.get_seo_chat(text) IS
  'SEO/AEO: main-floor opinions for a chat, ranked by head-to-head global_score (best first) with the score. Powers the answer-first /opinions/<code> page.';
