-- =============================================================================
-- MIGRATION: Separate Facilitation Mode from Schedule
-- =============================================================================
-- This migration separates two orthogonal concepts:
-- 1. Facilitation Mode (start_mode): How proposing starts (manual/auto)
-- 2. Schedule: When the chat room is open (none/once/recurring)
--
-- Previously, 'scheduled' was a start_mode value, but it conflates these concepts.
-- Now, schedule is independent - you can have manual+schedule or auto+schedule.
-- =============================================================================

-- =============================================================================
-- STEP 1: Migrate existing 'scheduled' chats to 'manual'
-- =============================================================================
-- Existing scheduled chats become manual facilitation with schedule enabled.
-- The schedule fields (schedule_type, schedule_windows, etc.) remain unchanged.

UPDATE public.chats
SET start_mode = 'manual'
WHERE start_mode = 'scheduled';

-- =============================================================================
-- STEP 2: Update CHECK constraint to only allow 'manual' and 'auto'
-- =============================================================================

ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_start_mode_check;

ALTER TABLE public.chats
ADD CONSTRAINT chats_start_mode_check
CHECK (start_mode = ANY (ARRAY['manual'::text, 'auto'::text]));

-- =============================================================================
-- STEP 3: Remove constraint that required schedule_type when start_mode='scheduled'
-- =============================================================================

ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_scheduled_requires_type;

-- =============================================================================
-- STEP 4: Update is_chat_in_schedule_window() to check schedule_type, not start_mode
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_chat_in_schedule_window(p_chat_id integer)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_chat RECORD;
    v_now TIMESTAMPTZ;
    v_now_in_tz TIMESTAMP;
    v_current_time TIME;
    v_current_day INTEGER;
    v_window JSONB;
    v_i INTEGER;
    v_window_count INTEGER;
BEGIN
    -- Get chat details
    SELECT
        schedule_type,
        schedule_timezone,
        scheduled_start_at,
        schedule_windows
    INTO v_chat
    FROM public.chats
    WHERE id = p_chat_id;

    -- If no schedule configured, always in window (chat is always open)
    IF v_chat.schedule_type IS NULL THEN
        RETURN TRUE;
    END IF;

    v_now := NOW();

    -- Handle one-time schedule
    IF v_chat.schedule_type = 'once' THEN
        RETURN v_now >= v_chat.scheduled_start_at;
    END IF;

    -- Handle recurring schedule with flexible windows
    IF v_chat.schedule_type = 'recurring' THEN
        -- If no windows configured, not in window
        IF v_chat.schedule_windows IS NULL OR jsonb_array_length(v_chat.schedule_windows) = 0 THEN
            RETURN FALSE;
        END IF;

        -- Convert current time to the chat's timezone
        v_now_in_tz := v_now AT TIME ZONE COALESCE(v_chat.schedule_timezone, 'UTC');
        v_current_time := v_now_in_tz::TIME;
        v_current_day := EXTRACT(DOW FROM v_now_in_tz)::INTEGER;  -- 0=Sunday

        v_window_count := jsonb_array_length(v_chat.schedule_windows);

        -- Check each window
        FOR v_i IN 0..(v_window_count - 1) LOOP
            v_window := v_chat.schedule_windows->v_i;
            IF is_in_single_window(v_current_day, v_current_time, v_window) THEN
                RETURN TRUE;
            END IF;
        END LOOP;

        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$function$;

COMMENT ON FUNCTION public.is_chat_in_schedule_window(integer) IS
'Checks if a chat is currently within its schedule window.
Returns TRUE if: no schedule configured, or current time is within a schedule window.
Returns FALSE if: schedule configured but current time is outside all windows.
Note: This is independent of start_mode (facilitation).';

-- =============================================================================
-- STEP 5: Update process_scheduled_chats() to query by schedule_type, not start_mode
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
    FOR v_chat IN
        SELECT c.id, c.is_active, c.schedule_paused, c.schedule_type,
               c.scheduled_start_at, c.proposing_duration_seconds, c.rating_duration_seconds
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
'Cron job function to pause/resume chats based on their schedules.
Queries chats by schedule_type (not start_mode) since schedule is now independent.
Preserves remaining phase time on pause and restores it on resume.';

-- =============================================================================
-- STEP 6: Update set_schedule_paused_on_insert() trigger to check schedule_type
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_schedule_paused_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_in_window BOOLEAN := FALSE;
    v_now_in_tz TIMESTAMP;
    v_current_time TIME;
    v_current_day INTEGER;
    v_window JSONB;
    v_i INTEGER;
    v_window_count INTEGER;
BEGIN
    -- Only process recurring chats with windows defined (check schedule_type, not start_mode)
    IF NEW.schedule_type = 'recurring' AND
       NEW.schedule_windows IS NOT NULL AND
       jsonb_array_length(NEW.schedule_windows) > 0 THEN

        -- Convert current time to the chat's timezone
        v_now_in_tz := NOW() AT TIME ZONE COALESCE(NEW.schedule_timezone, 'UTC');
        v_current_time := v_now_in_tz::TIME;
        v_current_day := EXTRACT(DOW FROM v_now_in_tz)::INTEGER;  -- 0=Sunday

        v_window_count := jsonb_array_length(NEW.schedule_windows);

        -- Check each window to see if we're currently inside one
        FOR v_i IN 0..(v_window_count - 1) LOOP
            v_window := NEW.schedule_windows->v_i;
            IF is_in_single_window(v_current_day, v_current_time, v_window) THEN
                v_in_window := TRUE;
                EXIT;  -- Found a matching window, no need to check more
            END IF;
        END LOOP;

        -- If not in any window, start paused
        IF NOT v_in_window THEN
            NEW.schedule_paused := TRUE;
            RAISE NOTICE '[SCHEDULE INSERT] Chat created outside schedule window, setting schedule_paused=TRUE';
        ELSE
            NEW.schedule_paused := FALSE;
            RAISE NOTICE '[SCHEDULE INSERT] Chat created inside schedule window, setting schedule_paused=FALSE';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_schedule_paused_on_insert IS
'Trigger function to set schedule_paused on INSERT for recurring scheduled chats.
Checks schedule_type (not start_mode) since schedule is now independent of facilitation mode.';

-- =============================================================================
-- STEP 7: Add index for efficient querying of chats with schedules
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_chats_with_schedule
ON public.chats(schedule_type)
WHERE schedule_type IS NOT NULL;

COMMENT ON INDEX idx_chats_with_schedule IS
'Index for efficient querying of chats that have schedules configured.';
