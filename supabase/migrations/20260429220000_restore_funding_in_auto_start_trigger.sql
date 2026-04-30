-- Corrective migration: restore funding logic that was accidentally
-- dropped by 20260429211818_block_auto_start_during_host_pause.sql.
--
-- That migration recreated check_auto_start_on_participant_join and
-- host_resume_chat from a stale base, silently overwriting:
--   - the fund_mid_round_join() call for late joiners (added in
--     20260212000000_chat_based_credits.sql)
--   - the create_round_for_cycle() call that performs atomic credit-
--     locking + minute-aligned timer (added in 20260117100000 and
--     refined in 20260212300000_fix_credit_race_condition.sql)
--
-- Effect of the regression: every mid-round joiner since the broken
-- deploy was permanently unfunded for the round they joined; auto-
-- created first rounds skipped the FOR UPDATE credit lock and used
-- a non-minute-aligned timer that doesn't align with the cron job.
--
-- This migration re-issues both functions correctly: the host_paused
-- skip from the prior migration is preserved, and all of the funding
-- + create_round_for_cycle behavior is restored.

-- =============================================================================
-- 1. check_auto_start_on_participant_join — host_paused skip + funding
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
    v_new_cycle_id BIGINT;
    v_new_round_id BIGINT;
    v_funded BOOLEAN;
BEGIN
    -- Only proceed for active participants (not pending approval)
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    SELECT
        c.id,
        c.start_mode,
        c.host_paused,
        c.auto_start_participant_count
    INTO v_chat
    FROM chats c
    WHERE c.id = NEW.chat_id;

    -- Only proceed if chat is in auto mode
    IF v_chat.start_mode != 'auto' THEN
        RETURN NEW;
    END IF;

    -- Skip auto-start while host has paused the chat.
    -- host_resume_chat will retry this logic when the host unpauses.
    -- Important: we do NOT attempt to fund mid-round joiners while paused
    -- because there is no active round to fund them into yet.
    IF v_chat.host_paused THEN
        RAISE NOTICE '[AUTO-START] Chat % is host_paused, skipping auto-start', NEW.chat_id;
        RETURN NEW;
    END IF;

    -- Check if there's already an existing cycle (chat already started)
    SELECT id INTO v_existing_cycle_id
    FROM cycles
    WHERE chat_id = NEW.chat_id
    LIMIT 1;

    IF v_existing_cycle_id IS NOT NULL THEN
        -- Chat already started: fund this mid-round joiner if possible.
        v_funded := public.fund_mid_round_join(NEW.id, NEW.chat_id);
        RAISE NOTICE '[AUTO-START] Mid-round join for participant %, funded: %',
            NEW.id, v_funded;
        RETURN NEW;
    END IF;

    -- Count active participants
    SELECT COUNT(*) INTO v_participant_count
    FROM participants
    WHERE chat_id = NEW.chat_id
    AND status = 'active';

    RAISE NOTICE '[AUTO-START] Chat % has % active participants, threshold is %',
        NEW.chat_id, v_participant_count, v_chat.auto_start_participant_count;

    IF v_participant_count >= v_chat.auto_start_participant_count THEN
        RAISE NOTICE '[AUTO-START] Threshold reached! Creating cycle and round for chat %', NEW.chat_id;

        -- Create first cycle
        INSERT INTO cycles (chat_id)
        VALUES (NEW.chat_id)
        RETURNING id INTO v_new_cycle_id;

        -- Create first round via the shared helper. create_round_for_cycle
        -- atomically acquires FOR UPDATE on chat_credits, funds participants
        -- if balance is sufficient, and uses calculate_round_minute_end() so
        -- the timer aligns with the cron job (no "0:00 ticking forever" bug).
        v_new_round_id := create_round_for_cycle(v_new_cycle_id, NEW.chat_id, 1);

        UPDATE chats
        SET last_activity_at = NOW()
        WHERE id = NEW.chat_id;

        RAISE NOTICE '[AUTO-START] Created cycle % and round % for chat %',
            v_new_cycle_id, v_new_round_id, NEW.chat_id;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION check_auto_start_on_participant_join IS
'Auto-starts a chat when participant count reaches threshold (using create_round_for_cycle for credit-aware atomic round creation). For already-started chats, funds the new participant via fund_mid_round_join. Skips entirely while chat is host_paused — host_resume_chat will retry on unpause.';

-- =============================================================================
-- 2. host_resume_chat — minute-aligned timer restore + auto-start retry
--    using create_round_for_cycle (so retry funds participants and aligns)
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
  v_new_cycle_id BIGINT;
  v_new_round_id BIGINT;
BEGIN
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
    -- We delegate to create_round_for_cycle so the retry path goes through
    -- the same credit-aware, minute-aligned creation as the trigger path.
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
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.host_resume_chat IS
'Resumes a chat that was manually paused by the host. Uses calculate_round_minute_end() for cron-aligned timer restoration. If the chat had not started before being paused and the participant threshold has since been reached, the auto-start retry runs through create_round_for_cycle so it picks up the same credit-aware atomic round creation as the participant-join trigger path.';
