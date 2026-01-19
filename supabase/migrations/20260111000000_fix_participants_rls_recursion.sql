-- Fix infinite recursion in participants RLS policy
-- The previous policy used a subquery on participants table which caused recursion
-- Solution: Use a security definer function to bypass RLS when checking membership

-- Create a security definer function to check if user is in a chat
-- This bypasses RLS to avoid recursion
CREATE OR REPLACE FUNCTION public.is_chat_participant(p_chat_id bigint)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.participants
    WHERE chat_id = p_chat_id
    AND session_token = get_session_token()
    AND status = 'active'
  );
$$;

-- Grant execute to authenticated and anon roles
GRANT EXECUTE ON FUNCTION public.is_chat_participant(bigint) TO authenticated, anon;

-- Drop the problematic policy
DROP POLICY IF EXISTS "Chat participants can view participants" ON public.participants;

-- Create a simpler policy using the security definer function
-- Users can view participants if:
-- 1. They are service role, OR
-- 2. They are viewing their own participant record, OR
-- 3. They are a participant in the same chat (checked via security definer function)
CREATE POLICY "Participants can view same chat participants"
  ON public.participants
  FOR SELECT
  USING (
    current_setting('role', true) = 'service_role'
    OR session_token = get_session_token()
    OR is_chat_participant(chat_id)
  );
