-- =============================================================================
-- MIGRATION: Flexible Schedule Windows for Recurring Schedules
-- =============================================================================
-- Replaces single time window with array of independent windows.
-- Each window has explicit start_day/time and end_day/time to support:
-- - Multiple windows per chat
-- - Different windows for different days
-- - Midnight-spanning windows (Thu 11pm → Fri 1am)
-- - Multi-day windows (Sat 10am → Mon 8am)
-- =============================================================================

-- =============================================================================
-- STEP 1: Add new schedule_windows column
-- =============================================================================

ALTER TABLE public.chats
ADD COLUMN schedule_windows JSONB;

COMMENT ON COLUMN public.chats.schedule_windows IS
'Array of schedule windows for recurring schedules. Each window: {"start_day": "monday", "start_time": "09:00", "end_day": "monday", "end_time": "17:00"}';

-- =============================================================================
-- STEP 2: Helper function to convert day name to number
-- =============================================================================

CREATE OR REPLACE FUNCTION public.day_name_to_number(day_name TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN CASE lower(trim(day_name))
        WHEN 'sunday' THEN 0
        WHEN 'monday' THEN 1
        WHEN 'tuesday' THEN 2
        WHEN 'wednesday' THEN 3
        WHEN 'thursday' THEN 4
        WHEN 'friday' THEN 5
        WHEN 'saturday' THEN 6
        ELSE NULL
    END;
END;
$$;

-- =============================================================================
-- STEP 3: Function to validate a single schedule window
-- =============================================================================

CREATE OR REPLACE FUNCTION public.validate_schedule_window(p_window JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_start_day INTEGER;
    v_end_day INTEGER;
    v_start_time TIME;
    v_end_time TIME;
BEGIN
    -- Check required fields exist
    IF p_window->>'start_day' IS NULL OR
       p_window->>'start_time' IS NULL OR
       p_window->>'end_day' IS NULL OR
       p_window->>'end_time' IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Validate day names
    v_start_day := day_name_to_number(p_window->>'start_day');
    v_end_day := day_name_to_number(p_window->>'end_day');

    IF v_start_day IS NULL OR v_end_day IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Validate time formats
    BEGIN
        v_start_time := (p_window->>'start_time')::TIME;
        v_end_time := (p_window->>'end_time')::TIME;
    EXCEPTION WHEN OTHERS THEN
        RETURN FALSE;
    END;

    -- If same day, end must be after start
    IF v_start_day = v_end_day AND v_end_time <= v_start_time THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

-- =============================================================================
-- STEP 4: Function to convert window to week minutes (for overlap detection)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.window_to_week_minutes(p_window JSONB)
RETURNS TABLE(start_min INTEGER, end_min INTEGER)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_start_day INTEGER;
    v_end_day INTEGER;
    v_start_time TIME;
    v_end_time TIME;
    v_start_minutes INTEGER;
    v_end_minutes INTEGER;
BEGIN
    v_start_day := day_name_to_number(p_window->>'start_day');
    v_end_day := day_name_to_number(p_window->>'end_day');
    v_start_time := (p_window->>'start_time')::TIME;
    v_end_time := (p_window->>'end_time')::TIME;

    -- Convert to minutes from start of week (Sunday 00:00)
    v_start_minutes := v_start_day * 1440 + EXTRACT(HOUR FROM v_start_time) * 60 + EXTRACT(MINUTE FROM v_start_time);
    v_end_minutes := v_end_day * 1440 + EXTRACT(HOUR FROM v_end_time) * 60 + EXTRACT(MINUTE FROM v_end_time);

    -- Handle week wraparound (e.g., Sat 11pm → Mon 1am)
    IF v_end_minutes <= v_start_minutes THEN
        v_end_minutes := v_end_minutes + 7 * 1440;  -- Add a week
    END IF;

    start_min := v_start_minutes;
    end_min := v_end_minutes;
    RETURN NEXT;
END;
$$;

-- =============================================================================
-- STEP 5: Function to check if two windows overlap
-- =============================================================================

CREATE OR REPLACE FUNCTION public.windows_overlap(window_a JSONB, window_b JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_a RECORD;
    v_b RECORD;
    v_a_ranges INTEGER[][];
    v_b_ranges INTEGER[][];
    v_week_minutes INTEGER := 7 * 1440;
BEGIN
    -- Get minute ranges for both windows
    SELECT * INTO v_a FROM window_to_week_minutes(window_a);
    SELECT * INTO v_b FROM window_to_week_minutes(window_b);

    -- Handle wraparound by checking both the original range and week-shifted versions
    -- Check if ranges overlap: a.start < b.end AND b.start < a.end
    IF v_a.start_min < v_b.end_min AND v_b.start_min < v_a.end_min THEN
        RETURN TRUE;
    END IF;

    -- Also check shifted versions for week wraparound edge cases
    IF v_a.start_min < (v_b.end_min + v_week_minutes) AND (v_b.start_min + v_week_minutes) < v_a.end_min THEN
        RETURN TRUE;
    END IF;

    IF (v_a.start_min + v_week_minutes) < v_b.end_min AND v_b.start_min < (v_a.end_min + v_week_minutes) THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;

-- =============================================================================
-- STEP 6: Function to validate entire schedule_windows array
-- =============================================================================

CREATE OR REPLACE FUNCTION public.validate_schedule_windows(windows JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_window JSONB;
    v_other JSONB;
    v_count INTEGER;
    v_i INTEGER;
    v_j INTEGER;
BEGIN
    -- NULL is valid (no windows = no recurring schedule)
    IF windows IS NULL THEN
        RETURN TRUE;
    END IF;

    -- Must be an array
    IF jsonb_typeof(windows) != 'array' THEN
        RETURN FALSE;
    END IF;

    v_count := jsonb_array_length(windows);

    -- Empty array is invalid for recurring schedules (handled by constraint)
    -- But the validation function itself accepts empty as valid structure
    IF v_count = 0 THEN
        RETURN TRUE;
    END IF;

    -- Validate each window individually
    FOR v_i IN 0..(v_count - 1) LOOP
        v_window := windows->v_i;
        IF NOT validate_schedule_window(v_window) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    -- Check for overlaps between all pairs
    FOR v_i IN 0..(v_count - 2) LOOP
        FOR v_j IN (v_i + 1)..(v_count - 1) LOOP
            IF windows_overlap(windows->v_i, windows->v_j) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
    END LOOP;

    RETURN TRUE;
END;
$$;

-- =============================================================================
-- STEP 7: Update is_chat_in_schedule_window function
-- =============================================================================

-- Drop existing function first to allow parameter name change
DROP FUNCTION IF EXISTS public.is_chat_in_schedule_window(INT);

CREATE OR REPLACE FUNCTION public.is_chat_in_schedule_window(p_chat_id INT)
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
    v_current_day INTEGER;
    v_window JSONB;
    v_i INTEGER;
    v_window_count INTEGER;
BEGIN
    -- Get chat details
    SELECT
        start_mode,
        schedule_type,
        schedule_timezone,
        scheduled_start_at,
        schedule_windows
    INTO v_chat
    FROM public.chats
    WHERE id = p_chat_id;

    -- If not scheduled mode, always in window
    IF v_chat.start_mode != 'scheduled' THEN
        RETURN TRUE;
    END IF;

    v_now := NOW();

    -- Handle one-time schedule
    IF v_chat.schedule_type = 'once' THEN
        RETURN v_now >= v_chat.scheduled_start_at;
    END IF;

    -- Handle recurring schedule with new flexible windows
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

    RETURN FALSE;
END;
$$;

-- =============================================================================
-- STEP 8: Helper function to check if current time is in a single window
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_in_single_window(
    p_current_day INTEGER,
    p_current_time TIME,
    p_window JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_start_day INTEGER;
    v_end_day INTEGER;
    v_start_time TIME;
    v_end_time TIME;
    v_check_day INTEGER;
    v_adjusted_end_day INTEGER;
BEGIN
    v_start_day := day_name_to_number(p_window->>'start_day');
    v_end_day := day_name_to_number(p_window->>'end_day');
    v_start_time := (p_window->>'start_time')::TIME;
    v_end_time := (p_window->>'end_time')::TIME;

    -- Same-day window (simple case)
    IF v_start_day = v_end_day THEN
        IF p_current_day = v_start_day THEN
            RETURN p_current_time >= v_start_time AND p_current_time < v_end_time;
        END IF;
        RETURN FALSE;
    END IF;

    -- Cross-day window (handles week wraparound)
    v_adjusted_end_day := v_end_day;
    IF v_end_day < v_start_day THEN
        v_adjusted_end_day := v_end_day + 7;
    END IF;

    v_check_day := p_current_day;
    IF p_current_day < v_start_day THEN
        v_check_day := p_current_day + 7;
    END IF;

    -- Check if we're on the start day (after start time)
    IF v_check_day = v_start_day THEN
        RETURN p_current_time >= v_start_time;
    END IF;

    -- Check if we're on the end day (before end time)
    IF (v_check_day % 7) = v_end_day OR v_check_day = v_adjusted_end_day THEN
        RETURN p_current_time < v_end_time;
    END IF;

    -- Check if we're on a middle day (fully within window)
    IF v_check_day > v_start_day AND v_check_day < v_adjusted_end_day THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;

-- =============================================================================
-- STEP 9: Reset existing recurring schedules (require reconfiguration)
-- =============================================================================

UPDATE public.chats
SET start_mode = 'manual',
    schedule_type = NULL,
    schedule_paused = FALSE
WHERE start_mode = 'scheduled'
  AND schedule_type = 'recurring';

-- =============================================================================
-- STEP 10: Drop old columns
-- =============================================================================

-- First drop constraints that reference these columns
ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_recurring_requires_fields;
ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_schedule_time_order;
ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chats_schedule_days_valid;

-- Drop the old columns
ALTER TABLE public.chats DROP COLUMN IF EXISTS schedule_days;
ALTER TABLE public.chats DROP COLUMN IF EXISTS schedule_start_time;
ALTER TABLE public.chats DROP COLUMN IF EXISTS schedule_end_time;

-- Drop the old validation function
DROP FUNCTION IF EXISTS public.validate_schedule_days(TEXT[]);

-- =============================================================================
-- STEP 11: Add constraint for recurring schedules requiring windows
-- =============================================================================

ALTER TABLE public.chats
ADD CONSTRAINT chats_recurring_requires_windows
CHECK (
    schedule_type != 'recurring' OR (
        schedule_windows IS NOT NULL AND
        jsonb_array_length(schedule_windows) > 0
    )
);

-- =============================================================================
-- STEP 12: Add constraint for window validation
-- =============================================================================

ALTER TABLE public.chats
ADD CONSTRAINT chats_schedule_windows_valid
CHECK (validate_schedule_windows(schedule_windows));

-- =============================================================================
-- STEP 13: Add index for efficient querying
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_chats_schedule_windows
ON public.chats USING GIN (schedule_windows)
WHERE schedule_windows IS NOT NULL;

-- =============================================================================
-- STEP 14: Comments
-- =============================================================================

COMMENT ON FUNCTION public.day_name_to_number IS
'Converts day name to number (0=Sunday, 6=Saturday)';

COMMENT ON FUNCTION public.validate_schedule_window IS
'Validates a single schedule window object';

COMMENT ON FUNCTION public.window_to_week_minutes IS
'Converts a schedule window to minutes from start of week for overlap detection';

COMMENT ON FUNCTION public.windows_overlap IS
'Checks if two schedule windows have any overlapping time';

COMMENT ON FUNCTION public.validate_schedule_windows IS
'Validates entire schedule_windows array: checks each window and ensures no overlaps';

COMMENT ON FUNCTION public.is_in_single_window IS
'Checks if current day/time falls within a single schedule window';
