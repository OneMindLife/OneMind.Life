-- Migration: Add cron job monitoring
--
-- Provides monitoring for cron jobs:
-- - Logs execution times and results
-- - Detects missed executions
-- - Provides health check functions

-- ============================================================================
-- STEP 1: Create cron execution log table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.cron_execution_log (
    id SERIAL PRIMARY KEY,
    job_name TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'running',
    result_code INTEGER,
    error_message TEXT,
    execution_time_ms INTEGER,
    metadata JSONB,
    CONSTRAINT cron_execution_log_status_check
        CHECK (status IN ('running', 'success', 'error', 'timeout'))
);

CREATE INDEX idx_cron_execution_log_job_name ON public.cron_execution_log(job_name);
CREATE INDEX idx_cron_execution_log_started_at ON public.cron_execution_log(started_at DESC);
CREATE INDEX idx_cron_execution_log_status ON public.cron_execution_log(status);

COMMENT ON TABLE public.cron_execution_log IS 'Log of cron job executions for monitoring';

-- ============================================================================
-- STEP 2: Function to start a cron execution (returns execution_id)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cron_execution_start(
    p_job_name TEXT,
    p_metadata JSONB DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO public.cron_execution_log (job_name, metadata)
    VALUES (p_job_name, p_metadata)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.cron_execution_start(TEXT, JSONB) IS
    'Start logging a cron job execution. Returns execution ID.';

-- ============================================================================
-- STEP 3: Function to complete a cron execution
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cron_execution_complete(
    p_execution_id INTEGER,
    p_status TEXT,
    p_result_code INTEGER DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.cron_execution_log
    SET
        completed_at = NOW(),
        status = p_status,
        result_code = p_result_code,
        error_message = p_error_message,
        execution_time_ms = EXTRACT(MILLISECONDS FROM (NOW() - started_at))::INTEGER
    WHERE id = p_execution_id;
END;
$$;

COMMENT ON FUNCTION public.cron_execution_complete(INTEGER, TEXT, INTEGER, TEXT) IS
    'Complete a cron job execution with status.';

-- ============================================================================
-- STEP 4: Function to check cron job health
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_cron_health(p_job_name TEXT)
RETURNS TABLE (
    is_healthy BOOLEAN,
    last_execution_at TIMESTAMPTZ,
    last_status TEXT,
    executions_last_hour INTEGER,
    errors_last_hour INTEGER,
    avg_execution_time_ms NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_last_execution RECORD;
    v_hour_ago TIMESTAMPTZ := NOW() - INTERVAL '1 hour';
BEGIN
    -- Get last execution
    SELECT
        cel.started_at,
        cel.status
    INTO v_last_execution
    FROM public.cron_execution_log cel
    WHERE cel.job_name = p_job_name
    ORDER BY cel.started_at DESC
    LIMIT 1;

    -- Calculate stats
    RETURN QUERY
    SELECT
        -- Is healthy if last execution was within 5 minutes and was successful
        (v_last_execution.started_at > NOW() - INTERVAL '5 minutes' AND
         v_last_execution.status = 'success') AS is_healthy,
        v_last_execution.started_at AS last_execution_at,
        v_last_execution.status AS last_status,
        (SELECT COUNT(*)::INTEGER FROM public.cron_execution_log cel
         WHERE cel.job_name = p_job_name AND cel.started_at > v_hour_ago) AS executions_last_hour,
        (SELECT COUNT(*)::INTEGER FROM public.cron_execution_log cel
         WHERE cel.job_name = p_job_name AND cel.started_at > v_hour_ago
         AND cel.status = 'error') AS errors_last_hour,
        (SELECT AVG(cel.execution_time_ms)::NUMERIC FROM public.cron_execution_log cel
         WHERE cel.job_name = p_job_name AND cel.started_at > v_hour_ago
         AND cel.status = 'success') AS avg_execution_time_ms;
END;
$$;

COMMENT ON FUNCTION public.check_cron_health(TEXT) IS
    'Check health status of a cron job.';

-- ============================================================================
-- STEP 5: Function to clean up old cron logs
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cleanup_cron_logs(p_retention_days INTEGER DEFAULT 7)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM public.cron_execution_log
    WHERE started_at < NOW() - (p_retention_days || ' days')::INTERVAL;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.cleanup_cron_logs(INTEGER) IS
    'Clean up old cron execution logs. Default retention is 7 days.';

-- ============================================================================
-- STEP 6: Add cleanup cron job
-- ============================================================================

-- Clean up old cron logs daily at 3 AM
SELECT cron.schedule(
    'cleanup-cron-logs',
    '0 3 * * *',  -- 3 AM daily
    $$SELECT public.cleanup_cron_logs(7);$$
);

-- Also clean up old rate limits daily
SELECT cron.schedule(
    'cleanup-rate-limits',
    '0 4 * * *',  -- 4 AM daily
    $$SELECT public.cleanup_rate_limits();$$
);

-- ============================================================================
-- STEP 7: Enable RLS
-- ============================================================================

ALTER TABLE public.cron_execution_log ENABLE ROW LEVEL SECURITY;

-- Only allow service role to insert/update (via SECURITY DEFINER functions)
-- No policies = no direct access
