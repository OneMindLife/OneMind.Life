-- RPC to upsert a grid ranking, bypassing RLS per-row evaluation.
-- The grid_rankings INSERT/UPDATE RLS policies call owns_participant() and
-- participant_can_access_round() per-row. Under concurrent load (100+ users
-- rating in the same round), this causes statement_timeout errors (PG 57014).
-- This SECURITY DEFINER function validates ownership and access once upfront,
-- then performs the upsert without per-row RLS overhead.

CREATE OR REPLACE FUNCTION public.upsert_grid_ranking(
  p_round_id bigint,
  p_participant_id bigint,
  p_proposition_id bigint,
  p_grid_position real
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify the caller owns this participant
  IF NOT EXISTS (
    SELECT 1
    FROM participants p
    WHERE p.id = p_participant_id
      AND p.user_id = auth.uid()
      AND p.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Not the owner of this participant';
  END IF;

  -- Verify the participant can access this round (same chat)
  IF NOT EXISTS (
    SELECT 1
    FROM participants p
    JOIN cycles c ON c.chat_id = p.chat_id
    JOIN rounds r ON r.cycle_id = c.id
    WHERE p.id = p_participant_id
      AND r.id = p_round_id
  ) THEN
    RAISE EXCEPTION 'Participant cannot access this round';
  END IF;

  -- Upsert the grid ranking
  INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
  VALUES (p_round_id, p_proposition_id, p_participant_id, p_grid_position)
  ON CONFLICT (round_id, proposition_id, participant_id)
  DO UPDATE SET grid_position = EXCLUDED.grid_position;
END;
$$;

-- Grant access to authenticated users
GRANT EXECUTE ON FUNCTION public.upsert_grid_ranking(bigint, bigint, bigint, real) TO authenticated;

COMMENT ON FUNCTION public.upsert_grid_ranking(bigint, bigint, bigint, real) IS
  'Upserts a grid ranking for a proposition. Uses SECURITY DEFINER to avoid per-row RLS evaluation.';
