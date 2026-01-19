-- Setup local development cron jobs
-- Run after `npx supabase db reset --local`
--
-- Usage: psql "postgresql://postgres:postgres@localhost:54322/postgres" -f scripts/setup_local_cron.sql

-- Remove production cron jobs that point to remote URLs
SELECT cron.unschedule('process-timers');
SELECT cron.unschedule('process-auto-refills');

-- Add local cron job for process-timers
SELECT cron.schedule(
    'process-timers',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := 'http://host.docker.internal:54321/functions/v1/process-timers',
        headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"}'::jsonb,
        body := '{}'::jsonb
    ) AS request_id;
    $$
);

-- Add local cron job for process-auto-refills
SELECT cron.schedule(
    'process-auto-refills',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := 'http://host.docker.internal:54321/functions/v1/process-auto-refill',
        headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"}'::jsonb,
        body := '{}'::jsonb
    ) AS request_id;
    $$
);

-- Verify setup
SELECT jobname, schedule,
       CASE
           WHEN command LIKE '%host.docker.internal%' THEN 'LOCAL'
           WHEN command LIKE '%supabase.co%' THEN 'PRODUCTION'
           ELSE 'OTHER'
       END as target
FROM cron.job
WHERE jobname IN ('process-timers', 'process-auto-refills');
