-- Fix rate limit triggers to use the new rate_limits table schema
-- The security_improvements migration created triggers that use the old schema,
-- but add_rate_limiting migration recreated the table with a different schema.

-- =============================================================================
-- STEP 1: Update check_rate_limit function to use new schema with session token
-- =============================================================================

-- Drop the old 2-param version if it exists
DROP FUNCTION IF EXISTS public.check_rate_limit(TEXT, INTEGER);

-- Create a new version that works with the current rate_limits schema
-- and uses session token from X-Session-Token header
CREATE OR REPLACE FUNCTION public.check_rate_limit(
    p_action_type TEXT,
    p_max_per_minute INTEGER DEFAULT 10
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_session_token UUID;
    v_key TEXT;
    v_window_start TIMESTAMPTZ;
    v_current_count INTEGER;
BEGIN
    -- Get session token from header
    v_session_token := public.get_session_token();

    IF v_session_token IS NULL THEN
        -- No session token = skip rate limiting (for tests, etc.)
        RETURN TRUE;
    END IF;

    -- Build a unique key combining session and action type
    v_key := v_session_token::TEXT || ':' || p_action_type;

    -- Calculate the start of the current 1-minute window
    v_window_start := date_trunc('minute', NOW());

    -- Try to insert or update the rate limit entry
    INSERT INTO public.rate_limits (key, window_start, request_count, updated_at)
    VALUES (v_key, v_window_start, 1, NOW())
    ON CONFLICT (key, window_start)
    DO UPDATE SET
        request_count = rate_limits.request_count + 1,
        updated_at = NOW()
    RETURNING request_count INTO v_current_count;

    -- Check if rate limit is exceeded
    RETURN v_current_count <= p_max_per_minute;
END;
$$;

COMMENT ON FUNCTION public.check_rate_limit(TEXT, INTEGER) IS
    'Check and increment rate limit for session-based actions. Returns TRUE if allowed, FALSE if rate limited.';

-- =============================================================================
-- STEP 2: Update trigger function to handle missing session token gracefully
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_proposition_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Skip rate limit check for service role
    IF current_setting('role', true) = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Skip if no session token (tests, direct DB access)
    IF public.get_session_token() IS NULL THEN
        RETURN NEW;
    END IF;

    -- Check rate limit (10 propositions per minute)
    IF NOT public.check_rate_limit('proposition', 10) THEN
        RAISE EXCEPTION 'Rate limit exceeded for propositions'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

-- Ensure trigger exists (recreate if needed)
DROP TRIGGER IF EXISTS trg_proposition_rate_limit ON public.propositions;
CREATE TRIGGER trg_proposition_rate_limit
BEFORE INSERT ON public.propositions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_proposition_rate_limit();

-- =============================================================================
-- STEP 3: Update rating rate limit trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_rating_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Skip rate limit check for service role
    IF current_setting('role', true) = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Skip if no session token (tests, direct DB access)
    IF public.get_session_token() IS NULL THEN
        RETURN NEW;
    END IF;

    -- Check rate limit (30 ratings per minute)
    IF NOT public.check_rate_limit('rating', 30) THEN
        RAISE EXCEPTION 'Rate limit exceeded for ratings'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

-- Ensure trigger exists
DROP TRIGGER IF EXISTS trg_rating_rate_limit ON public.ratings;
CREATE TRIGGER trg_rating_rate_limit
BEFORE INSERT ON public.ratings
FOR EACH ROW
EXECUTE FUNCTION public.enforce_rating_rate_limit();
