-- Fix DELETE policy on chats to use auth.uid() instead of session token
-- The original policy used creator_session_token but we migrated to auth.uid()

DROP POLICY IF EXISTS "Creator can delete own chat" ON chats;

CREATE POLICY "Creator can delete own chat"
ON chats FOR DELETE
TO authenticated
USING (
    creator_id = auth.uid()
);

COMMENT ON POLICY "Creator can delete own chat" ON chats IS 'Chat creator (host) can delete their own chat using auth.uid()';
