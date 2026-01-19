-- Migration: Add scheduled chat functionality
-- Allows chats to start/pause on a schedule (one-time or recurring)

-- ============================================================================
-- STEP 1: Add new columns for scheduling
-- ============================================================================

-- Schedule type: 'once' for one-time, 'recurring' for weekly schedule
ALTER TABLE public.chats
ADD COLUMN schedule_type TEXT;

-- Timezone for schedule interpretation (IANA timezone name)
ALTER TABLE public.chats
ADD COLUMN schedule_timezone TEXT DEFAULT 'UTC';

-- For one-time scheduled start
ALTER TABLE public.chats
ADD COLUMN scheduled_start_at TIMESTAMPTZ;

-- For recurring schedule
ALTER TABLE public.chats
ADD COLUMN schedule_days TEXT[] DEFAULT '{}';

ALTER TABLE public.chats
ADD COLUMN schedule_start_time TIME;

ALTER TABLE public.chats
ADD COLUMN schedule_end_time TIME;

-- Whether chat is visible outside scheduled window
ALTER TABLE public.chats
ADD COLUMN visible_outside_schedule BOOLEAN DEFAULT TRUE;

-- Track if chat is currently paused due to schedule
ALTER TABLE public.chats
ADD COLUMN schedule_paused BOOLEAN DEFAULT FALSE;

-- ============================================================================
-- STEP 2: Update start_mode check constraint
-- ============================================================================

-- Drop existing constraint
ALTER TABLE public.chats
DROP CONSTRAINT IF EXISTS chats_start_mode_check;

-- Add new constraint including 'scheduled'
ALTER TABLE public.chats
ADD CONSTRAINT chats_start_mode_check
CHECK (start_mode = ANY (ARRAY['manual'::text, 'auto'::text, 'scheduled'::text]));

-- ============================================================================
-- STEP 3: Add validation constraints
-- ============================================================================

-- Schedule type must be valid
ALTER TABLE public.chats
ADD CONSTRAINT chats_schedule_type_check
CHECK (schedule_type IS NULL OR schedule_type = ANY (ARRAY['once'::text, 'recurring'::text]));

-- If start_mode = 'scheduled', schedule_type must be set
ALTER TABLE public.chats
ADD CONSTRAINT chats_scheduled_requires_type
CHECK (start_mode != 'scheduled' OR schedule_type IS NOT NULL);

-- If schedule_type = 'once', scheduled_start_at must be set
ALTER TABLE public.chats
ADD CONSTRAINT chats_once_requires_start_at
CHECK (schedule_type != 'once' OR scheduled_start_at IS NOT NULL);

-- If schedule_type = 'recurring', all recurring fields must be set
ALTER TABLE public.chats
ADD CONSTRAINT chats_recurring_requires_fields
CHECK (
    schedule_type != 'recurring' OR (
        array_length(schedule_days, 1) > 0 AND
        schedule_start_time IS NOT NULL AND
        schedule_end_time IS NOT NULL
    )
);

-- Schedule days must be valid day names
CREATE OR REPLACE FUNCTION public.validate_schedule_days(days TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    valid_days TEXT[] := ARRAY['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
    day TEXT;
BEGIN
    IF days IS NULL OR array_length(days, 1) IS NULL THEN
        RETURN TRUE;
    END IF;

    FOREACH day IN ARRAY days LOOP
        IF NOT (lower(day) = ANY(valid_days)) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$;

ALTER TABLE public.chats
ADD CONSTRAINT chats_schedule_days_valid
CHECK (validate_schedule_days(schedule_days));

-- Schedule end time must be after start time (for same-day schedules)
ALTER TABLE public.chats
ADD CONSTRAINT chats_schedule_time_order
CHECK (
    schedule_type != 'recurring' OR
    schedule_end_time > schedule_start_time
);

-- ============================================================================
-- STEP 4: Helper function to check if chat is in scheduled window
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_chat_in_schedule_window(chat_id INT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_now TIMESTAMPTZ;
    v_now_in_tz TIMESTAMP;
    v_current_time TIME;
    v_current_day TEXT;
    v_day_matches BOOLEAN;
BEGIN
    -- Get chat details
    SELECT
        start_mode,
        schedule_type,
        schedule_timezone,
        scheduled_start_at,
        schedule_days,
        schedule_start_time,
        schedule_end_time
    INTO v_chat
    FROM public.chats
    WHERE id = chat_id;

    -- If not scheduled mode, always in window
    IF v_chat.start_mode != 'scheduled' THEN
        RETURN TRUE;
    END IF;

    v_now := NOW();

    -- Handle one-time schedule
    IF v_chat.schedule_type = 'once' THEN
        -- For one-time, we're "in window" after the scheduled time
        -- (the actual start is handled by the cron job)
        RETURN v_now >= v_chat.scheduled_start_at;
    END IF;

    -- Handle recurring schedule
    IF v_chat.schedule_type = 'recurring' THEN
        -- Convert current time to the chat's timezone
        v_now_in_tz := v_now AT TIME ZONE COALESCE(v_chat.schedule_timezone, 'UTC');
        v_current_time := v_now_in_tz::TIME;
        v_current_day := lower(to_char(v_now_in_tz, 'Day'));
        v_current_day := trim(v_current_day); -- Remove trailing spaces

        -- Check if current day is in schedule_days
        v_day_matches := FALSE;
        FOR i IN 1..array_length(v_chat.schedule_days, 1) LOOP
            IF lower(v_chat.schedule_days[i]) = v_current_day THEN
                v_day_matches := TRUE;
                EXIT;
            END IF;
        END LOOP;

        IF NOT v_day_matches THEN
            RETURN FALSE;
        END IF;

        -- Check if current time is within schedule window
        RETURN v_current_time >= v_chat.schedule_start_time
           AND v_current_time < v_chat.schedule_end_time;
    END IF;

    RETURN FALSE;
END;
$$;

-- ============================================================================
-- STEP 5: Function to process scheduled chats (called by cron)
-- ============================================================================

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
BEGIN
    -- Process all scheduled chats
    FOR v_chat IN
        SELECT c.id, c.is_active, c.schedule_paused, c.schedule_type, c.scheduled_start_at
        FROM public.chats c
        WHERE c.start_mode = 'scheduled'
          AND c.is_active = TRUE
    LOOP
        v_in_window := is_chat_in_schedule_window(v_chat.id::INT);

        -- Case 1: Chat should be active but is paused -> Resume
        IF v_in_window AND v_chat.schedule_paused THEN
            -- Unpause the chat
            UPDATE public.chats
            SET schedule_paused = FALSE
            WHERE id = v_chat.id;

            -- Get current round
            SELECT r.* INTO v_current_round
            FROM public.rounds r
            JOIN public.cycles cy ON r.cycle_id = cy.id
            WHERE cy.chat_id = v_chat.id
              AND r.completed_at IS NULL
            ORDER BY r.created_at DESC
            LIMIT 1;

            -- If round exists and is in waiting phase, start it
            IF v_current_round.id IS NOT NULL AND v_current_round.phase = 'waiting' THEN
                UPDATE public.rounds
                SET phase = 'proposing',
                    phase_started_at = NOW()
                WHERE id = v_current_round.id;
            END IF;

            chat_id := v_chat.id;
            action := 'resumed';
            details := 'Chat resumed - entered schedule window';
            RETURN NEXT;

        -- Case 2: Chat should be paused but is active -> Pause
        ELSIF NOT v_in_window AND NOT v_chat.schedule_paused THEN
            -- For one-time schedules that haven't started yet, don't pause
            IF v_chat.schedule_type = 'once' AND v_chat.scheduled_start_at > NOW() THEN
                CONTINUE;
            END IF;

            -- Pause the chat
            UPDATE public.chats
            SET schedule_paused = TRUE
            WHERE id = v_chat.id;

            chat_id := v_chat.id;
            action := 'paused';
            details := 'Chat paused - outside schedule window';
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$;

-- ============================================================================
-- STEP 6: Create cron job for processing scheduled chats
-- ============================================================================

-- Run every minute to check scheduled chats
SELECT cron.schedule(
    'process-scheduled-chats',
    '* * * * *',  -- Every minute
    $$SELECT public.process_scheduled_chats()$$
);

-- ============================================================================
-- STEP 7: Update RLS policies to respect visibility setting
-- ============================================================================

-- Helper function to check if chat is visible to user
CREATE OR REPLACE FUNCTION public.is_chat_visible(chat_record public.chats)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    -- Always visible if not scheduled
    IF chat_record.start_mode != 'scheduled' THEN
        RETURN TRUE;
    END IF;

    -- Always visible if visible_outside_schedule is true
    IF chat_record.visible_outside_schedule THEN
        RETURN TRUE;
    END IF;

    -- Check if in schedule window
    RETURN is_chat_in_schedule_window(chat_record.id);
END;
$$;

-- Note: RLS policy updates would go here, but we need to be careful
-- not to break existing policies. For now, visibility will be handled
-- at the application layer by checking schedule_paused and visible_outside_schedule.

-- ============================================================================
-- STEP 8: Add indexes for efficient querying
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_chats_start_mode
ON public.chats(start_mode)
WHERE start_mode = 'scheduled';

CREATE INDEX IF NOT EXISTS idx_chats_schedule_paused
ON public.chats(schedule_paused)
WHERE schedule_paused = TRUE;

-- ============================================================================
-- STEP 9: Comments for documentation
-- ============================================================================

COMMENT ON COLUMN public.chats.schedule_type IS 'Type of schedule: once (one-time) or recurring (weekly)';
COMMENT ON COLUMN public.chats.schedule_timezone IS 'IANA timezone name for schedule interpretation (e.g., America/New_York)';
COMMENT ON COLUMN public.chats.scheduled_start_at IS 'For one-time schedules: when the chat should start';
COMMENT ON COLUMN public.chats.schedule_days IS 'For recurring schedules: array of day names (e.g., {monday,wednesday,friday})';
COMMENT ON COLUMN public.chats.schedule_start_time IS 'For recurring schedules: time of day to start (in schedule_timezone)';
COMMENT ON COLUMN public.chats.schedule_end_time IS 'For recurring schedules: time of day to pause (in schedule_timezone)';
COMMENT ON COLUMN public.chats.visible_outside_schedule IS 'If false, chat is hidden when outside schedule window';
COMMENT ON COLUMN public.chats.schedule_paused IS 'True when chat is currently paused due to being outside schedule window';

COMMENT ON FUNCTION public.is_chat_in_schedule_window IS 'Returns true if the chat is currently within its scheduled active window';
COMMENT ON FUNCTION public.process_scheduled_chats IS 'Cron job function to pause/resume chats based on their schedules';
