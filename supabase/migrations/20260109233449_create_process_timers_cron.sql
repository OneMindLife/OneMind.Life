-- Create cron job to call process-timers Edge Function every minute
-- This handles timer expiration, phase advancement, and auto-start

SELECT cron.schedule(
    'process-timers',
    '* * * * *',  -- Every minute
    $$
    SELECT extensions.http_post(
        'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/process-timers',
        '{}',
        'application/json'
    );
    $$
);
