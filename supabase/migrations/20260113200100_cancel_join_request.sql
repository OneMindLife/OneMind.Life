-- =============================================================================
-- Migration: Cancel Join Request Function
-- =============================================================================
-- Adds 'cancelled' status and function for requesters to cancel their own
-- pending join requests.
-- =============================================================================

-- Update status constraint to include 'cancelled'
ALTER TABLE join_requests DROP CONSTRAINT IF EXISTS join_requests_status_check;
ALTER TABLE join_requests ADD CONSTRAINT join_requests_status_check
  CHECK (status = ANY (ARRAY['pending', 'approved', 'denied', 'cancelled']));

-- =============================================================================
-- Function: cancel_join_request
-- =============================================================================
-- Allows a requester to cancel their own pending join request.
-- Uses SECURITY DEFINER to bypass RLS for the update operation.
-- =============================================================================
CREATE OR REPLACE FUNCTION cancel_join_request(p_request_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_session_token UUID;
BEGIN
  -- Get the session token from request headers
  v_session_token := get_session_token();

  -- Get the request (must be pending)
  SELECT * INTO v_request
  FROM join_requests
  WHERE id = p_request_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Join request not found or already processed';
  END IF;

  -- Verify caller owns this request (by session_token)
  IF v_request.session_token IS NULL OR v_request.session_token != v_session_token THEN
    RAISE EXCEPTION 'You can only cancel your own join requests';
  END IF;

  -- Update request status to cancelled
  UPDATE join_requests
  SET status = 'cancelled',
      resolved_at = NOW()
  WHERE id = p_request_id;
END;
$$;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION cancel_join_request(BIGINT) TO authenticated, anon;
