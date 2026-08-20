-- Step 4c of solo game-mode AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
-- Drives the game AI voters: when a game ANSWER round enters the RATING phase
-- and at least one active 'player' agent exists (FILL regime), call the
-- game-ai-voter edge function (async, pg_net) so the bots cast their votes.
--
-- Mirrors trigger_game_ai_proposer. Gated on game mode + has_ai_player + a
-- non-topic cycle + an active 'player' agent (so IDEATION rounds, where no bot
-- votes, make no edge call).

CREATE OR REPLACE FUNCTION public.trigger_game_ai_voter()
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
  v_player_cnt  INT;
  v_service_key TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  IF NEW.phase <> 'rating' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.phase = 'rating' THEN
    RETURN NEW;  -- already rating; not a fresh entry
  END IF;

  SELECT c.chat_id, c.is_topic, ch.mode, ch.has_ai_player
    INTO v_chat_id, v_is_topic, v_mode, v_has_ai
  FROM cycles c
  JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  IF v_mode IS DISTINCT FROM 'game' OR v_has_ai IS NOT TRUE OR v_is_topic IS TRUE THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_player_cnt
  FROM participants
  WHERE chat_id = v_chat_id AND is_agent = true AND status = 'active' AND agent_role = 'player';

  IF v_player_cnt = 0 THEN
    RETURN NEW;  -- IDEATION (or no FILL bots): nobody to vote.
  END IF;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'game-ai-voter skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('game-ai-voter');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('round_id', NEW.id)
  ) INTO v_request_id;

  RAISE LOG 'game-ai-voter called for round % chat % (% players, request_id %)',
    NEW.id, v_chat_id, v_player_cnt, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'game-ai-voter trigger error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_game_ai_voter_trg ON public.rounds;
CREATE TRIGGER trigger_game_ai_voter_trg
AFTER INSERT OR UPDATE OF phase ON public.rounds
FOR EACH ROW
EXECUTE FUNCTION public.trigger_game_ai_voter();
