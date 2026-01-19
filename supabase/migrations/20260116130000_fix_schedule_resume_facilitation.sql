-- =============================================================================
-- MIGRATION: Fix Schedule Resume to Respect Facilitation Mode
-- =============================================================================
-- FIXES:
-- 1. process_scheduled_chats() was still querying by start_mode='scheduled'
--    instead of schedule_type IS NOT NULL (from earlier migration bug)
-- 2. When schedule window opens and round is in 'waiting' phase, it was
--    force-starting 'proposing' regardless of facilitation mode (start_mode)
--
-- EXPECTED BEHAVIOR:
-- - start_mode='manual' + waiting phase: STAY in waiting, host must click "Start"
-- - start_mode='auto' + waiting phase: STAY in waiting, let process-timers handle
-- - Any phase in progress (proposing/rating): Resume with saved time (unchanged)
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
    -- Process all chats with schedule configured (regardless of start_mode)
    -- FIX: Query by schedule_type IS NOT NULL, not start_mode='scheduled'
    FOR v_chat IN
        SELECT c.id, c.is_active, c.schedule_paused, c.schedule_type,
               c.scheduled_start_at, c.proposing_duration_seconds, c.rating_duration_seconds,
               c.start_mode  -- Include start_mode for facilitation check
        FROM public.chats c
        WHERE c.schedule_type IS NOT NULL  -- Has schedule configured
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

                -- FIX: If round was in 'waiting', DO NOT auto-start proposing
                -- Respect the facilitation mode (start_mode):
                --   - manual: stay in waiting, host must click "Start"
                --   - auto: stay in waiting, let process-timers check participant threshold
                IF v_current_round.phase = 'waiting' THEN
                    -- Just unpause the chat, don't change the phase
                    -- The round stays in 'waiting' and normal facilitation rules apply
                    RAISE NOTICE '[SCHEDULE RESUME] Round % stays in waiting phase (start_mode=%), facilitation rules apply',
                        v_current_round.id, v_chat.start_mode;
                ELSE
                    -- Resume existing phase (proposing/rating) with remaining time
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
            IF v_current_round.phase = 'waiting' THEN
                details := format('Chat resumed, round in waiting phase (start_mode=%s)', v_chat.start_mode);
            ELSE
                details := format('Chat resumed with %s seconds remaining (aligned to minute)', v_remaining_seconds);
            END IF;
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
'Cron job function to pause/resume chats based on their schedules.
Queries chats by schedule_type (not start_mode) since schedule is now independent of facilitation.
FIX: When resuming a chat in waiting phase, respects facilitation mode:
  - manual: stays in waiting, host must start
  - auto: stays in waiting, process-timers checks participant threshold
Preserves remaining phase time on pause and restores it on resume for active phases.';
