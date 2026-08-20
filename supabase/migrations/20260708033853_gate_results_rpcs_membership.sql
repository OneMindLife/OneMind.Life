-- =============================================================================
-- SECURITY: gate the results/history DEFINER RPCs on chat membership.
-- =============================================================================
-- Vulnerability (found 2026-07-07): get_round_history / get_chat_result_meta /
-- get_round_voter_count are SECURITY DEFINER, GRANTed to anon, and had NO
-- membership check — "open by chat_id". get_round_history returns the WINNING
-- proposition text (p.content) of every round. Because chat_id is a small
-- sequential integer, an unauthenticated caller could enumerate every chat on
-- the platform and read each one's winning decision + vote/people/comparison
-- counts, including PRIVATE (access_method <> 'public') chats. Confirmed by
-- calling get_round_history(1185) as the anon role with no JWT.
--
-- The original migration (20260607180000) rationalized these as "aggregate,
-- non-sensitive data only ... same access posture as the bootstrap." That was
-- wrong twice: (1) winner text is message content, not an aggregate; (2) the
-- bootstrap (get_chat_detail_bootstrap) actually DOES gate — participant (any
-- status) OR public — so these RPCs were strictly MORE open than the thing they
-- claimed parity with.
--
-- Fix: apply the bootstrap's exact gate. A caller may read results only if they
-- are a participant of the chat (ANY status — preserves the "just-opened
-- session" fix these RPCs were built for; a user viewing results has already
-- joined) OR the chat is public. Otherwise the RPCs return empty/zero, never
-- content. Read-only, no behavior change for legitimate members.
-- =============================================================================

-- Shared gate helper. STABLE + DEFINER so it evaluates auth.uid() and reads
-- chats/participants regardless of the caller's own RLS. status is NOT filtered
-- (matches the bootstrap's "any status" posture).
CREATE OR REPLACE FUNCTION public.can_read_chat_results(p_chat_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    (current_setting('role', true) = 'service_role')
    OR EXISTS (SELECT 1 FROM public.chats c
                 WHERE c.id = p_chat_id AND c.access_method = 'public')
    OR EXISTS (SELECT 1 FROM public.participants p
                 WHERE p.chat_id = p_chat_id AND p.user_id = auth.uid());
$$;

GRANT EXECUTE ON FUNCTION public.can_read_chat_results(BIGINT) TO anon, authenticated;

-- 1. Voter count for a round — gate via the round's chat.
CREATE OR REPLACE FUNCTION public.get_round_voter_count(p_round_id BIGINT)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN public.can_read_chat_results(
           (SELECT cy.chat_id FROM public.rounds r
              JOIN public.cycles cy ON cy.id = r.cycle_id
              WHERE r.id = p_round_id))
    THEN (
      SELECT count(DISTINCT pid)::int FROM (
        SELECT participant_id AS pid FROM public.rating_completions WHERE round_id = p_round_id
        UNION
        SELECT participant_id FROM public.grid_rankings WHERE round_id = p_round_id
      ) x)
    ELSE 0
  END;
$$;

-- 2. Round history (winner text + voters per round) — gate on the chat.
CREATE OR REPLACE FUNCTION public.get_round_history(p_chat_id BIGINT)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.can_read_chat_results(p_chat_id) THEN coalesce(
    (SELECT jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'custom_id', r.custom_id,
          'winner', p.content,
          'voters', public.get_round_voter_count(r.id)
        )
        ORDER BY r.custom_id)
     FROM public.rounds r
     JOIN public.cycles cy ON cy.id = r.cycle_id
     LEFT JOIN public.propositions p ON p.id = r.winning_proposition_id
     WHERE cy.chat_id = p_chat_id),
    '[]'::jsonb)
  ELSE '[]'::jsonb END;
$$;

-- 3. Ended-state header stats — gate on the chat.
CREATE OR REPLACE FUNCTION public.get_chat_result_meta(p_chat_id BIGINT)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.can_read_chat_results(p_chat_id) THEN jsonb_build_object(
    'rounds', coalesce(
      (SELECT max(r.custom_id) FROM public.rounds r
         JOIN public.cycles cy ON cy.id = r.cycle_id WHERE cy.chat_id = p_chat_id), 0),
    'people', (SELECT count(*) FROM public.participants
         WHERE chat_id = p_chat_id AND status = 'active'),
    'comparisons', coalesce(
      (SELECT count(*) FROM public.pairwise_comparisons pc
         JOIN public.rounds r ON r.id = pc.round_id
         JOIN public.cycles cy ON cy.id = r.cycle_id WHERE cy.chat_id = p_chat_id), 0)
  )
  ELSE NULL END;
$$;
