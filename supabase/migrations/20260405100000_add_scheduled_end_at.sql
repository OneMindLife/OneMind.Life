-- Migration: Add optional end time for one-time scheduled chats
-- One-time schedules can now have an optional end time.
-- If set, the chat will be paused after the end time.
-- If not set, the chat stays active indefinitely after start.

-- Add the column
ALTER TABLE public.chats
ADD COLUMN scheduled_end_at TIMESTAMPTZ;

-- If scheduled_end_at is set, it must be after scheduled_start_at
ALTER TABLE public.chats
ADD CONSTRAINT chats_once_end_after_start
CHECK (scheduled_end_at IS NULL OR scheduled_start_at IS NULL OR scheduled_end_at > scheduled_start_at);

-- Update is_chat_in_schedule_window to respect end time for one-time schedules.
-- Based on the version from 20260115080000_separate_facilitation_from_schedule.sql
-- which uses schedule_windows (JSONB) for recurring and schedule_type for routing.
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
        scheduled_end_at,
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
        -- Not yet started
        IF v_now < v_chat.scheduled_start_at THEN
            RETURN FALSE;
        END IF;
        -- If end time is set and we're past it, not in window
        IF v_chat.scheduled_end_at IS NOT NULL AND v_now >= v_chat.scheduled_end_at THEN
            RETURN FALSE;
        END IF;
        RETURN TRUE;
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

COMMENT ON COLUMN public.chats.scheduled_end_at IS 'For one-time schedules: optional end time. If NULL, chat stays active indefinitely after start.';
