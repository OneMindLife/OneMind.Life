-- Function to approve join requests (bypasses RLS with SECURITY DEFINER)
-- This allows hosts to create participants on behalf of requesters
--
-- Architecture:
-- - Leave: DELETE participant record (so they can rejoin cleanly)
-- - Kick: UPDATE status='kicked' (so we can block/reactivate)
-- This means only 'kicked' or 'active' participants have records.

CREATE OR REPLACE FUNCTION approve_join_request(p_request_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_is_host BOOLEAN;
  v_existing_participant RECORD;
BEGIN
  -- Get the request
  SELECT * INTO v_request
  FROM join_requests
  WHERE id = p_request_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Join request not found or already processed';
  END IF;

  -- Verify caller is host of this chat
  SELECT EXISTS(
    SELECT 1 FROM participants
    WHERE chat_id = v_request.chat_id
    AND session_token = get_session_token()
    AND is_host = TRUE
    AND status = 'active'
  ) INTO v_is_host;

  IF NOT v_is_host THEN
    RAISE EXCEPTION 'Only the host can approve join requests';
  END IF;

  -- Check if participant already exists (only kicked users have residual records)
  SELECT * INTO v_existing_participant
  FROM participants
  WHERE chat_id = v_request.chat_id
  AND (
    (v_request.session_token IS NOT NULL AND session_token = v_request.session_token)
    OR (v_request.user_id IS NOT NULL AND user_id = v_request.user_id)
  );

  IF FOUND THEN
    -- Participant exists - reactivate if kicked or left (legacy records)
    IF v_existing_participant.status IN ('kicked', 'left') THEN
      UPDATE participants
      SET status = 'active',
          display_name = v_request.display_name
      WHERE id = v_existing_participant.id;
    END IF;
    -- If already active, just mark the request as approved (duplicate request)
  ELSE
    -- Create new participant (SECURITY DEFINER bypasses RLS)
    INSERT INTO participants (
      chat_id,
      display_name,
      session_token,
      user_id,
      is_authenticated,
      is_host,
      status
    ) VALUES (
      v_request.chat_id,
      v_request.display_name,
      v_request.session_token,
      v_request.user_id,
      v_request.is_authenticated,
      FALSE,
      'active'
    );
  END IF;

  -- Update request status
  UPDATE join_requests
  SET status = 'approved',
      resolved_at = NOW()
  WHERE id = p_request_id;
END;
$$;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION approve_join_request(BIGINT) TO authenticated, anon;

COMMENT ON FUNCTION approve_join_request IS
'Approves a join request. Only callable by the host of the chat.
Creates a participant record and marks the request as approved.';
