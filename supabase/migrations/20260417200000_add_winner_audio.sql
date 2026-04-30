-- Add audio URL columns for automatic ElevenLabs TTS on official chat content.
--
-- Round winner audio: populated by trigger → generate-winner-audio edge function
-- Initial message audio: populated by trigger on chat creation/update
--
-- Both apply only to chats where is_official = true.

ALTER TABLE public.rounds ADD COLUMN IF NOT EXISTS audio_url TEXT;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS initial_message_audio_url TEXT;

-- =============================================================================
-- Trigger: generate audio when a round's winning_proposition_id is first set
-- =============================================================================

CREATE OR REPLACE FUNCTION trigger_generate_round_audio()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_url TEXT;
  v_service_key TEXT;
  v_is_official BOOLEAN;
BEGIN
  -- Only fire on NULL → NOT NULL transition
  IF NEW.winning_proposition_id IS NULL THEN RETURN NEW; END IF;
  IF OLD.winning_proposition_id IS NOT NULL THEN RETURN NEW; END IF;

  -- Official chats only
  SELECT ch.is_official INTO v_is_official
  FROM cycles cy
  JOIN chats ch ON ch.id = cy.chat_id
  WHERE cy.id = NEW.cycle_id;

  IF NOT COALESCE(v_is_official, false) THEN RETURN NEW; END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  v_url := COALESCE(v_url, 'https://ccyuxrtrklgpkzcryzpj.supabase.co') || '/functions/v1/generate-winner-audio';

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'edge_function_service_key';

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('kind', 'round', 'id', NEW.id),
    timeout_milliseconds := 60000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_round_audio trigger error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS generate_round_audio_trigger ON rounds;
CREATE TRIGGER generate_round_audio_trigger
AFTER UPDATE OF winning_proposition_id ON rounds
FOR EACH ROW
EXECUTE FUNCTION trigger_generate_round_audio();

-- =============================================================================
-- Trigger: generate audio for chat initial_message when official
-- =============================================================================

CREATE OR REPLACE FUNCTION trigger_generate_chat_initial_audio()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_url TEXT;
  v_service_key TEXT;
BEGIN
  IF NOT COALESCE(NEW.is_official, false) THEN RETURN NEW; END IF;
  IF NEW.initial_message IS NULL OR NEW.initial_message = '' THEN RETURN NEW; END IF;
  IF NEW.initial_message_audio_url IS NOT NULL THEN RETURN NEW; END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  v_url := COALESCE(v_url, 'https://ccyuxrtrklgpkzcryzpj.supabase.co') || '/functions/v1/generate-winner-audio';

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'edge_function_service_key';

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('kind', 'chat_initial', 'id', NEW.id),
    timeout_milliseconds := 60000
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_chat_initial_audio trigger error for chat %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS generate_chat_initial_audio_trigger ON chats;
CREATE TRIGGER generate_chat_initial_audio_trigger
AFTER INSERT OR UPDATE OF is_official, initial_message ON chats
FOR EACH ROW
EXECUTE FUNCTION trigger_generate_chat_initial_audio();
