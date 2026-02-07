-- =============================================================================
-- MIGRATION: Move hardcoded URLs and cron secrets to Supabase Vault
-- =============================================================================
-- This migration:
-- 1. Stores project_url and cron_secret in vault (configurable per instance)
-- 2. Creates get_cron_headers() helper to read cron auth from vault
-- 3. Rewrites get_edge_function_url() to read project_url from vault
-- 4. Recreates all 3 cron jobs using the vault-based helpers
-- 5. Updates trigger functions to use get_edge_function_url()
--
-- Old migrations are left untouched — they've already run on production.
-- This migration supersedes them for the URL/auth configuration.
-- =============================================================================

-- =============================================================================
-- STEP 1: Store project URL and cron secret in vault
-- =============================================================================
-- Users must update these via Supabase Dashboard > Vault for their own instance.

-- Only create if not already set (vault.create_secret is the proper API)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'project_url') THEN
    PERFORM vault.create_secret('https://YOUR_PROJECT_REF.supabase.co', 'project_url', 'Project URL for edge function helpers');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'cron_secret') THEN
    PERFORM vault.create_secret('YOUR_CRON_SECRET_HERE', 'cron_secret', 'Cron job authentication secret');
  END IF;
END;
$$;

-- =============================================================================
-- STEP 2: Create helper function to get cron auth headers from vault
-- =============================================================================

CREATE OR REPLACE FUNCTION get_cron_headers()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret';

  RETURN jsonb_build_object(
    'Content-Type', 'application/json',
    'X-Cron-Secret', COALESCE(v_secret, 'not-configured')
  );
END;
$$;

COMMENT ON FUNCTION get_cron_headers() IS
  'Returns JSON headers for cron job HTTP requests, reading the cron secret from vault.';

-- =============================================================================
-- STEP 3: Rewrite get_edge_function_url() to read from vault
-- =============================================================================
-- Previously used current_setting('app.settings.project_ref') which was never set.
-- Now reads project_url from vault.decrypted_secrets.

CREATE OR REPLACE FUNCTION get_edge_function_url(func_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_project_url TEXT;
BEGIN
  SELECT decrypted_secret INTO v_project_url
  FROM vault.decrypted_secrets
  WHERE name = 'project_url';

  IF v_project_url IS NULL THEN
    RAISE WARNING 'Vault secret "project_url" not set. Cron jobs will fail.';
    RETURN 'https://NOT_CONFIGURED/functions/v1/' || func_name;
  END IF;

  RETURN rtrim(v_project_url, '/') || '/functions/v1/' || func_name;
END;
$$;

COMMENT ON FUNCTION get_edge_function_url(TEXT) IS
  'Builds an Edge Function URL from the project_url vault secret. '
  'Returns a warning URL if the vault secret is not configured.';

-- =============================================================================
-- STEP 3b: Restrict access to helper functions
-- =============================================================================
-- These functions read secrets from vault. Only postgres and service_role
-- (used by pg_cron internally) should be able to call them.

REVOKE EXECUTE ON FUNCTION get_cron_headers() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION get_edge_function_url(TEXT) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- STEP 4: Recreate all cron jobs using vault-based helpers
-- =============================================================================

-- 4a. process-timers (every minute)
SELECT cron.unschedule('process-timers');

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

-- 4b. process-auto-refills (every minute)
SELECT cron.unschedule('process-auto-refills');

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

-- 4c. cleanup-inactive-chats (Sunday 3 AM UTC)
SELECT cron.unschedule('cleanup-inactive-chats');

SELECT cron.schedule(
    'cleanup-inactive-chats',
    '0 3 * * 0',
    $$
    SELECT net.http_post(
        url := get_edge_function_url('cleanup-inactive-chats'),
        headers := get_cron_headers(),
        body := '{"dry_run": false}'::jsonb
    ) AS request_id;
    $$
);

-- =============================================================================
-- STEP 5: Update trigger functions to use get_edge_function_url()
-- =============================================================================

-- 5a. trigger_translate_chat() — latest version from 20260201204821
CREATE OR REPLACE FUNCTION trigger_translate_chat()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
BEGIN
  -- Get service role key from vault
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  -- If no key found, log warning and skip (don't fail the INSERT)
  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'Translation skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  -- Build Edge Function URL from vault
  v_url := get_edge_function_url('translate');

  -- Build request body with name (always present)
  v_body := jsonb_build_object(
    'chat_id', NEW.id,
    'texts', jsonb_build_array(
      jsonb_build_object('text', NEW.name, 'field_name', 'name')
    )
  );

  -- Add initial_message if present
  IF NEW.initial_message IS NOT NULL AND NEW.initial_message != '' THEN
    v_body := jsonb_set(
      v_body,
      '{texts}',
      v_body->'texts' || jsonb_build_array(
        jsonb_build_object('text', NEW.initial_message, 'field_name', 'initial_message')
      )
    );
  END IF;

  -- Add description if present
  IF NEW.description IS NOT NULL AND NEW.description != '' THEN
    v_body := jsonb_set(
      v_body,
      '{texts}',
      v_body->'texts' || jsonb_build_array(
        jsonb_build_object('text', NEW.description, 'field_name', 'description')
      )
    );
  END IF;

  -- Call Edge Function via pg_net (async, non-blocking)
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body
  ) INTO v_request_id;

  -- Log the request ID for debugging
  RAISE LOG 'Translation requested for chat % (request_id: %)', NEW.id, v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the INSERT
  RAISE WARNING 'Translation trigger error for chat %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- 5b. trigger_translate_proposition()
CREATE OR REPLACE FUNCTION trigger_translate_proposition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
BEGIN
  -- Skip carried-forward propositions (they already have translations)
  IF NEW.carried_from_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Get service role key from vault
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  -- If no key found, log warning and skip (don't fail the INSERT)
  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'Translation skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  -- Build Edge Function URL from vault
  v_url := get_edge_function_url('translate');

  -- Build request body
  v_body := jsonb_build_object(
    'proposition_id', NEW.id,
    'text', NEW.content,
    'entity_type', 'proposition',
    'field_name', 'content'
  );

  -- Call Edge Function via pg_net (async, non-blocking)
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body
  ) INTO v_request_id;

  -- Log the request ID for debugging
  RAISE LOG 'Translation requested for proposition % (request_id: %)', NEW.id, v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the INSERT
  RAISE WARNING 'Translation trigger error for proposition %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- 5c. trigger_ai_proposer_on_proposing()
CREATE OR REPLACE FUNCTION trigger_ai_proposer_on_proposing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_chat RECORD;
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
  v_cycle_id BIGINT;
  v_chat_id BIGINT;
BEGIN
  -- Only trigger when phase becomes 'proposing'
  IF NEW.phase != 'proposing' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.phase = 'proposing' THEN
    RETURN NEW;
  END IF;

  -- Get the chat_id from the cycle
  SELECT c.chat_id INTO v_chat_id
  FROM cycles c
  WHERE c.id = NEW.cycle_id;

  -- Get chat settings to check if AI is enabled
  SELECT
    ch.id,
    ch.name,
    ch.initial_message,
    ch.description,
    ch.enable_ai_participant,
    ch.ai_propositions_count
  INTO v_chat
  FROM chats ch
  WHERE ch.id = v_chat_id;

  -- Skip if AI participant is disabled for this chat
  IF NOT v_chat.enable_ai_participant THEN
    RAISE LOG 'AI proposer skipped for round %: AI participant disabled for chat %',
      NEW.id, v_chat_id;
    RETURN NEW;
  END IF;

  -- Skip if ai_propositions_count is 0 or NULL
  IF v_chat.ai_propositions_count IS NULL OR v_chat.ai_propositions_count = 0 THEN
    RAISE LOG 'AI proposer skipped for round %: ai_propositions_count is %',
      NEW.id, COALESCE(v_chat.ai_propositions_count::TEXT, 'NULL');
    RETURN NEW;
  END IF;

  -- Get service role key from vault
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  -- If no key found, log warning and skip (don't fail the operation)
  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'AI proposer skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  -- Build Edge Function URL from vault
  v_url := get_edge_function_url('ai-proposer');

  -- Build request body
  v_body := jsonb_build_object(
    'round_id', NEW.id,
    'chat_id', v_chat_id,
    'cycle_id', NEW.cycle_id,
    'custom_id', NEW.custom_id
  );

  -- Call Edge Function via pg_net (async, non-blocking)
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body
  ) INTO v_request_id;

  -- Log the request for debugging
  RAISE LOG 'AI proposer called for round % in chat % (request_id: %)',
    NEW.id, v_chat_id, v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the operation
  RAISE WARNING 'AI proposer trigger error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
-- After applying this migration, configure vault secrets for your instance:
--
--   -- In Supabase SQL Editor:
--   UPDATE vault.secrets SET secret = 'https://YOUR_REF.supabase.co'
--   WHERE name = 'project_url';
--
--   UPDATE vault.secrets SET secret = 'your-actual-cron-secret'
--   WHERE name = 'cron_secret';
--
-- Or via Dashboard: Project Settings > Vault > Edit secret
-- =============================================================================
