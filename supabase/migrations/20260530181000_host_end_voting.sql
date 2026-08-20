-- Quick-create real chats: let the host end voting and finalize the result on demand.
--
-- Real quick-create chats have NO timer (see seed change) and don't silently auto-seal
-- (late-joiner safety). The host decides when voting is over via this RPC, which tallies
-- the votes AS THEY STAND and locks in the winner — the same finalize process-timers and
-- the preview trigger use (complete_round_with_winner), so the result is computed
-- identically no matter who triggers it.
--
-- Scoped to quick-create chats (max_cycles IS NOT NULL) so it can't be used to force-end
-- rounds in normal continuous chats. Host-gated (service role allowed for tests/automation).
-- Idempotent: complete_round_with_winner bails if the round is already completed.

CREATE OR REPLACE FUNCTION public.host_end_voting(p_chat_id BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_service_role BOOLEAN;
  v_caller UUID;
  v_is_host BOOLEAN;
  v_max_cycles INTEGER;
  v_ended TIMESTAMPTZ;
  v_cycle_id BIGINT;
  v_round_id BIGINT;
  v_phase TEXT;
  v_completed TIMESTAMPTZ;
BEGIN
  -- COALESCE: an unset request.jwt.claim.role returns NULL, and `FALSE OR NULL`
  -- is NULL, which would make `IF NOT v_is_service_role` skip the authz block.
  v_is_service_role := COALESCE(current_setting('role', true) = 'service_role', false)
                    OR COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', false);

  -- Quick-create only.
  SELECT max_cycles, ended_at INTO v_max_cycles, v_ended FROM chats WHERE id = p_chat_id;
  IF v_max_cycles IS NULL THEN
    RAISE EXCEPTION 'host_end_voting is only available for quick-create chats';
  END IF;

  -- Authz: active host (or service role).
  IF NOT v_is_service_role THEN
    v_caller := auth.uid();
    IF v_caller IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;
    SELECT is_host INTO v_is_host
    FROM participants
    WHERE chat_id = p_chat_id AND user_id = v_caller AND status = 'active';
    IF v_is_host IS NOT TRUE THEN
      RAISE EXCEPTION 'Only the host can end voting';
    END IF;
  END IF;

  -- Already finished (e.g. a double-tap, or the all-done path beat us): the cycle is
  -- completed so there's no "active" cycle to find — return success idempotently.
  IF v_ended IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'already_completed', true);
  END IF;

  -- Current cycle + latest round.
  SELECT id INTO v_cycle_id
  FROM cycles WHERE chat_id = p_chat_id AND completed_at IS NULL
  ORDER BY id DESC LIMIT 1;
  IF v_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No active cycle to finalize';
  END IF;

  SELECT id, phase, completed_at INTO v_round_id, v_phase, v_completed
  FROM rounds WHERE cycle_id = v_cycle_id
  ORDER BY id DESC LIMIT 1;
  IF v_round_id IS NULL THEN
    RAISE EXCEPTION 'No active round to finalize';
  END IF;

  IF v_completed IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'round_id', v_round_id, 'already_completed', true);
  END IF;

  -- Only "voting" (rating) can be ended this way — proposing has no votes to tally,
  -- and the host can't manually advance proposing (mirrors real OneMind).
  IF v_phase <> 'rating' THEN
    RAISE EXCEPTION 'Voting can only be ended during the rating phase (current phase: %)', v_phase;
  END IF;

  -- Serialize against a concurrent auto-finalize on the same round.
  PERFORM pg_advisory_xact_lock(v_round_id);
  PERFORM complete_round_with_winner(v_round_id);

  RETURN jsonb_build_object('success', true, 'round_id', v_round_id);
END;
$$;

COMMENT ON FUNCTION public.host_end_voting(BIGINT) IS
  'Host-only (quick-create chats): end the rating phase now, tally votes as they stand, and lock in the winner via complete_round_with_winner. Idempotent.';

GRANT EXECUTE ON FUNCTION public.host_end_voting(BIGINT) TO authenticated, anon;
