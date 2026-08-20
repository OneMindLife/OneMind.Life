-- Always-running Telegram group rooms.
--
-- The group room is never idle: it's always in proposing or rating, cycling
-- forever (propose anything -> vote -> a winning message posts into the thread
-- -> fresh proposing round). No /ask, no host — the topic emerges democratically
-- from what the group proposes and votes for.
--
-- Advancing is driven two ways, both of which just mutate rounds:
--   1. the telegram-bot edge fn, immediately, when everyone in the group has
--      acted (member-count driven), and
--   2. process-timers, as the 12h backstop (rounds carry a 12h phase_ends_at).
--
-- POSTING to the group must happen no matter which driver flipped the phase, so
-- it lives HERE: this trigger calls the telegram-bot edge fn (async, via pg_net,
-- mirroring trigger_game_ai_proposer) whenever a bound round opens proposing,
-- opens voting, or gets a winner. The bot then posts the right message/button.

CREATE OR REPLACE FUNCTION public.notify_telegram_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tg_chat_id  BIGINT;
  v_event       TEXT;
  v_service_key TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  -- Which transition is this? (at most one event per statement)
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

  -- Only bound (Telegram) rooms; cheap short-circuit for every other chat.
  SELECT ch.telegram_chat_id INTO v_tg_chat_id
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  IF v_tg_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'notify_telegram_round skipped: edge_function_service_key not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('telegram-bot');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      'tgevent', v_event,
      'round_id', NEW.id,
      'telegram_chat_id', v_tg_chat_id
    )
  ) INTO v_request_id;

  RAISE LOG 'notify_telegram_round % for round % chat % (request_id %)',
    v_event, NEW.id, v_tg_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_telegram_round error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_telegram_round_trg ON public.rounds;
CREATE TRIGGER notify_telegram_round_trg
AFTER INSERT OR UPDATE ON public.rounds
FOR EACH ROW
EXECUTE FUNCTION public.notify_telegram_round();

COMMENT ON FUNCTION public.notify_telegram_round IS
'Posts to a bound Telegram group when a round opens proposing, opens voting, or
gets a winner. Async via pg_net -> telegram-bot edge fn (tgevent). Fires no matter
what drove the phase change (the bot on everyone-acted, or process-timers at 12h).';
