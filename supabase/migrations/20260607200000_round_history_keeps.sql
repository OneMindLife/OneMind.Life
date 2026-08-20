-- =============================================================================
-- get_round_history: add per-round "keeps" (affirmations) alongside "voters".
-- =============================================================================
-- A round can be decided two ways: by VOTING (it had alternatives → people
-- voted in pairwise matches) or by KEEPING (no alternatives → people kept the
-- carried answer; nobody voted). The history/results UI needs to show the right
-- participation number — "N voted" vs "N kept it" — instead of a misleading
-- "0 voters" for a kept round. So return both counts per round.
-- =============================================================================

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
        'voters', public.get_round_voter_count(r.id),
        'keeps', (SELECT count(*)::int FROM affirmations a WHERE a.round_id = r.id)
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
