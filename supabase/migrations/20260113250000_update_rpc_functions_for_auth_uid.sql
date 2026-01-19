-- =============================================================================
-- Migration: Update RPC Functions to use auth.uid()
-- =============================================================================
-- Updates approve_join_request and cancel_join_request functions to use
-- auth.uid() instead of get_session_token() for Realtime compatibility.
-- =============================================================================

-- =============================================================================
-- Function: approve_join_request (updated)
-- =============================================================================
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

  -- Verify caller is host of this chat (using auth.uid())
  SELECT EXISTS(
    SELECT 1 FROM participants
    WHERE chat_id = v_request.chat_id
    AND user_id = auth.uid()
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
  AND user_id = v_request.user_id;

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
      user_id,
      is_authenticated,
      is_host,
      status
    ) VALUES (
      v_request.chat_id,
      v_request.display_name,
      v_request.user_id,
      TRUE,  -- All auth.uid() users are authenticated
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

-- =============================================================================
-- Function: cancel_join_request (updated)
-- =============================================================================
CREATE OR REPLACE FUNCTION cancel_join_request(p_request_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
BEGIN
  -- Get the request (must be pending)
  SELECT * INTO v_request
  FROM join_requests
  WHERE id = p_request_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Join request not found or already processed';
  END IF;

  -- Verify caller owns this request (by user_id via auth.uid())
  IF v_request.user_id IS NULL OR v_request.user_id != auth.uid() THEN
    RAISE EXCEPTION 'You can only cancel your own join requests';
  END IF;

  -- Update request status to cancelled
  UPDATE join_requests
  SET status = 'cancelled',
      resolved_at = NOW()
  WHERE id = p_request_id;
END;
$$;

-- Grants already exist from original migrations
