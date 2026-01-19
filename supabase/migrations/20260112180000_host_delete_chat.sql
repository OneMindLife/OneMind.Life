-- Migration: Allow host to delete their chat
-- Host is identified by creator_session_token matching the request header

-- Policy: Creator can delete their own chat
CREATE POLICY "Creator can delete own chat"
ON chats FOR DELETE
TO authenticated, anon
USING (
    creator_session_token = (current_setting('request.headers', true)::json->>'x-session-token')::uuid
);

COMMENT ON POLICY "Creator can delete own chat" ON chats IS 'Chat creator (host) can delete their own chat';
