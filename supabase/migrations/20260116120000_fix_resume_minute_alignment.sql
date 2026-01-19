-- =============================================================================
-- MIGRATION: Fix Timer Resume Minute Alignment
-- =============================================================================
-- When resuming from pause, use calculate_round_minute_end() to align with cron.
-- Prevents "timer shows 0:00 but nothing happens" bug.
--
-- Problem: NOW() + saved_seconds doesn't align to whole minutes.
-- Example: Resume at 12:02:33 + 150s = 12:05:03, but cron runs at :00 seconds
--          Timer shows 0:00 for up to 57 seconds before cron processes.
--
-- Solution: Use calculate_round_minute_end() which rounds UP to next :00
-- =============================================================================

-- =============================================================================
-- STEP 1: Fix host_resume_chat to use minute alignment
-- =============================================================================

CREATE OR REPLACE FUNCTION public.host_resume_chat(p_chat_id bigint)
RETURNS void AS $$
DECLARE
  v_current_round record;
  v_is_host boolean;
  v_schedule_paused boolean;
  v_found boolean;
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

  -- Check if not paused
  IF NOT (SELECT host_paused FROM public.chats WHERE id = p_chat_id) THEN
    RAISE NOTICE 'Chat % is not paused by host', p_chat_id;
    RETURN;
  END IF;

  -- Clear host_paused flag first
  UPDATE public.chats SET host_paused = false WHERE id = p_chat_id;

  -- Check if schedule is also paused
  SELECT schedule_paused INTO v_schedule_paused
  FROM public.chats WHERE id = p_chat_id;

  -- Only restore timer if schedule is also not paused
  IF NOT v_schedule_paused THEN
    -- Get current round that might have saved time (explicit columns)
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

    -- Restore timer if there was saved time
    -- FIX: Use calculate_round_minute_end() for cron alignment
    IF v_found AND v_current_round.phase_time_remaining_seconds > 0 THEN
      UPDATE public.rounds
      SET phase_ends_at = calculate_round_minute_end(phase_time_remaining_seconds),
          phase_time_remaining_seconds = NULL
      WHERE id = v_current_round.id;

      RAISE NOTICE '[HOST RESUME] Round % resumed with % seconds (aligned to minute)',
        v_current_round.id, v_current_round.phase_time_remaining_seconds;
    END IF;
  ELSE
    RAISE NOTICE '[HOST RESUME] Chat % resumed by host but still paused by schedule', p_chat_id;
  END IF;

  RAISE NOTICE '[HOST RESUME] Chat % resumed by host', p_chat_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.host_resume_chat IS
'Resumes a chat that was manually paused by the host. Uses minute-aligned timer for cron compatibility.';

-- =============================================================================
-- STEP 2: Fix process_scheduled_chats to use minute alignment
-- =============================================================================

CREATE OR REPLACE FUNCTION public.process_scheduled_chats()
RETURNS TABLE(
    chat_id INT,
    action TEXT,
    details TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_in_window BOOLEAN;
    v_current_round RECORD;
    v_remaining_seconds INTEGER;
    v_phase_duration INTEGER;
BEGIN
    -- Process all scheduled chats
    FOR v_chat IN
        SELECT c.id, c.is_active, c.schedule_paused, c.schedule_type,
               c.scheduled_start_at, c.proposing_duration_seconds, c.rating_duration_seconds
        FROM public.chats c
        WHERE c.start_mode = 'scheduled'
          AND c.is_active = TRUE
    LOOP
        v_in_window := is_chat_in_schedule_window(v_chat.id::INT);

        -- Case 1: Chat should be active but is paused -> RESUME
        IF v_in_window AND v_chat.schedule_paused THEN
            -- Unpause the chat
            UPDATE public.chats
            SET schedule_paused = FALSE
            WHERE id = v_chat.id;

            -- Get current round (most recent incomplete)
            SELECT r.* INTO v_current_round
            FROM public.rounds r
            JOIN public.cycles cy ON r.cycle_id = cy.id
            WHERE cy.chat_id = v_chat.id
              AND r.completed_at IS NULL
            ORDER BY r.created_at DESC
            LIMIT 1;

            IF v_current_round.id IS NOT NULL THEN
                -- Determine phase duration for this phase
                IF v_current_round.phase = 'proposing' OR v_current_round.phase = 'waiting' THEN
                    v_phase_duration := COALESCE(v_chat.proposing_duration_seconds, 86400);
                ELSE
                    v_phase_duration := COALESCE(v_chat.rating_duration_seconds, 86400);
                END IF;

                -- Calculate how much time to restore
                IF v_current_round.phase_time_remaining_seconds IS NOT NULL
                   AND v_current_round.phase_time_remaining_seconds > 0 THEN
                    -- Restore the saved remaining time
                    v_remaining_seconds := v_current_round.phase_time_remaining_seconds;
                ELSE
                    -- No saved time - use full phase duration
                    v_remaining_seconds := v_phase_duration;
                END IF;

                -- If round was in 'waiting', transition to 'proposing'
                -- FIX: Use calculate_round_minute_end() for cron alignment
                IF v_current_round.phase = 'waiting' THEN
                    UPDATE public.rounds
                    SET phase = 'proposing',
                        phase_started_at = NOW(),
                        phase_ends_at = calculate_round_minute_end(v_remaining_seconds),
                        phase_time_remaining_seconds = NULL
                    WHERE id = v_current_round.id;

                    RAISE NOTICE '[SCHEDULE RESUME] Round % started proposing with % seconds (aligned to minute)',
                        v_current_round.id, v_remaining_seconds;
                ELSE
                    -- Resume existing phase with remaining time
                    -- FIX: Use calculate_round_minute_end() for cron alignment
                    UPDATE public.rounds
                    SET phase_started_at = NOW(),
                        phase_ends_at = calculate_round_minute_end(v_remaining_seconds),
                        phase_time_remaining_seconds = NULL
                    WHERE id = v_current_round.id;

                    RAISE NOTICE '[SCHEDULE RESUME] Round % resumed % phase with % seconds remaining (aligned to minute)',
                        v_current_round.id, v_current_round.phase, v_remaining_seconds;
                END IF;
            END IF;

            chat_id := v_chat.id;
            action := 'resumed';
            details := format('Chat resumed with %s seconds remaining (aligned to minute)', v_remaining_seconds);
            RETURN NEXT;

        -- Case 2: Chat should be paused but is active -> PAUSE
        ELSIF NOT v_in_window AND NOT v_chat.schedule_paused THEN
            -- For one-time schedules that haven't started yet, don't pause
            IF v_chat.schedule_type = 'once' AND v_chat.scheduled_start_at > NOW() THEN
                CONTINUE;
            END IF;

            -- Get current round to save remaining time
            SELECT r.* INTO v_current_round
            FROM public.rounds r
            JOIN public.cycles cy ON r.cycle_id = cy.id
            WHERE cy.chat_id = v_chat.id
              AND r.completed_at IS NULL
            ORDER BY r.created_at DESC
            LIMIT 1;

            -- Calculate and save remaining time
            IF v_current_round.id IS NOT NULL
               AND v_current_round.phase IN ('proposing', 'rating')
               AND v_current_round.phase_ends_at IS NOT NULL THEN
                -- Calculate remaining seconds (minimum 0)
                v_remaining_seconds := GREATEST(0,
                    EXTRACT(EPOCH FROM (v_current_round.phase_ends_at - NOW()))::INTEGER
                );

                -- Save remaining time to round
                UPDATE public.rounds
                SET phase_time_remaining_seconds = v_remaining_seconds
                WHERE id = v_current_round.id;

                RAISE NOTICE '[SCHEDULE PAUSE] Round % paused in % phase with % seconds remaining',
                    v_current_round.id, v_current_round.phase, v_remaining_seconds;
            ELSE
                v_remaining_seconds := NULL;
            END IF;

            -- Pause the chat
            UPDATE public.chats
            SET schedule_paused = TRUE
            WHERE id = v_chat.id;

            chat_id := v_chat.id;
            action := 'paused';
            details := format('Chat paused with %s seconds remaining', COALESCE(v_remaining_seconds::TEXT, 'N/A'));
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.process_scheduled_chats IS
'Cron job function to pause/resume chats based on their schedules. Uses minute-aligned timers for cron compatibility.';
