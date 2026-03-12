-- Combined RPC to fetch current round state + submission status in one call.
-- Replaces 4 separate PostgREST queries that each go through per-row RLS:
--   1. GET /cycles?chat_id=eq.X (RLS: participants JOIN per row)
--   2. GET /rounds?cycle_id=eq.X (RLS: participants JOIN cycles per row)
--   3. GET /propositions?round_id=eq.X&participant_id=eq.X (RLS: 3-table JOIN per row)
--   4. GET /grid_rankings?round_id=eq.X&participant_id=eq.X (RLS: 3-table JOIN per row)
--
-- Under 100+ concurrent users in the same chat, these per-row RLS evaluations
-- cause statement_timeout (PG 57014). This SECURITY DEFINER function validates
-- participant access once, then queries everything without RLS overhead.

CREATE OR REPLACE FUNCTION public.get_round_state_for_participant(
  p_chat_id bigint,
  p_participant_id bigint
)
RETURNS TABLE (
  cycle_id bigint,
  round_id bigint,
  phase text,
  phase_ends_at timestamptz,
  custom_id int,
  has_submitted_proposition boolean,
  has_submitted_ratings boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cycle_id bigint;
  v_round_id bigint;
  v_phase text;
  v_phase_ends_at timestamptz;
  v_custom_id int;
  v_has_proposition boolean;
  v_has_ratings boolean;
BEGIN
  -- Verify the caller owns this participant and is in this chat
  IF NOT EXISTS (
    SELECT 1 FROM participants p
    WHERE p.id = p_participant_id
      AND p.chat_id = p_chat_id
      AND p.user_id = auth.uid()
      AND p.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Not an active participant in this chat';
  END IF;

  -- Get the most recent cycle for this chat
  SELECT c.id INTO v_cycle_id
  FROM cycles c
  WHERE c.chat_id = p_chat_id
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- No cycle yet (chat hasn't started)
  IF v_cycle_id IS NULL THEN
    RETURN;
  END IF;

  -- Get the most recent round for this cycle
  SELECT r.id, r.phase, r.phase_ends_at, r.custom_id
  INTO v_round_id, v_phase, v_phase_ends_at, v_custom_id
  FROM rounds r
  WHERE r.cycle_id = v_cycle_id
  ORDER BY r.custom_id DESC
  LIMIT 1;

  -- No round yet
  IF v_round_id IS NULL THEN
    RETURN;
  END IF;

  -- Check if participant has submitted a proposition this round
  -- (only new propositions, not carried forward)
  SELECT EXISTS (
    SELECT 1 FROM propositions pr
    WHERE pr.round_id = v_round_id
      AND pr.participant_id = p_participant_id
      AND pr.carried_from_id IS NULL
  ) INTO v_has_proposition;

  -- Check if participant has submitted any ratings this round
  SELECT EXISTS (
    SELECT 1 FROM grid_rankings gr
    WHERE gr.round_id = v_round_id
      AND gr.participant_id = p_participant_id
  ) INTO v_has_ratings;

  -- Return combined state
  cycle_id := v_cycle_id;
  round_id := v_round_id;
  phase := v_phase;
  phase_ends_at := v_phase_ends_at;
  custom_id := v_custom_id;
  has_submitted_proposition := v_has_proposition;
  has_submitted_ratings := v_has_ratings;
  RETURN NEXT;
END;
$$;

-- Grant access to authenticated users
GRANT EXECUTE ON FUNCTION public.get_round_state_for_participant(bigint, bigint) TO authenticated;

COMMENT ON FUNCTION public.get_round_state_for_participant(bigint, bigint) IS
  'Returns current round state and submission status for a participant. Replaces 4 separate RLS-evaluated queries with 1 SECURITY DEFINER call.';
