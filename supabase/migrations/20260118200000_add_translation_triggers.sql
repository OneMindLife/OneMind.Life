-- =============================================================================
-- MIGRATION: Add database triggers for automatic translations
-- =============================================================================
-- This migration creates triggers that automatically call the translate Edge
-- Function when chats or propositions are created. This replaces the fire-and-
-- forget pattern in the Flutter app with reliable database-level triggers.
--
-- Architecture:
-- 1. Trigger fires on INSERT to chats/propositions
-- 2. Trigger function calls Edge Function via pg_net (async HTTP)
-- 3. Edge Function handles its own auth (verify_jwt=false at Supabase level)
-- 4. Edge Function uses service role key passed in Authorization header
--
-- Benefits:
-- - Reliable: translations happen even if client disconnects
-- - Decoupled: client doesn't need to manage translation logic
-- - Secure: uses service role key from vault
-- - Scalable: easy to add more entity types
-- =============================================================================

-- =============================================================================
-- PREREQUISITE: Create vault secret via Supabase Dashboard
-- =============================================================================
-- IMPORTANT: Before this trigger will work, you must create a vault secret:
--
-- 1. Go to Supabase Dashboard > Project Settings > Vault
-- 2. Click "New Secret"
-- 3. Name: edge_function_service_key
-- 4. Value: Your SUPABASE_SERVICE_ROLE_KEY (from Project Settings > API)
-- 5. Description: Service role key for Edge Function authentication from DB triggers
--
-- NOTE: Cannot create vault secrets in migrations due to encryption function
-- permissions. The trigger will log a warning and skip translation if the
-- secret is not configured (it won't fail the INSERT).

-- =============================================================================
-- STEP 2: Create helper function to get Edge Function URL
-- =============================================================================

CREATE OR REPLACE FUNCTION get_edge_function_url(func_name TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  -- Construct URL from project ref
  -- Format: https://<project_ref>.supabase.co/functions/v1/<func_name>
  SELECT 'https://' ||
         current_setting('app.settings.project_ref', true) ||
         '.supabase.co/functions/v1/' ||
         func_name;
$$;

-- Set project ref for URL construction (this is set during migration push)
-- In production, this is automatically available
DO $$
BEGIN
  -- Try to set from environment or use a placeholder for local dev
  PERFORM set_config('app.settings.project_ref',
    COALESCE(current_setting('app.settings.project_ref', true), 'YOUR_PROJECT_REF'),
    false
  );
EXCEPTION WHEN OTHERS THEN
  -- Ignore errors - config may already be set
  NULL;
END $$;

-- =============================================================================
-- STEP 3: Create trigger function for chat translations
-- =============================================================================

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

  -- Build Edge Function URL
  v_url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/translate';

  -- Build request body with all translatable fields
  v_body := jsonb_build_object(
    'chat_id', NEW.id,
    'texts', jsonb_build_array(
      jsonb_build_object('text', NEW.name, 'field_name', 'name'),
      jsonb_build_object('text', NEW.initial_message, 'field_name', 'initial_message')
    )
  );

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

-- =============================================================================
-- STEP 4: Create trigger function for proposition translations
-- =============================================================================

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

  -- Build Edge Function URL
  v_url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/translate';

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

-- =============================================================================
-- STEP 5: Create triggers on chats and propositions tables
-- =============================================================================

-- Drop existing triggers if they exist (idempotent)
DROP TRIGGER IF EXISTS translate_chat_on_insert ON chats;
DROP TRIGGER IF EXISTS translate_proposition_on_insert ON propositions;

-- Create trigger for chats
CREATE TRIGGER translate_chat_on_insert
  AFTER INSERT ON chats
  FOR EACH ROW
  EXECUTE FUNCTION trigger_translate_chat();

-- Create trigger for propositions
CREATE TRIGGER translate_proposition_on_insert
  AFTER INSERT ON propositions
  FOR EACH ROW
  EXECUTE FUNCTION trigger_translate_proposition();

-- =============================================================================
-- STEP 6: Add comments for documentation
-- =============================================================================

COMMENT ON FUNCTION trigger_translate_chat() IS
  'Trigger function that calls translate Edge Function when a chat is created. '
  'Uses pg_net for async HTTP calls and service role key from vault for auth.';

COMMENT ON FUNCTION trigger_translate_proposition() IS
  'Trigger function that calls translate Edge Function when a proposition is created. '
  'Skips carried-forward propositions. Uses pg_net for async HTTP calls.';

COMMENT ON TRIGGER translate_chat_on_insert ON chats IS
  'Automatically triggers AI translation of chat name, initial_message, and description on INSERT.';

COMMENT ON TRIGGER translate_proposition_on_insert ON propositions IS
  'Automatically triggers AI translation of proposition content on INSERT (new propositions only).';

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
-- Next steps:
-- 1. Set the service role key in Supabase Dashboard > Settings > Vault
--    - Name: edge_function_service_key
--    - Value: Your SUPABASE_SERVICE_ROLE_KEY
-- 2. Deploy the translate Edge Function with --no-verify-jwt flag
-- 3. Set ANTHROPIC_API_KEY in Edge Function secrets
-- =============================================================================
