-- =============================================================================
-- MIGRATION: Update cron job with authentication
-- =============================================================================
-- This migration updates the process-timers cron job to include
-- the X-Cron-Secret header for authentication
-- =============================================================================

-- Remove existing cron job
SELECT cron.unschedule('process-timers');

-- Recreate with auth header
SELECT cron.schedule(
    'process-timers',
    '* * * * *',  -- Every minute
    $$
    SELECT net.http_post(
        url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/process-timers',
        headers := '{"Content-Type": "application/json", "X-Cron-Secret": "process-timers-cron-secret"}'::jsonb,
        body := '{}'::jsonb
    );
    $$
);
