-- =============================================================================
-- MIGRATION: Fix chats SELECT policy to allow creators to see their own chat
-- =============================================================================
-- The security hardening wave 2 (20260207200000) restricted chats SELECT to:
--   service_role OR public+active chats OR participants
--
-- But when creating a chat, the creator_id is set before the participant row
-- is inserted. PostgREST's `return=representation` triggers a SELECT on the
-- just-inserted row, which fails because the creator isn't a participant yet.
--
-- Fix: Add `creator_id = auth.uid()` to the SELECT policy.
-- =============================================================================

DROP POLICY IF EXISTS "Users can view relevant chats" ON public.chats;

CREATE POLICY "Users can view relevant chats" ON public.chats
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (is_active = true AND access_method = 'public')
    OR (creator_id = auth.uid())
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = chats.id
        AND p.user_id = auth.uid()
    )
);
