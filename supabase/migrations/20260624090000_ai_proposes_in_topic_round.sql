-- The AI plays the topic round too: it proposes its own "what to discuss next"
-- suggestion (competing in the single-round topic vote). Drops the `is_topic`
-- skip from trigger_game_ai_proposer; the edge fn now branches its prompt by
-- topic-vs-answer round.

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
  v_service_key TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  IF NEW.phase <> 'proposing' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.phase = 'proposing' THEN
    RETURN NEW;
  END IF;

  SELECT c.chat_id, ch.mode, ch.has_ai_player
    INTO v_chat_id, v_mode, v_has_ai
  FROM cycles c
  JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  -- Game + AI player; topic AND answer rounds both get the AI (the edge fn
  -- tailors its prompt to which kind of round it is).
  IF v_mode IS DISTINCT FROM 'game' OR v_has_ai IS NOT TRUE THEN
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
