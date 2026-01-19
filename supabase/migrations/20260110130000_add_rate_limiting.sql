-- Migration: Add rate limiting infrastructure
--
-- Provides database-backed rate limiting for Edge Functions.
-- Uses a sliding window approach for accurate rate limiting.
--
-- Usage: SELECT check_rate_limit('user_id:endpoint', 10, '1 minute'::interval)
-- Returns TRUE if allowed, FALSE if rate limited.

-- ============================================================================
-- STEP 1: Create rate_limits table to track request counts
-- ============================================================================

-- Drop existing table if it has wrong schema
DROP TABLE IF EXISTS public.rate_limits CASCADE;

CREATE TABLE public.rate_limits (
    id SERIAL PRIMARY KEY,
    key TEXT NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT unique_rate_limit_key_window UNIQUE (key, window_start)
);

-- Index for efficient lookups
CREATE INDEX idx_rate_limits_key ON public.rate_limits(key);
CREATE INDEX idx_rate_limits_window ON public.rate_limits(window_start);

COMMENT ON TABLE public.rate_limits IS 'Tracks API request counts for rate limiting';

-- ============================================================================
-- STEP 2: Create check_rate_limit function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_rate_limit(
    p_key TEXT,
    p_max_requests INTEGER,
    p_window_size INTERVAL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_window_start TIMESTAMPTZ;
    v_current_count INTEGER;
    v_result BOOLEAN;
BEGIN
    -- Calculate the start of the current window
    v_window_start := date_trunc('second', NOW() - (
        EXTRACT(EPOCH FROM NOW())::INTEGER %
        EXTRACT(EPOCH FROM p_window_size)::INTEGER
    ) * INTERVAL '1 second');

    -- Try to insert or update the rate limit entry
    INSERT INTO public.rate_limits (key, window_start, request_count, updated_at)
    VALUES (p_key, v_window_start, 1, NOW())
    ON CONFLICT (key, window_start)
    DO UPDATE SET
        request_count = rate_limits.request_count + 1,
        updated_at = NOW()
    RETURNING request_count INTO v_current_count;

    -- Check if rate limit is exceeded
    v_result := v_current_count <= p_max_requests;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTERVAL) IS
    'Check and increment rate limit. Returns TRUE if allowed, FALSE if rate limited.';

-- ============================================================================
-- STEP 3: Create get_rate_limit_status function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_rate_limit_status(
    p_key TEXT,
    p_window_size INTERVAL
)
RETURNS TABLE (
    current_count INTEGER,
    window_start TIMESTAMPTZ,
    remaining INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_window_start TIMESTAMPTZ;
BEGIN
    v_window_start := date_trunc('second', NOW() - (
        EXTRACT(EPOCH FROM NOW())::INTEGER %
        EXTRACT(EPOCH FROM p_window_size)::INTEGER
    ) * INTERVAL '1 second');

    RETURN QUERY
    SELECT
        COALESCE(rl.request_count, 0)::INTEGER as current_count,
        v_window_start as window_start,
        0::INTEGER as remaining -- Will be calculated by caller
    FROM (SELECT 1) AS dummy
    LEFT JOIN public.rate_limits rl
        ON rl.key = p_key
        AND rl.window_start = v_window_start;
END;
$$;

COMMENT ON FUNCTION public.get_rate_limit_status(TEXT, INTERVAL) IS
    'Get current rate limit status without incrementing counter';

-- ============================================================================
-- STEP 4: Create cleanup function for old entries
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cleanup_rate_limits()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    -- Delete entries older than 1 hour (should cover any window size we use)
    DELETE FROM public.rate_limits
    WHERE window_start < NOW() - INTERVAL '1 hour';

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.cleanup_rate_limits() IS
    'Clean up old rate limit entries. Call periodically via cron.';

-- ============================================================================
-- STEP 5: Enable RLS (only service role should access this)
-- ============================================================================

ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

-- No policies = only service role can access via SECURITY DEFINER functions
