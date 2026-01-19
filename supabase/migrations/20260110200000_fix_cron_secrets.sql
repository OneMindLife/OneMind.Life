-- =============================================================================
-- MIGRATION: Fix cron job secrets configuration
-- =============================================================================
-- Updates cron jobs to use secure secrets for Edge Function authentication
-- =============================================================================

-- ============================================================================
-- STEP 1: Update process-timers cron job with secure secret
-- ============================================================================

-- Remove existing cron job
SELECT cron.unschedule('process-timers');

-- Recreate with secure auth header
SELECT cron.schedule(
    'process-timers',
    '* * * * *',  -- Every minute
    $$
    SELECT net.http_post(
        url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/process-timers',
        headers := '{"Content-Type": "application/json", "X-Cron-Secret": "855dd968210a46ed2334a6281b016a94ce4fb56bfc496851"}'::jsonb,
        body := '{}'::jsonb
    ) AS request_id;
    $$
);

-- ============================================================================
-- STEP 2: Recreate process-auto-refills with same secret
-- ============================================================================

-- Remove existing cron job if exists
SELECT cron.unschedule('process-auto-refills');

-- Recreate with secure auth header
SELECT cron.schedule(
    'process-auto-refills',
    '* * * * *',  -- Every minute
    $$
    SELECT net.http_post(
        url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/process-auto-refill',
        headers := '{"Content-Type": "application/json", "Authorization": "Bearer 855dd968210a46ed2334a6281b016a94ce4fb56bfc496851"}'::jsonb,
        body := '{}'::jsonb
    ) AS request_id;
    $$
);
