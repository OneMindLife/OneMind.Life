-- Generalize the game AI seat-fill system off the game-mode gate, 2026-07-09.
--
-- Previously all three seat-fill trigger functions gated on
-- `mode = 'game' AND has_ai_player`. For the continuous global "arena" room
-- (a normal, non-game matches chat that must never sit empty) we want the same
-- AI seat-fill — bots that join, propose, and cast pairwise votes — to fire on
-- ANY chat with `has_ai_player = true`, regardless of mode. No non-game chat
-- currently sets has_ai_player, so this is purely additive/safe for existing
-- chats; game chats behave exactly as before.
--
-- What changes here (everything else is reproduced verbatim from the source
-- migrations 20260625120100 / 20260624080000 / 20260625120400):
--   * select_game_ai_regime()   — drop the `v_mode IS DISTINCT FROM 'game'`
--                                  clause; fill target/max become per-mode:
--                                  game = 3 target / 2 max (unchanged),
--                                  arena (any other mode) = 5 target / 4 max.
--   * trigger_game_ai_proposer() — drop only the mode clause (KEEP is_topic).
--   * trigger_game_ai_voter()    — drop only the mode clause (KEEP is_topic).
--
-- The triggers themselves are unchanged (they already point at these function
-- names), so we only CREATE OR REPLACE the functions.

CREATE OR REPLACE FUNCTION public.select_game_ai_regime()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_target   int;   -- TARGET_PROPOSERS (per-mode)
  v_max_bots int;   -- MAX_FILL_BOTS (per-mode)
  v_chat_id  bigint;
  v_mode     text;
  v_has_ai   boolean;
  v_is_topic boolean;
  v_humans   int;
  v_active   int;     -- how many agents are active this round
  v_role     text;    -- the role those active agents take
  v_idx      int := 0;
  v_agent    RECORD;
BEGIN
  IF NEW.phase <> 'proposing' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.phase = 'proposing' THEN RETURN NEW; END IF;

  SELECT c.chat_id, c.is_topic, ch.mode, ch.has_ai_player
    INTO v_chat_id, v_is_topic, v_mode, v_has_ai
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  IF v_has_ai IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- Per-mode fill sizing: game keeps its 3/2 profile; the continuous arena
  -- (any non-game chat) fills a larger room to 5 target / 4 max bots.
  IF v_mode = 'game' THEN
    v_target   := 3;
    v_max_bots := 2;
  ELSE
    v_target   := 5;
    v_max_bots := 4;
  END IF;

  SELECT count(*) INTO v_humans
  FROM participants
  WHERE chat_id = v_chat_id AND is_agent = false AND status = 'active';

  IF v_humans >= v_target THEN
    -- IDEATION: one ideation bot proposes, never votes.
    v_active := 1;
    v_role   := 'proposer';
  ELSE
    -- FILL: top up to TARGET_PROPOSERS distinct proposers (capped at MAX_FILL_BOTS).
    -- On ANSWER rounds those bots also vote ('player'); on TOPIC rounds (most-
    -- votes-wins, human-driven selection) they only propose ('proposer').
    v_active := LEAST(GREATEST(v_target - v_humans, 1), v_max_bots);
    v_role   := CASE WHEN v_is_topic THEN 'proposer' ELSE 'player' END;
  END IF;

  FOR v_agent IN
    SELECT id FROM participants
    WHERE chat_id = v_chat_id AND is_agent = true AND status = 'active'
    ORDER BY id
  LOOP
    UPDATE participants
       SET agent_role = CASE WHEN v_idx < v_active THEN v_role ELSE 'off' END
     WHERE id = v_agent.id;
    v_idx := v_idx + 1;
  END LOOP;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'select_game_ai_regime error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

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

  IF v_has_ai IS NOT TRUE OR v_is_topic IS TRUE THEN
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

  IF v_has_ai IS NOT TRUE OR v_is_topic IS TRUE THEN
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
