-- =============================================================================
-- Skip Rating With Cleanup
-- =============================================================================
-- Allows users to skip rating even after placing intermediate rankings.
-- Atomically: deletes any grid_rankings, then inserts a rating_skip.
-- Called from the rating screen's skip button.

CREATE OR REPLACE FUNCTION skip_rating_with_cleanup(
  p_round_id BIGINT,
  p_participant_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_round_phase text;
  v_skip_count integer;
  v_total_participants integer;
  v_rating_minimum integer;
  v_chat_id bigint;
BEGIN
  -- Verify the participant belongs to the calling user
  SELECT user_id INTO v_user_id
  FROM participants WHERE id = p_participant_id;

  IF v_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Participant does not belong to current user';
  END IF;

  -- Verify round is in rating phase
  SELECT r.phase, c.chat_id INTO v_round_phase, v_chat_id
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE r.id = p_round_id;

  IF v_round_phase IS DISTINCT FROM 'rating' THEN
    RAISE EXCEPTION 'Round is not in rating phase';
  END IF;

  -- Check not already skipped
  IF EXISTS (
    SELECT 1 FROM rating_skips
    WHERE round_id = p_round_id AND participant_id = p_participant_id
  ) THEN
    RAISE EXCEPTION 'Already skipped this round';
  END IF;

  -- Check skip quota
  SELECT COUNT(*) INTO v_skip_count FROM rating_skips WHERE round_id = p_round_id;
  SELECT COUNT(*) INTO v_total_participants FROM participants WHERE chat_id = v_chat_id AND status = 'active';
  SELECT rating_minimum INTO v_rating_minimum FROM chats WHERE id = v_chat_id;
  v_rating_minimum := COALESCE(v_rating_minimum, 2);

  IF v_skip_count >= (v_total_participants - v_rating_minimum) THEN
    RAISE EXCEPTION 'Rating skip quota exceeded';
  END IF;

  -- Delete any intermediate grid_rankings for this round + participant
  DELETE FROM grid_rankings
  WHERE participant_id = p_participant_id
    AND proposition_id IN (
      SELECT id FROM propositions WHERE round_id = p_round_id
    );

  -- Insert the rating skip
  INSERT INTO rating_skips (round_id, participant_id)
  VALUES (p_round_id, p_participant_id);
END;
$$;

COMMENT ON FUNCTION skip_rating_with_cleanup IS
  'Atomically skips rating: deletes any intermediate grid_rankings, then inserts a rating_skip. '
  'Validates ownership, phase, and skip quota. Called from the rating screen skip button.';
