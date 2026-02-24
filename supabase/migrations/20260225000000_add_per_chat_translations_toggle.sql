-- =============================================================================
-- MIGRATION: Add per-chat translations toggle
-- =============================================================================
-- Allows chat creators to opt-in to automatic translations at creation time.
-- When OFF: no LLM calls, duplicate detection compares raw LOWER(TRIM(content))
-- When ON: current behavior (translate to English, normalize, dedup via translations)
--
-- Default: OFF for new chats, backfill existing chats to ON (backwards compatible)
-- =============================================================================

-- =============================================================================
-- STEP 1: Add columns to chats table
-- =============================================================================

ALTER TABLE chats
  ADD COLUMN IF NOT EXISTS translations_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS translation_languages TEXT[] NOT NULL DEFAULT '{en,es,pt,fr,de}';

-- Constraint: languages must be a subset of supported languages
ALTER TABLE chats
  ADD CONSTRAINT chk_translation_languages_valid
  CHECK (translation_languages <@ ARRAY['en','es','pt','fr','de']::TEXT[]);

-- Constraint: if translations enabled, must have at least 1 language
ALTER TABLE chats
  ADD CONSTRAINT chk_translation_languages_nonempty
  CHECK (NOT translations_enabled OR coalesce(array_length(translation_languages, 1), 0) >= 1);

-- =============================================================================
-- STEP 2: Backfill existing chats to have translations enabled
-- =============================================================================

UPDATE chats SET translations_enabled = true WHERE translations_enabled = false;

-- =============================================================================
-- STEP 3: New function - find_duplicate_proposition_raw
-- =============================================================================
-- Compares LOWER(TRIM(content)) directly on propositions table (no translations JOIN).
-- Used when translations are disabled for a chat.

CREATE OR REPLACE FUNCTION find_duplicate_proposition_raw(
  p_round_id bigint,
  p_normalized_content text
)
RETURNS TABLE (
  proposition_id bigint,
  content text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    p.id AS proposition_id,
    p.content
  FROM propositions p
  WHERE p.round_id = p_round_id
    AND LOWER(TRIM(p.content)) = p_normalized_content
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION find_duplicate_proposition_raw(bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION find_duplicate_proposition_raw(bigint, text) TO authenticated;

COMMENT ON FUNCTION find_duplicate_proposition_raw IS
  'Find existing proposition in a round with matching raw normalized content (no translations). '
  'Used by submit-proposition Edge Function when translations are disabled for the chat.';

-- =============================================================================
-- STEP 4: New helper - get_chat_translation_settings
-- =============================================================================
-- Returns translation settings for the chat that owns a given round.
-- Navigates: round → cycle → chat

CREATE OR REPLACE FUNCTION get_chat_translation_settings(p_round_id bigint)
RETURNS TABLE (
  chat_id bigint,
  translations_enabled boolean,
  translation_languages text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    c.id AS chat_id,
    c.translations_enabled,
    c.translation_languages
  FROM rounds r
  INNER JOIN cycles cy ON cy.id = r.cycle_id
  INNER JOIN chats c ON c.id = cy.chat_id
  WHERE r.id = p_round_id
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION get_chat_translation_settings(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION get_chat_translation_settings(bigint) TO authenticated;

COMMENT ON FUNCTION get_chat_translation_settings IS
  'Returns translation settings for the chat that owns a given round. '
  'Used by submit-proposition Edge Function to determine translation behavior.';

-- =============================================================================
-- STEP 5: Update trigger_translate_chat() to respect translations_enabled
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
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body
  ) INTO v_request_id;

  -- Log the request ID for debugging
  RAISE LOG 'Translation requested for chat % (request_id: %, languages: %)', NEW.id, v_request_id, NEW.translation_languages;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the INSERT
  RAISE WARNING 'Translation trigger error for chat %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- =============================================================================
-- STEP 6: Update trigger_translate_proposition() to respect chat settings
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
  v_translations_enabled BOOLEAN;
  v_translation_languages TEXT[];
BEGIN
  -- Skip carried-forward propositions (they already have translations)
  IF NEW.carried_from_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Look up chat's translation settings via round → cycle → chat
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
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body
  ) INTO v_request_id;

  -- Log the request ID for debugging
  RAISE LOG 'Translation requested for proposition % (request_id: %, languages: %)', NEW.id, v_request_id, v_translation_languages;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the INSERT
  RAISE WARNING 'Translation trigger error for proposition %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
