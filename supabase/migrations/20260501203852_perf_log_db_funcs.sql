-- =============================================================================
-- MIGRATION: instrument host_resume_chat + skip_rating_with_cleanup with perf_logs
-- =============================================================================
-- Each function gets a `start` row at entry and an `end` row at exit (with
-- duration_ms). If the caller passes a `p_correlation_id` (Flutter's already
-- looking at this RPC), the timeline ties to the same correlation id as the
-- Flutter-side start/end pair.
--
-- We wrap in EXCEPTION WHEN OTHERS at the log_perf call sites — logging
-- failure must never break the actual RPC.
--
-- Body logic is unchanged. Only the entry/exit instrumentation is added.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- skip_rating_with_cleanup — adds optional p_correlation_id + start/end logs.
-- -----------------------------------------------------------------------------
-- Drop the old 2-arg signature so callers without a correlation_id route to
-- the new instrumented function (its 3rd arg defaults to NULL).
DROP FUNCTION IF EXISTS public.skip_rating_with_cleanup(bigint, bigint);

CREATE OR REPLACE FUNCTION public.skip_rating_with_cleanup(
  p_round_id        bigint,
  p_participant_id  bigint,
  p_correlation_id  uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_user_id              uuid;
  v_round_phase          text;
  v_skip_count           integer;
  v_total_participants   integer;
  v_rating_minimum       integer;
  v_chat_id              bigint;
  v_allow_skip           boolean;
  v_started_at           timestamptz := clock_timestamp();
  v_corr                 uuid := COALESCE(p_correlation_id, gen_random_uuid());
BEGIN
  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'skip_rating_with_cleanup',
    p_phase          := 'start',
    p_round_id       := p_round_id
  );

  SELECT user_id INTO v_user_id
  FROM participants WHERE id = p_participant_id;

  IF v_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Participant does not belong to current user';
  END IF;

  SELECT r.phase, c.chat_id INTO v_round_phase, v_chat_id
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE r.id = p_round_id;

  IF v_round_phase IS DISTINCT FROM 'rating' THEN
    RAISE EXCEPTION 'Round is not in rating phase';
  END IF;

  SELECT allow_skip_rating INTO v_allow_skip
  FROM chats WHERE id = v_chat_id;

  IF v_allow_skip IS NOT TRUE THEN
    RAISE EXCEPTION 'Skipping rating is not allowed in this chat';
  END IF;

  IF EXISTS (
    SELECT 1 FROM rating_skips
    WHERE round_id = p_round_id AND participant_id = p_participant_id
  ) THEN
    RAISE EXCEPTION 'Already skipped this round';
  END IF;

  -- Active-only skip count for the quota check (left skippers' preserved
  -- rows must not consume quota meant for currently-active participants)
  SELECT COUNT(*) INTO v_skip_count
  FROM rating_skips rs
  JOIN participants p ON p.id = rs.participant_id
  WHERE rs.round_id = p_round_id
    AND p.status = 'active';

  SELECT COUNT(*) INTO v_total_participants FROM participants WHERE chat_id = v_chat_id AND status = 'active';
  SELECT rating_minimum INTO v_rating_minimum FROM chats WHERE id = v_chat_id;
  v_rating_minimum := COALESCE(v_rating_minimum, 2);

  IF v_skip_count >= (v_total_participants - v_rating_minimum) THEN
    RAISE EXCEPTION 'Rating skip quota exceeded';
  END IF;

  DELETE FROM grid_rankings
  WHERE participant_id = p_participant_id
    AND proposition_id IN (
      SELECT id FROM propositions WHERE round_id = p_round_id
    );

  INSERT INTO rating_skips (round_id, participant_id)
  VALUES (p_round_id, p_participant_id);

  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'skip_rating_with_cleanup',
    p_phase          := 'end',
    p_duration_ms    := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started_at)::int,
    p_chat_id        := v_chat_id,
    p_round_id       := p_round_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.skip_rating_with_cleanup(bigint, bigint, uuid)
  TO authenticated, anon;

-- -----------------------------------------------------------------------------
-- host_resume_chat — adds optional p_correlation_id + start/end logs.
-- -----------------------------------------------------------------------------
-- Drop the old 1-arg signature so callers without a correlation_id route to
-- the new instrumented function (its 2nd arg defaults to NULL).
DROP FUNCTION IF EXISTS public.host_resume_chat(bigint);

CREATE OR REPLACE FUNCTION public.host_resume_chat(
  p_chat_id         bigint,
  p_correlation_id  uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_current_round       record;
  v_is_host             boolean;
  v_schedule_paused     boolean;
  v_found               boolean;
  v_chat                record;
  v_existing_cycle_id   INTEGER;
  v_participant_count   INTEGER;
  v_new_cycle_id        BIGINT;
  v_new_round_id        BIGINT;
  v_started_at          timestamptz := clock_timestamp();
  v_corr                uuid := COALESCE(p_correlation_id, gen_random_uuid());
BEGIN
  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'host_resume_chat',
    p_phase          := 'start',
    p_chat_id        := p_chat_id
  );

  -- Verify caller is host
  SELECT EXISTS(
    SELECT 1 FROM public.participants
    WHERE chat_id = p_chat_id
      AND user_id = auth.uid()
      AND is_host = true
      AND status = 'active'
  ) INTO v_is_host;

  IF NOT v_is_host THEN
    RAISE EXCEPTION 'Only hosts can resume the chat';
  END IF;

  IF NOT (SELECT host_paused FROM public.chats WHERE id = p_chat_id) THEN
    RAISE NOTICE 'Chat % is not paused by host', p_chat_id;
    PERFORM public.log_perf(
      p_correlation_id := v_corr,
      p_source         := 'db_func',
      p_action         := 'host_resume_chat',
      p_phase          := 'end',
      p_duration_ms    := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started_at)::int,
      p_chat_id        := p_chat_id,
      p_payload        := '{"noop": true, "reason": "not_paused"}'::JSONB
    );
    RETURN;
  END IF;

  UPDATE public.chats SET host_paused = false WHERE id = p_chat_id;

  SELECT schedule_paused INTO v_schedule_paused
  FROM public.chats WHERE id = p_chat_id;

  IF NOT v_schedule_paused THEN
    -- Restore timer for an in-progress proposing/rating round (existing behavior)
    SELECT r.id, r.phase_time_remaining_seconds INTO v_current_round
    FROM public.rounds r
    JOIN public.cycles c ON r.cycle_id = c.id
    WHERE c.chat_id = p_chat_id
      AND r.phase IN ('proposing', 'rating')
      AND r.completed_at IS NULL
      AND r.phase_time_remaining_seconds IS NOT NULL
    ORDER BY r.created_at DESC
    LIMIT 1;

    v_found := FOUND;

    IF v_found AND v_current_round.phase_time_remaining_seconds > 0 THEN
      UPDATE public.rounds
      SET phase_ends_at = calculate_round_minute_end(phase_time_remaining_seconds),
          phase_time_remaining_seconds = NULL
      WHERE id = v_current_round.id;

      RAISE NOTICE '[HOST RESUME] Round % resumed with % seconds (aligned to minute)',
        v_current_round.id, v_current_round.phase_time_remaining_seconds;
    END IF;

    -- If chat hasn't started yet (no cycle), retry auto-start in case
    -- the threshold was reached while the chat was host_paused.
    SELECT id INTO v_existing_cycle_id
    FROM cycles
    WHERE chat_id = p_chat_id
    LIMIT 1;

    IF v_existing_cycle_id IS NULL THEN
      SELECT
        c.start_mode,
        c.auto_start_participant_count
      INTO v_chat
      FROM chats c
      WHERE c.id = p_chat_id;

      IF v_chat.start_mode = 'auto' THEN
        SELECT COUNT(*) INTO v_participant_count
        FROM participants
        WHERE chat_id = p_chat_id
          AND status = 'active';

        IF v_participant_count >= v_chat.auto_start_participant_count THEN
          INSERT INTO cycles (chat_id)
          VALUES (p_chat_id)
          RETURNING id INTO v_new_cycle_id;

          v_new_round_id := create_round_for_cycle(v_new_cycle_id, p_chat_id, 1);

          UPDATE chats
          SET last_activity_at = NOW()
          WHERE id = p_chat_id;

          RAISE NOTICE '[HOST RESUME] Auto-start retry on resume: cycle % round % for chat %',
            v_new_cycle_id, v_new_round_id, p_chat_id;
        END IF;
      END IF;
    END IF;
  ELSE
    RAISE NOTICE '[HOST RESUME] Chat % resumed by host but still paused by schedule', p_chat_id;
  END IF;

  RAISE NOTICE '[HOST RESUME] Chat % resumed by host', p_chat_id;

  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'host_resume_chat',
    p_phase          := 'end',
    p_duration_ms    := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started_at)::int,
    p_chat_id        := p_chat_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.host_resume_chat(bigint, uuid) TO authenticated, anon;

COMMENT ON FUNCTION public.skip_rating_with_cleanup(bigint, bigint, uuid) IS
'Skip rating + delete partial grid_rankings atomically. Optional p_correlation_id ties this DB-side timing to the Flutter-side perf_logs entry.';

COMMENT ON FUNCTION public.host_resume_chat(bigint, uuid) IS
'Resume a host-paused chat. Optional p_correlation_id ties this DB-side timing to the Flutter-side perf_logs entry.';
