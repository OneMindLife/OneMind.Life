-- Dedicated internal secret shared between the notify_telegram_round trigger and
-- the telegram-bot edge fn (which is --no-verify-jwt, so the platform doesn't
-- verify the bearer). The service-role JWT the other triggers pass isn't byte-
-- identical to the bot's SUPABASE_SERVICE_ROLE_KEY env, so an exact-match check
-- 403'd. This secret lives only in vault; the bot verifies via
-- verify_telegram_internal (the secret never leaves the DB).

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'telegram_internal_secret') THEN
    PERFORM vault.create_secret(encode(gen_random_bytes(32), 'hex'), 'telegram_internal_secret',
      'Shared bearer for notify_telegram_round -> telegram-bot tgevent calls');
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.verify_telegram_internal(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'vault', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM vault.decrypted_secrets
    WHERE name = 'telegram_internal_secret' AND decrypted_secret = p_token
  );
$$;

REVOKE ALL ON FUNCTION public.verify_telegram_internal(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_telegram_internal(TEXT) TO service_role;

-- Point the notify_telegram_round trigger at the dedicated secret.
CREATE OR REPLACE FUNCTION public.notify_telegram_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tg_chat_id  BIGINT;
  v_event       TEXT;
  v_secret      TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  IF NEW.winning_proposition_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.winning_proposition_id IS DISTINCT FROM NEW.winning_proposition_id) THEN
    v_event := 'winner';
  ELSIF NEW.phase = 'rating'
     AND (TG_OP = 'INSERT' OR OLD.phase IS DISTINCT FROM 'rating') THEN
    v_event := 'vote_open';
  ELSIF NEW.phase = 'proposing'
     AND (TG_OP = 'INSERT' OR OLD.phase IS DISTINCT FROM 'proposing') THEN
    v_event := 'round_open';
  ELSE
    RETURN NEW;
  END IF;

  SELECT ch.telegram_chat_id INTO v_tg_chat_id
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  IF v_tg_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'telegram_internal_secret';

  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_telegram_round skipped: telegram_internal_secret not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('telegram-bot');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object('tgevent', v_event, 'round_id', NEW.id, 'telegram_chat_id', v_tg_chat_id)
  ) INTO v_request_id;

  RAISE LOG 'notify_telegram_round % for round % chat % (request_id %)',
    v_event, NEW.id, v_tg_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_telegram_round error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;
