-- Fix round-minute timer to truncate milliseconds
-- Prevents extra minute being added due to fractional seconds

CREATE OR REPLACE FUNCTION calculate_round_minute_end(duration_seconds INTEGER)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE  -- Changed from IMMUTABLE since it uses NOW()
AS $$
DECLARE
    v_now_truncated TIMESTAMPTZ;
    v_min_end TIMESTAMPTZ;
BEGIN
    -- Truncate NOW() to seconds to avoid milliseconds causing extra rounding
    v_now_truncated := date_trunc('second', NOW());
    v_min_end := v_now_truncated + (duration_seconds * INTERVAL '1 second');

    -- If already at :00, use that; otherwise round up to next minute
    IF EXTRACT(SECOND FROM v_min_end) = 0 THEN
        RETURN v_min_end;
    ELSE
        RETURN date_trunc('minute', v_min_end) + INTERVAL '1 minute';
    END IF;
END;
$$;

COMMENT ON FUNCTION calculate_round_minute_end IS
'Calculates phase end time rounded up to the next :00 seconds to align with cron job schedule.
Truncates milliseconds first to prevent extra minute being added.
Example: NOW()=1:00:42, duration=60s → 1:02:00 (not 1:01:42)';
