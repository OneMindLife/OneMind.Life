-- Drives the game AI player: when a game ANSWER round enters proposing, call the
-- game-ai-proposer edge function (async, via pg_net) so the AI submits its
-- alternative. Separate from the dormant Flutter `trigger_ai_proposer_on_proposing`
-- path (which gates on enable_ai_participant and game chats never set) — no overlap.
--
-- Gated on: game mode + chats.has_ai_player + NOT a topic cycle (the AI plays the
-- answer, not the topic selection).

CREATE OR REPLACE FUNCTION public.trigger_game_ai_proposer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id     BIGINT;
  v_mode        TEXT;
  v_has_ai      BOOLEAN;
  v_is_topic    BOOLEAN;
  v_service_key TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  IF NEW.phase <> 'proposing' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.phase = 'proposing' THEN
    RETURN NEW;  -- already in proposing; not a fresh entry
  END IF;

  SELECT c.chat_id, c.is_topic, ch.mode, ch.has_ai_player
    INTO v_chat_id, v_is_topic, v_mode, v_has_ai
  FROM cycles c
  JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  IF v_mode IS DISTINCT FROM 'game' OR v_has_ai IS NOT TRUE OR v_is_topic IS TRUE THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'game-ai-proposer skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('game-ai-proposer');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('round_id', NEW.id)
  ) INTO v_request_id;

  RAISE LOG 'game-ai-proposer called for round % chat % (request_id %)',
    NEW.id, v_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'game-ai-proposer trigger error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_game_ai_proposer_trg ON public.rounds;
CREATE TRIGGER trigger_game_ai_proposer_trg
AFTER INSERT OR UPDATE OF phase ON public.rounds
FOR EACH ROW
EXECUTE FUNCTION public.trigger_game_ai_proposer();
