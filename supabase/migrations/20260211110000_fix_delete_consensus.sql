-- =============================================================================
-- FIX: delete_consensus must check "latest completed" BEFORE clearing,
-- and must also clean up subsequent incomplete cycles.
-- =============================================================================

CREATE OR REPLACE FUNCTION delete_consensus(p_cycle_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_chat_id BIGINT;
  v_is_host BOOLEAN;
  v_latest_completed_cycle_id BIGINT;
  v_was_latest BOOLEAN := FALSE;
  v_new_round_id BIGINT;
  v_restarted BOOLEAN := FALSE;
BEGIN
  -- Verify caller is authenticated
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Get cycle's chat_id
  SELECT chat_id INTO v_chat_id
  FROM cycles
  WHERE id = p_cycle_id;

  IF v_chat_id IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  -- Verify caller is host
  SELECT is_host INTO v_is_host
  FROM participants
  WHERE chat_id = v_chat_id
    AND user_id = v_caller_id
    AND status = 'active';

  IF v_is_host IS NOT TRUE THEN
    RAISE EXCEPTION 'Only the host can delete a consensus';
  END IF;

  -- Check if this is the latest completed cycle BEFORE clearing it
  SELECT id INTO v_latest_completed_cycle_id
  FROM cycles
  WHERE chat_id = v_chat_id
    AND completed_at IS NOT NULL
  ORDER BY completed_at DESC
  LIMIT 1;

  v_was_latest := (v_latest_completed_cycle_id IS NOT NULL AND v_latest_completed_cycle_id = p_cycle_id);

  -- Clear the cycle's winning proposition and completion
  UPDATE cycles
  SET winning_proposition_id = NULL,
      completed_at = NULL
  WHERE id = p_cycle_id;

  -- Delete all rounds in this cycle (CASCADE handles propositions, grid_rankings,
  -- round_winners, round_skips, rating_skips)
  DELETE FROM rounds WHERE cycle_id = p_cycle_id;

  -- If this was the latest completed cycle, clean up subsequent cycles and restart
  IF v_was_latest THEN
    -- Delete all subsequent incomplete cycles (follow-ups to the deleted consensus)
    -- Their rounds are deleted by CASCADE
    DELETE FROM rounds WHERE cycle_id IN (
      SELECT id FROM cycles
      WHERE chat_id = v_chat_id AND id > p_cycle_id AND completed_at IS NULL
    );
    DELETE FROM cycles
    WHERE chat_id = v_chat_id AND id > p_cycle_id AND completed_at IS NULL;

    -- Create a fresh round for this cycle (in proposing or waiting phase)
    -- This triggers agent_orchestrator_on_phase_change automatically
    v_new_round_id := create_round_for_cycle(p_cycle_id, v_chat_id, 1);
    v_restarted := TRUE;
  END IF;

  RETURN jsonb_build_object(
    'restarted', v_restarted,
    'new_round_id', v_new_round_id
  );
END;
$$;

COMMENT ON FUNCTION delete_consensus(BIGINT) IS
  'Deletes a consensus by clearing cycle winner and removing all rounds. '
  'If this was the latest completed cycle, also cleans up subsequent incomplete '
  'cycles and restarts with a fresh round in proposing phase.';
