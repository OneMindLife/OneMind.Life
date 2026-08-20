-- Push notifications for round lifecycle — the DB-trigger twin of
-- notify_telegram_round. Until now pushes fired ONLY from process-timers
-- (timer expiry), so threshold/participation-driven advances — the common
-- case in an active group — and winners were silent. This trigger fires on
-- the same transitions no matter which driver flipped the phase, and posts
-- to the push-events edge fn which fans out via FCM.
--
-- Skips: preview chats (tutorial junk), arena chats (120s phases would spam
-- pointless invocations; wedge users have no FCM tokens), telegram-bound
-- chats (Telegram itself is their notification surface).

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'push_internal_secret') THEN
    PERFORM vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'push_internal_secret',
      'Shared bearer for notify_push_round -> push-events edge fn calls');
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.verify_push_internal(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'vault', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM vault.decrypted_secrets
    WHERE name = 'push_internal_secret' AND decrypted_secret = p_token
  );
$$;

REVOKE ALL ON FUNCTION public.verify_push_internal(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_push_internal(TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.notify_push_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id     BIGINT;
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

  SELECT ch.id INTO v_chat_id
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id
    AND ch.is_preview = false
    AND ch.is_arena = false
    AND ch.telegram_chat_id IS NULL;

  IF v_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'push_internal_secret';

  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_push_round skipped: push_internal_secret not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('push-events');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object('pushevent', v_event, 'round_id', NEW.id, 'chat_id', v_chat_id)
  ) INTO v_request_id;

  RAISE LOG 'notify_push_round % for round % chat % (request_id %)',
    v_event, NEW.id, v_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_push_round error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_push_round_trg ON public.rounds;
CREATE TRIGGER notify_push_round_trg
  AFTER INSERT OR UPDATE ON public.rounds
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_round();

COMMENT ON FUNCTION public.notify_push_round() IS
  'Posts round lifecycle events (round_open/vote_open/winner) to the push-events edge fn for FCM fan-out. Fires no matter which driver flipped the phase (thresholds, bot, process-timers). Skips preview/arena/telegram chats.';
