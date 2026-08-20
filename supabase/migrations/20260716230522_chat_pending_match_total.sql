-- Total pending pairwise MATCHES this participant still owes across the WHOLE
-- chat (every round in every cycle), floor(unplaced/2) summed. Powers the
-- "N more votes across this chat still need you" pull. Takes any round in the
-- chat and resolves the chat from it, so the client can call it with the round
-- it already has.
CREATE OR REPLACE FUNCTION public.get_chat_pending_match_total(
  p_round_id bigint,
  p_participant_id bigint
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH chat AS (
    SELECT cy.chat_id
    FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
    WHERE r.id = p_round_id
  )
  SELECT COALESCE(sum(floor(u.unplaced / 2)), 0)::bigint
  FROM rounds r
  JOIN cycles cy ON cy.id = r.cycle_id
  JOIN chat c ON c.chat_id = cy.chat_id
  CROSS JOIN LATERAL (
    SELECT count(*)::bigint AS unplaced
    FROM propositions cp
    WHERE cp.round_id = r.id
      AND cp.carried_from_id IS NULL
      AND cp.participant_id IS DISTINCT FROM p_participant_id
      AND NOT EXISTS (
        SELECT 1 FROM pairwise_comparisons pc
        WHERE pc.round_id = r.id
          AND pc.participant_id = p_participant_id
          AND (pc.winner_proposition_id = cp.id
               OR pc.loser_proposition_id = cp.id)
      )
  ) u;
$$;

GRANT EXECUTE ON FUNCTION public.get_chat_pending_match_total(bigint, bigint)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_chat_pending_match_total(bigint, bigint) IS
  'Total pending pairwise matches this participant owes across the WHOLE chat (resolved from any round in it), floor(unplaced/2) summed. Powers the chat-wide "keep going" pull. Per-user, depletes as they vote.';
