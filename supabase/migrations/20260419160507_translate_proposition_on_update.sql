-- Re-translate propositions when their content is edited.
--
-- INSERTs already trigger `translate_proposition_on_insert`, which populates
-- `translations` for every configured language. If content later changes
-- (direct DB edit, future in-app edit feature, etc.) the stale rows linger
-- and `get_propositions_with_translations` keeps returning the old text —
-- users see the original content even after it's been rewritten.
--
-- Mirrors the existing `trigger_translate_chat_on_update` pattern:
--   * only fires when `content` actually changed (IS DISTINCT FROM)
--   * deletes stale translations for this proposition's content
--   * re-requests translation async via pg_net
--   * skips carried-forward props (their translations are indexed by the
--     ORIGINAL proposition's id, not this row's — a no-op delete, and the
--     original is the source of truth)
--   * exception-safe: logs on failure but never blocks the UPDATE

CREATE OR REPLACE FUNCTION public.trigger_translate_proposition_on_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
  v_translations_enabled BOOLEAN;
  v_translation_languages TEXT[];
BEGIN
  IF OLD.content IS NOT DISTINCT FROM NEW.content THEN
    RETURN NEW;
  END IF;

  DELETE FROM public.translations
  WHERE proposition_id = NEW.id
    AND field_name = 'content';

  -- Carried-forward propositions share translations with their original
  -- via carried_from_id — nothing to re-translate at this row's level.
  IF NEW.carried_from_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.content IS NULL OR NEW.content = '' THEN
    RETURN NEW;
  END IF;

  SELECT c.translations_enabled, c.translation_languages
  INTO v_translations_enabled, v_translation_languages
  FROM public.rounds r
  INNER JOIN public.cycles cy ON cy.id = r.cycle_id
  INNER JOIN public.chats c ON c.id = cy.chat_id
  WHERE r.id = NEW.round_id;

  IF NOT COALESCE(v_translations_enabled, FALSE) THEN
    RAISE LOG 'Translation skipped for proposition % update: chat translations_enabled = false', NEW.id;
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'Translation skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('translate');

  v_body := jsonb_build_object(
    'proposition_id', NEW.id,
    'text', NEW.content,
    'entity_type', 'proposition',
    'field_name', 'content',
    'languages', to_jsonb(v_translation_languages)
  );

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body,
    timeout_milliseconds := 60000
  ) INTO v_request_id;

  RAISE LOG 'Translation requested for proposition % update (request_id: %, languages: %)',
    NEW.id, v_request_id, v_translation_languages;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Translation trigger error for proposition % on update: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS translate_proposition_on_update ON public.propositions;

CREATE TRIGGER translate_proposition_on_update
  AFTER UPDATE ON public.propositions
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_translate_proposition_on_update();
