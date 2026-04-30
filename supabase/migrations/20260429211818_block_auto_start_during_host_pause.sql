-- Block auto-start trigger from firing while host_paused = TRUE.
-- Also: when host resumes a chat that hasn't started yet, retry the auto-start
-- logic in case the participant threshold was reached during the pause window.
--
-- Bug: a host who pauses an auto-mode chat to wait for more joiners gets the
-- chat started anyway the moment threshold is hit. The pause flag is set but
-- the timer runs invisibly underneath it. This breaks the legitimate use case
-- of "create chat → pause → drop link → wait for joiners → resume".

-- =============================================================================
-- 1. Auto-start trigger respects host_paused
-- =============================================================================

CREATE OR REPLACE FUNCTION check_auto_start_on_participant_join()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_existing_cycle_id INTEGER;
    v_new_cycle_id INTEGER;
    v_new_round_id INTEGER;
    v_phase_ends_at TIMESTAMPTZ;
BEGIN
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    SELECT
        c.id,
        c.start_mode,
        c.host_paused,
        c.auto_start_participant_count,
        c.proposing_duration_seconds
    INTO v_chat
    FROM chats c
    WHERE c.id = NEW.chat_id;

    IF v_chat.start_mode != 'auto' THEN
        RETURN NEW;
    END IF;

    -- Skip auto-start while host has paused the chat.
    -- host_resume_chat will retry this logic when the host unpauses.
    IF v_chat.host_paused THEN
        RAISE NOTICE '[AUTO-START] Chat % is host_paused, skipping auto-start', NEW.chat_id;
        RETURN NEW;
    END IF;

    SELECT id INTO v_existing_cycle_id
    FROM cycles
    WHERE chat_id = NEW.chat_id
    LIMIT 1;

    IF v_existing_cycle_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(*) INTO v_participant_count
    FROM participants
    WHERE chat_id = NEW.chat_id
    AND status = 'active';

    RAISE NOTICE '[AUTO-START] Chat % has % active participants, threshold is %',
        NEW.chat_id, v_participant_count, v_chat.auto_start_participant_count;

    IF v_participant_count >= v_chat.auto_start_participant_count THEN
        RAISE NOTICE '[AUTO-START] Threshold reached! Creating cycle and round for chat %', NEW.chat_id;

        v_phase_ends_at := NOW() + (v_chat.proposing_duration_seconds * INTERVAL '1 second');

        INSERT INTO cycles (chat_id)
        VALUES (NEW.chat_id)
        RETURNING id INTO v_new_cycle_id;

        INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
        VALUES (v_new_cycle_id, 1, 'proposing', NOW(), v_phase_ends_at)
        RETURNING id INTO v_new_round_id;

        UPDATE chats
        SET last_activity_at = NOW()
        WHERE id = NEW.chat_id;

        RAISE NOTICE '[AUTO-START] Created cycle % and round % for chat %',
            v_new_cycle_id, v_new_round_id, NEW.chat_id;
    END IF;

    RETURN NEW;
END;
$$;

-- =============================================================================
-- 2. host_resume_chat retries auto-start when chat hasn't started yet
-- =============================================================================

CREATE OR REPLACE FUNCTION public.host_resume_chat(p_chat_id bigint)
RETURNS void AS $$
DECLARE
  v_current_round record;
  v_is_host boolean;
  v_schedule_paused boolean;
  v_found boolean;
  v_chat record;
  v_existing_cycle_id INTEGER;
  v_participant_count INTEGER;
  v_new_cycle_id INTEGER;
  v_new_round_id INTEGER;
  v_phase_ends_at TIMESTAMPTZ;
BEGIN
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
    RETURN;
  END IF;

  UPDATE public.chats SET host_paused = false WHERE id = p_chat_id;

  SELECT schedule_paused INTO v_schedule_paused
  FROM public.chats WHERE id = p_chat_id;

  IF NOT v_schedule_paused THEN
    -- Existing logic: restore timer for an in-progress proposing/rating round
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

    -- New: if chat hasn't started yet (no cycle), retry auto-start in case
    -- the threshold was reached while the chat was host_paused.
    SELECT id INTO v_existing_cycle_id
    FROM cycles
    WHERE chat_id = p_chat_id
    LIMIT 1;

    IF v_existing_cycle_id IS NULL THEN
      SELECT
        c.start_mode,
        c.auto_start_participant_count,
        c.proposing_duration_seconds
      INTO v_chat
      FROM chats c
      WHERE c.id = p_chat_id;

      IF v_chat.start_mode = 'auto' THEN
        SELECT COUNT(*) INTO v_participant_count
        FROM participants
        WHERE chat_id = p_chat_id
          AND status = 'active';

        IF v_participant_count >= v_chat.auto_start_participant_count THEN
          v_phase_ends_at := NOW() + (v_chat.proposing_duration_seconds * INTERVAL '1 second');

          INSERT INTO cycles (chat_id)
          VALUES (p_chat_id)
          RETURNING id INTO v_new_cycle_id;

          INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
          VALUES (v_new_cycle_id, 1, 'proposing', NOW(), v_phase_ends_at)
          RETURNING id INTO v_new_round_id;

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
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.host_resume_chat IS
'Resumes a chat that was manually paused by the host. Uses minute-aligned timer for cron compatibility. If chat was paused before auto-start fired and threshold has since been reached, the auto-start logic runs on resume.';
