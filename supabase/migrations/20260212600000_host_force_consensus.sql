-- =============================================================================
-- Host Force Consensus
-- =============================================================================
-- Allows the host to force a proposition directly as consensus, bypassing
-- the normal voting flow. Useful when agents reach consensus on tasks that
-- require human action and the host needs to signal "task completed."
-- =============================================================================

-- 1. Add host_override column to cycles
ALTER TABLE cycles ADD COLUMN host_override BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN cycles.host_override IS
  'TRUE when this cycle''s consensus was forced by the host (not through normal voting).';

-- 2. Create the host_force_consensus RPC function
CREATE OR REPLACE FUNCTION host_force_consensus(p_chat_id BIGINT, p_content TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_is_host BOOLEAN;
  v_participant_id BIGINT;
  v_current_cycle_id BIGINT;
  v_current_round_id BIGINT;
  v_proposition_id BIGINT;
BEGIN
  -- Verify caller is authenticated
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Verify caller is host and get their participant_id
  SELECT id, is_host INTO v_participant_id, v_is_host
  FROM participants
  WHERE chat_id = p_chat_id
    AND user_id = v_caller_id
    AND status = 'active';

  IF v_is_host IS NOT TRUE THEN
    RAISE EXCEPTION 'Only the host can force a consensus';
  END IF;

  -- Validate content
  IF p_content IS NULL OR TRIM(p_content) = '' THEN
    RAISE EXCEPTION 'Content cannot be empty';
  END IF;

  -- Find the current (incomplete) cycle for this chat
  SELECT id INTO v_current_cycle_id
  FROM cycles
  WHERE chat_id = p_chat_id
    AND completed_at IS NULL
  ORDER BY id DESC
  LIMIT 1;

  IF v_current_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No active cycle found for this chat';
  END IF;

  -- Find the current round in this cycle
  SELECT id INTO v_current_round_id
  FROM rounds
  WHERE cycle_id = v_current_cycle_id
  ORDER BY id DESC
  LIMIT 1;

  IF v_current_round_id IS NULL THEN
    RAISE EXCEPTION 'No active round found for this cycle';
  END IF;

  -- Create a proposition with the host's content in the current round
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_current_round_id, v_participant_id, TRIM(p_content))
  RETURNING id INTO v_proposition_id;

  -- Set this proposition as the cycle winner and mark completed
  -- The on_cycle_winner_set trigger will auto-create next cycle + round
  UPDATE cycles
  SET winning_proposition_id = v_proposition_id,
      completed_at = NOW(),
      host_override = TRUE
  WHERE id = v_current_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_current_cycle_id,
    'proposition_id', v_proposition_id
  );
END;
$$;

COMMENT ON FUNCTION host_force_consensus(BIGINT, TEXT) IS
  'Allows host to force a proposition directly as consensus, bypassing voting. '
  'Creates a proposition in the current round, sets it as cycle winner, and marks '
  'host_override=TRUE. The on_cycle_winner_set trigger auto-creates the next cycle.';

-- 3. Security grants
REVOKE EXECUTE ON FUNCTION host_force_consensus(BIGINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION host_force_consensus(BIGINT, TEXT) TO authenticated, service_role;
