-- Fix: chat_allows_direct_join was missing personal_code access method
-- and didn't allow creators to join their own chat.
-- This caused 403 when creating a personal_code or invite_only chat
-- because the host INSERT into participants was blocked by RLS.

CREATE OR REPLACE FUNCTION chat_allows_direct_join(p_chat_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM chats c
        WHERE c.id = p_chat_id
        AND c.is_active = true
        AND (
            c.access_method IN ('public', 'code', 'personal_code')
            OR c.creator_id = auth.uid()
        )
    );
$$;
