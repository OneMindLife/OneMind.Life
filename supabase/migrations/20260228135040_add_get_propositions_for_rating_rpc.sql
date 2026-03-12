-- RPC to get propositions for rating, bypassing RLS per-row evaluation.
-- The propositions RLS policy uses an EXISTS subquery with a 3-table JOIN
-- (propositions → rounds → cycles → participants) that is evaluated per-row.
-- Under concurrent load (100+ users hitting the same round), this causes
-- statement_timeout errors (Postgres error 57014).
-- This SECURITY DEFINER function validates chat membership once upfront,
-- then returns all propositions without per-row RLS overhead.

CREATE OR REPLACE FUNCTION public.get_propositions_for_rating(
  p_round_id bigint,
  p_participant_id bigint
)
RETURNS TABLE (
  id bigint,
  content text,
  participant_id bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify the caller is a participant in the chat that owns this round
  IF NOT EXISTS (
    SELECT 1
    FROM participants p
    JOIN cycles c ON c.chat_id = p.chat_id
    JOIN rounds r ON r.cycle_id = c.id
    WHERE r.id = p_round_id
      AND p.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a participant in this chat';
  END IF;

  -- Return all propositions for the round except the caller's own
  RETURN QUERY
    SELECT pr.id, pr.content, pr.participant_id
    FROM propositions pr
    WHERE pr.round_id = p_round_id
      AND pr.participant_id != p_participant_id;
END;
$$;

-- Grant access to authenticated users
GRANT EXECUTE ON FUNCTION public.get_propositions_for_rating(bigint, bigint) TO authenticated;

COMMENT ON FUNCTION public.get_propositions_for_rating(bigint, bigint) IS
  'Returns propositions for rating in a round, excluding the callers own. Uses SECURITY DEFINER to avoid per-row RLS evaluation.';
