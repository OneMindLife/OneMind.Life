-- =============================================================================
-- Authoritative (SECURITY DEFINER) reads for the results/history detail screens.
-- =============================================================================
-- Root cause of the "0 voters" flicker: get_chat_detail_bootstrap is DEFINER and
-- renders the chat for anyone with the chat_id — including BEFORE a fresh
-- visitor's view+join-on-open commits. But the History / RoundRanking screens
-- read rating_completions DIRECTLY from the client, gated by RLS
-- (is_chat_participant). On a just-opened session that read returns 0 (the join
-- isn't committed yet) and the one-shot fetch never corrects → a confident,
-- wrong "0 voters".
--
-- The fix is to stop mixing authorities: these aggregate counts now come from
-- DEFINER RPCs, exactly like the bootstrap — server-computed, no dependence on
-- the caller's freshly-committed participant row. Same access posture as the
-- bootstrap (open by chat_id; aggregate, non-sensitive data only: winner text +
-- counts), so no new exposure surface. All read-only (no DML).
-- =============================================================================

-- Distinct people who finished rating a round, across BOTH surfaces
-- (rating_completions = matches mode, grid_rankings = 0-100 grid mode).
CREATE OR REPLACE FUNCTION public.get_round_voter_count(p_round_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT count(DISTINCT pid)::int FROM (
    SELECT participant_id AS pid FROM rating_completions WHERE round_id = p_round_id
    UNION
    SELECT participant_id FROM grid_rankings WHERE round_id = p_round_id
  ) x;
$$;

-- Per-round timeline for "How it converged": each round in order, its winning
-- answer, and how many people voted that round.
CREATE OR REPLACE FUNCTION public.get_round_history(p_chat_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'custom_id', r.custom_id,
        'winner', p.content,
        'voters', public.get_round_voter_count(r.id)
      )
      ORDER BY r.custom_id
    ),
    '[]'::jsonb
  )
  FROM rounds r
  JOIN cycles cy ON cy.id = r.cycle_id
  LEFT JOIN propositions p ON p.id = r.winning_proposition_id
  WHERE cy.chat_id = p_chat_id;
$$;

-- Ended-state header stats: rounds it took (>=2 = converged), people who
-- decided, and total head-to-head comparisons cast across the chat.
CREATE OR REPLACE FUNCTION public.get_chat_result_meta(p_chat_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'rounds', coalesce(
      (SELECT max(r.custom_id) FROM rounds r
         JOIN cycles cy ON cy.id = r.cycle_id WHERE cy.chat_id = p_chat_id), 0),
    'people', (SELECT count(*) FROM participants
         WHERE chat_id = p_chat_id AND status = 'active'),
    'comparisons', coalesce(
      (SELECT count(*) FROM pairwise_comparisons pc
         JOIN rounds r ON r.id = pc.round_id
         JOIN cycles cy ON cy.id = r.cycle_id WHERE cy.chat_id = p_chat_id), 0)
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_round_voter_count(bigint) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_round_history(bigint) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_chat_result_meta(bigint) TO anon, authenticated;
