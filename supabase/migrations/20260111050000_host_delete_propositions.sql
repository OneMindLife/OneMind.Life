-- Allow hosts to delete propositions during proposing phase only
-- Host can see proposition content but NOT who submitted it (anonymity preserved)

-- Add DELETE policy for propositions
CREATE POLICY "Host can delete propositions during proposing" ON "public"."propositions"
FOR DELETE USING (
    -- Service role can always delete
    (current_setting('role'::text, true) = 'service_role'::text)
    OR (
        -- Check that the round is in proposing phase
        EXISTS (
            SELECT 1 FROM rounds r
            WHERE r.id = propositions.round_id
            AND r.phase = 'proposing'
        )
        AND
        -- Check that the requester is the host of this chat
        EXISTS (
            SELECT 1 FROM participants p
            JOIN rounds r ON r.id = propositions.round_id
            JOIN cycles c ON c.id = r.cycle_id
            WHERE p.chat_id = c.chat_id
            AND p.is_host = TRUE
            AND p.session_token = (current_setting('request.headers', true)::json->>'x-session-token')::uuid
        )
    )
);

-- Add index to improve performance of host lookups
CREATE INDEX IF NOT EXISTS idx_participants_host_session
ON participants(chat_id, is_host, session_token)
WHERE is_host = TRUE;

COMMENT ON POLICY "Host can delete propositions during proposing" ON "public"."propositions" IS
'Hosts can delete inappropriate propositions, but only during the proposing phase.
Once rating begins, propositions are locked. Host cannot see who submitted each proposition.';
