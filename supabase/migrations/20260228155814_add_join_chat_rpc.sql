-- RPC to join a chat and return the participant record in one call.
-- Bypasses per-row RLS evaluation on both INSERT (participants) and SELECT
-- (is_chat_participant). Under 5,000 concurrent users joining the same chat,
-- per-row RLS causes statement_timeout due to connection pool saturation.
-- This SECURITY DEFINER function validates access once, performs an idempotent
-- insert, and returns the participant — replacing 2 separate PostgREST calls.

CREATE OR REPLACE FUNCTION public.join_chat_returning_participant(
  p_chat_id bigint,
  p_display_name text
)
RETURNS TABLE (
  id bigint,
  display_name text,
  status text,
  is_host boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_participant_id bigint;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Verify the chat allows direct joining
  IF NOT EXISTS (
    SELECT 1 FROM chats c
    WHERE c.id = p_chat_id
      AND c.is_active = true
      AND c.access_method IN ('public', 'code')
  ) THEN
    RAISE EXCEPTION 'Chat does not allow direct joining';
  END IF;

  -- Idempotent insert: if already a participant, do nothing
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (p_chat_id, v_user_id, p_display_name, false, 'active')
  ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
  DO NOTHING;

  -- Return the participant record (whether just inserted or already existed)
  RETURN QUERY
  SELECT p.id, p.display_name, p.status, p.is_host
  FROM participants p
  WHERE p.chat_id = p_chat_id
    AND p.user_id = v_user_id;
END;
$$;

-- Grant access to authenticated users
GRANT EXECUTE ON FUNCTION public.join_chat_returning_participant(bigint, text) TO authenticated;

COMMENT ON FUNCTION public.join_chat_returning_participant(bigint, text) IS
  'Joins a chat and returns the participant record. Uses SECURITY DEFINER to avoid per-row RLS evaluation. Idempotent — safe to call multiple times.';
