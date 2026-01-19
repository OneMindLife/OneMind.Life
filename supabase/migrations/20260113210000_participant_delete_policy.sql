-- Add DELETE policy for participants to allow users to leave chats
-- Users can only delete their own participant record

CREATE POLICY "Participants can leave chat"
ON participants FOR DELETE
USING (
  session_token = get_session_token()
  OR (user_id IS NOT NULL AND user_id = auth.uid())
);

COMMENT ON POLICY "Participants can leave chat" ON participants IS
'Allows participants to delete their own record (leave chat)';
