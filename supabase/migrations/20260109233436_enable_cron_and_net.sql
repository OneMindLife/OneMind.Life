-- Enable pg_cron and pg_net extensions for timer processing
-- These extensions allow scheduled jobs and HTTP requests from the database

-- pg_cron: Allows scheduling periodic jobs
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- pg_net: Allows making HTTP requests from SQL
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Grant usage to postgres role
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;
