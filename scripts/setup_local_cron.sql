-- Setup local development cron jobs
-- Run after `npx supabase db reset --local`
--
-- Usage: psql "postgresql://postgres:postgres@localhost:54322/postgres" -f scripts/setup_local_cron.sql

-- =============================================================================
-- STEP 1: Set vault secrets for local development
-- =============================================================================
-- These override the placeholder values from the migration so cron jobs
-- and trigger functions resolve to the local Supabase instance.

-- Delete and recreate vault secrets for local dev (vault.create_secret is the proper API)
DELETE FROM vault.secrets WHERE name = 'project_url';
SELECT vault.create_secret('http://host.docker.internal:54321', 'project_url', 'Local dev project URL');

DELETE FROM vault.secrets WHERE name = 'cron_secret';
SELECT vault.create_secret('local-dev-secret', 'cron_secret', 'Local dev cron secret');

-- =============================================================================
-- STEP 2: Remove production cron jobs that point to remote URLs
-- =============================================================================

SELECT cron.unschedule('process-timers');
SELECT cron.unschedule('process-auto-refills');
SELECT cron.unschedule('cleanup-inactive-chats');
SELECT cron.unschedule('moltbook-agent-heartbeat');
SELECT cron.unschedule('moltcourt-agent-heartbeat');

-- =============================================================================
-- STEP 3: Recreate cron jobs for local development
-- =============================================================================
-- These use the vault-based helpers which now resolve to local URLs.

-- Add local cron job for process-timers
SELECT cron.schedule(
    'process-timers',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := get_edge_function_url('process-timers'),
        headers := get_cron_headers(),
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
        url := get_edge_function_url('process-auto-refill'),
        headers := get_cron_headers(),
        body := '{}'::jsonb
    ) AS request_id;
    $$
);

-- Add local cron job for cleanup-inactive-chats (runs every minute locally for testing)
SELECT cron.schedule(
    'cleanup-inactive-chats',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := get_edge_function_url('cleanup-inactive-chats'),
        headers := get_cron_headers(),
        body := '{"dry_run": true}'::jsonb
    ) AS request_id;
    $$
);

-- Add local cron job for moltbook-agent (runs every minute locally for testing, production is every 30 min)
SELECT cron.schedule(
    'moltbook-agent-heartbeat',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := get_edge_function_url('moltbook-agent'),
        headers := get_cron_headers(),
        body := '{}'::jsonb
    ) AS request_id;
    $$
);

-- Add local cron job for moltcourt-agent (runs every minute locally for testing, production is every 4 hours)
SELECT cron.schedule(
    'moltcourt-agent-heartbeat',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := get_edge_function_url('moltcourt-agent'),
        headers := get_cron_headers(),
        body := '{"source": "heartbeat"}'::jsonb
    ) AS request_id;
    $$
);

-- =============================================================================
-- STEP 4: Verify setup
-- =============================================================================

SELECT jobname, schedule,
       CASE
           WHEN command LIKE '%get_edge_function_url%' THEN 'VAULT-BASED'
           WHEN command LIKE '%host.docker.internal%' THEN 'LOCAL'
           WHEN command LIKE '%supabase.co%' THEN 'PRODUCTION'
           ELSE 'OTHER'
       END as target
FROM cron.job
WHERE jobname IN ('process-timers', 'process-auto-refills', 'cleanup-inactive-chats', 'moltbook-agent-heartbeat', 'moltcourt-agent-heartbeat');
