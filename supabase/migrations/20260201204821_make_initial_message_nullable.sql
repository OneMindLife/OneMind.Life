-- =============================================================================
-- MIGRATION: Make initial_message nullable and update translation trigger
-- =============================================================================
-- This migration allows chats to be created without an initial message.
-- Instead, users can provide an optional description.
--
-- Changes:
-- 1. Make initial_message column nullable with empty string default
-- 2. Update trigger_translate_chat() to conditionally include initial_message
-- =============================================================================

-- =============================================================================
-- STEP 1: Make initial_message nullable
-- =============================================================================

ALTER TABLE chats ALTER COLUMN initial_message DROP NOT NULL;
ALTER TABLE chats ALTER COLUMN initial_message SET DEFAULT '';

-- =============================================================================
-- STEP 2: Update trigger function to handle NULL initial_message
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
  v_url := 'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/translate';

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

-- =============================================================================
-- STEP 3: Update comment
-- =============================================================================

COMMENT ON FUNCTION trigger_translate_chat() IS
  'Trigger function that calls translate Edge Function when a chat is created. '
  'Conditionally includes name (always), initial_message (if present), and description (if present). '
  'Uses pg_net for async HTTP calls and service role key from vault for auth.';

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
