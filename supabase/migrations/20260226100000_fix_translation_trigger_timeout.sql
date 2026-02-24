-- Fix: pg_net timeout for translation triggers
-- The translate Edge Function calls an LLM which takes 10-30 seconds,
-- but net.http_post defaults to 5000ms timeout. Increase to 60 seconds.

-- Update trigger_translate_chat with 60s timeout
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
  -- Skip if translations are not enabled for this chat
  IF NOT NEW.translations_enabled THEN
    RAISE LOG 'Translation skipped for chat %: translations_enabled = false', NEW.id;
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
  v_url := 'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/translate';

  -- Build request body with all translatable fields + languages filter
  v_body := jsonb_build_object(
    'chat_id', NEW.id,
    'languages', to_jsonb(NEW.translation_languages),
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
  -- Use 60s timeout since the translate function calls an LLM
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body,
    timeout_milliseconds := 60000
  ) INTO v_request_id;

  RAISE LOG 'Translation requested for chat % (request_id: %, languages: %)', NEW.id, v_request_id, NEW.translation_languages;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the INSERT
  RAISE WARNING 'Translation trigger error for chat %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- Update trigger_translate_proposition with 60s timeout
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
  v_translations_enabled BOOLEAN;
  v_translation_languages TEXT[];
BEGIN
  -- Skip carried-forward propositions (they already have translations)
  IF NEW.carried_from_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Look up chat's translation settings via round -> cycle -> chat
  SELECT c.translations_enabled, c.translation_languages
  INTO v_translations_enabled, v_translation_languages
  FROM rounds r
  INNER JOIN cycles cy ON cy.id = r.cycle_id
  INNER JOIN chats c ON c.id = cy.chat_id
  WHERE r.id = NEW.round_id;

  -- Skip if translations are not enabled
  IF NOT COALESCE(v_translations_enabled, false) THEN
    RAISE LOG 'Translation skipped for proposition %: chat translations_enabled = false', NEW.id;
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
  v_url := 'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/translate';

  -- Build request body with languages filter
  v_body := jsonb_build_object(
    'proposition_id', NEW.id,
    'text', NEW.content,
    'entity_type', 'proposition',
    'field_name', 'content',
    'languages', to_jsonb(v_translation_languages)
  );

  -- Call Edge Function via pg_net (async, non-blocking)
  -- Use 60s timeout since the translate function calls an LLM
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body,
    timeout_milliseconds := 60000
  ) INTO v_request_id;

  RAISE LOG 'Translation requested for proposition % (request_id: %, languages: %)', NEW.id, v_request_id, v_translation_languages;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the INSERT
  RAISE WARNING 'Translation trigger error for proposition %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;
