-- =============================================================================
-- MIGRATION: Set schedule_paused on INSERT for recurring chats
-- =============================================================================
-- Bug fix: Recurring chats created outside their schedule windows should start
-- with schedule_paused = TRUE. Previously, they started unpaused regardless of
-- whether the current time was within a schedule window.
-- =============================================================================

-- =============================================================================
-- STEP 1: Create trigger function to evaluate schedule_paused on INSERT
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_schedule_paused_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_now_in_tz TIMESTAMP;
    v_current_time TIME;
    v_current_day INTEGER;
    v_window JSONB;
    v_i INTEGER;
    v_window_count INTEGER;
    v_in_window BOOLEAN := FALSE;
BEGIN
    -- Only process recurring scheduled chats with windows defined
    IF NEW.start_mode = 'scheduled' AND
       NEW.schedule_type = 'recurring' AND
       NEW.schedule_windows IS NOT NULL AND
       jsonb_array_length(NEW.schedule_windows) > 0 THEN

        v_now := NOW();

        -- Convert current time to the chat's timezone
        v_now_in_tz := v_now AT TIME ZONE COALESCE(NEW.schedule_timezone, 'UTC');
        v_current_time := v_now_in_tz::TIME;
        v_current_day := EXTRACT(DOW FROM v_now_in_tz)::INTEGER;  -- 0=Sunday

        v_window_count := jsonb_array_length(NEW.schedule_windows);

        -- Check each window to see if we're currently inside one
        FOR v_i IN 0..(v_window_count - 1) LOOP
            v_window := NEW.schedule_windows->v_i;
            IF is_in_single_window(v_current_day, v_current_time, v_window) THEN
                v_in_window := TRUE;
                EXIT;  -- Found a window we're in, no need to check more
            END IF;
        END LOOP;

        -- If we're NOT in any window, set schedule_paused to TRUE
        IF NOT v_in_window THEN
            NEW.schedule_paused := TRUE;
        ELSE
            -- Explicitly set to FALSE if we're inside a window
            NEW.schedule_paused := FALSE;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_schedule_paused_on_insert IS
'BEFORE INSERT trigger: Sets schedule_paused = TRUE for recurring chats created outside their schedule windows';

-- =============================================================================
-- STEP 2: Create the BEFORE INSERT trigger
-- =============================================================================

DROP TRIGGER IF EXISTS set_schedule_paused_on_insert_trigger ON public.chats;

CREATE TRIGGER set_schedule_paused_on_insert_trigger
    BEFORE INSERT ON public.chats
    FOR EACH ROW
    EXECUTE FUNCTION public.set_schedule_paused_on_insert();

COMMENT ON TRIGGER set_schedule_paused_on_insert_trigger ON public.chats IS
'Ensures recurring chats created outside schedule windows start with schedule_paused = TRUE';
