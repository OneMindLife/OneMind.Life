-- Let game AI 'player' bots vote on TOPIC rounds too (FILL only).
--
-- WHY: a solo game's topic round (pick the next question) had the bots as
-- 'proposer' (propose a topic, never vote). With a single human that left the
-- human as the ONLY voter — so "skip this pair" dead-ended the round (0 votes →
-- the matches finalize can't crown a winner). Companion to 20260625130000, which
-- now gives FILL topic-round bots the 'player' role; this drops the is_topic gate
-- from the voter trigger so those players actually get called to vote.
--
-- IDEATION topic rounds (humans >= 3) keep the single 'proposer' bot (no vote) —
-- a real group still decides its own topic. Answer rounds are unchanged.

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

  SELECT c.chat_id, ch.mode, ch.has_ai_player
    INTO v_chat_id, v_mode, v_has_ai
  FROM cycles c
  JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  -- NB: topic rounds are NO LONGER excluded — FILL gives their bots the 'player'
  -- role (see 20260625130000), and a topic round needs bot votes to resolve when
  -- the lone human skips. The player-count gate below makes IDEATION topic rounds
  -- (a single 'proposer' bot, 0 players) a no-op, so the rule still holds there.
  IF v_mode IS DISTINCT FROM 'game' OR v_has_ai IS NOT TRUE THEN
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
