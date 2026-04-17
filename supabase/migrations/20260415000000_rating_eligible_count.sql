-- Returns the number of participants eligible to rate in a chat.
-- Excludes AI agents when rating_agent_count = 0.
-- When rating_agent_count > 0, agents can rate so they're included.
CREATE OR REPLACE FUNCTION public.get_rating_eligible_count(p_chat_id BIGINT)
RETURNS INTEGER
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
    SELECT COUNT(*)::INTEGER
    FROM public.participants p
    JOIN public.chats c ON c.id = p.chat_id
    WHERE p.chat_id = p_chat_id
      AND p.status = 'active'
      AND (
        p.is_agent = false
        OR c.rating_agent_count > 0
      );
$$;

COMMENT ON FUNCTION public.get_rating_eligible_count IS
'Returns the count of participants eligible to rate. Excludes AI agents when rating_agent_count = 0.';
