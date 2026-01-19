-- =============================================================================
-- MIGRATION: Schedule Pause/Resume with Time Preservation
-- =============================================================================
-- When schedule window closes mid-phase, we store remaining time.
-- When window reopens, we resume with exactly that remaining time.
-- =============================================================================

-- =============================================================================
-- STEP 1: Add column to store remaining time when paused
-- =============================================================================

ALTER TABLE public.rounds
ADD COLUMN IF NOT EXISTS phase_time_remaining_seconds INTEGER;

COMMENT ON COLUMN public.rounds.phase_time_remaining_seconds IS
'Stores remaining phase time in seconds when chat is paused due to schedule. Used to restore timer on resume.';

-- =============================================================================
-- STEP 2: Update process_scheduled_chats to preserve and restore time
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
                IF v_current_round.phase = 'waiting' THEN
                    UPDATE public.rounds
                    SET phase = 'proposing',
                        phase_started_at = NOW(),
                        phase_ends_at = NOW() + (v_remaining_seconds || ' seconds')::INTERVAL,
                        phase_time_remaining_seconds = NULL
                    WHERE id = v_current_round.id;

                    RAISE NOTICE '[SCHEDULE RESUME] Round % started proposing with % seconds',
                        v_current_round.id, v_remaining_seconds;
                ELSE
                    -- Resume existing phase with remaining time
                    UPDATE public.rounds
                    SET phase_started_at = NOW(),
                        phase_ends_at = NOW() + (v_remaining_seconds || ' seconds')::INTERVAL,
                        phase_time_remaining_seconds = NULL
                    WHERE id = v_current_round.id;

                    RAISE NOTICE '[SCHEDULE RESUME] Round % resumed % phase with % seconds remaining',
                        v_current_round.id, v_current_round.phase, v_remaining_seconds;
                END IF;
            END IF;

            chat_id := v_chat.id;
            action := 'resumed';
            details := format('Chat resumed with %s seconds remaining', v_remaining_seconds);
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
'Cron job function to pause/resume chats based on their schedules. Preserves remaining phase time on pause and restores it on resume.';

-- =============================================================================
-- STEP 3: Index for efficient querying of paused rounds
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_rounds_phase_time_remaining
ON public.rounds(phase_time_remaining_seconds)
WHERE phase_time_remaining_seconds IS NOT NULL;
