-- notify_telegram_round: also fire a BROADCAST event for the official web room
-- (1269) so the bot posts each phase transition to the OneMind channel
-- (@onemind_life) — the retention loop (growth D68). Does NOT overload
-- chats.telegram_chat_id (that would disable web-push for the room); instead
-- sends {broadcast:true} and the bot posts to its BROADCAST_CHANNEL_ID.
CREATE OR REPLACE FUNCTION public.notify_telegram_round()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tg_chat_id   BIGINT;
  v_is_official  BOOLEAN;
  v_event        TEXT;
  v_secret       TEXT;
  v_url          TEXT;
  v_request_id   BIGINT;
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

  SELECT ch.telegram_chat_id, ch.is_official
  INTO v_tg_chat_id, v_is_official
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'telegram_internal_secret';

  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_telegram_round skipped: telegram_internal_secret not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('telegram-bot');

  -- Broadcast to the OneMind channel for the official web room (retention loop).
  IF v_is_official THEN
    SELECT net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_secret
      ),
      body := jsonb_build_object('tgevent', v_event, 'round_id', NEW.id, 'broadcast', true)
    ) INTO v_request_id;
    RAISE LOG 'notify_telegram_round broadcast % for round % (request_id %)',
      v_event, NEW.id, v_request_id;
  END IF;

  -- Bound Telegram group (per-group Lens/House posts).
  IF v_tg_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

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
