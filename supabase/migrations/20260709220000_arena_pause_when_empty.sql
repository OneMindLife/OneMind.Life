-- Pause-when-empty for the continuous AI arena, 2026-07-09.
--
-- The seat-fill agents (proposer / player bots) in a has_ai_player arena must
-- STOP running when no human is present, and RESUME when a human returns — so
-- an idle global room doesn't burn 24/7 LLM spend.
--
-- Mechanism:
--   * `chats.last_human_seen_at` is a heartbeat written by every present human
--     (client calls touch_arena_presence() on mount + every ~15s while visible).
--   * The seat-fill regime is refactored into a callable helper
--     `apply_game_ai_regime(p_round_id)` shared by the phase-trigger wrapper AND
--     the wake RPC. It gains a COLD GATE: if the room hasn't seen a human within
--     ARENA_COLD_THRESHOLD (2 minutes) it switches every agent OFF and does not
--     fill.
--   * The proposer/voter fire triggers gain the same cold check so they never
--     invoke the edge fn in an empty room.
--   * `touch_arena_presence(p_chat_id)` is the wake path: it stamps the
--     heartbeat and, if the current proposing round was frozen cold, re-runs the
--     (now-warm) regime and kicks the proposer edge fn.
--
-- ARENA_COLD_THRESHOLD is 2 minutes throughout (client heartbeat is ~15s, so a
-- present human refreshes it ~8x per window). Tune both together.
--
-- The regime/proposer/voter bodies below are reproduced VERBATIM from
-- 20260709200000_generalize_seatfill_off_game_mode.sql except for the stated
-- cold-check additions.

-- 1. Heartbeat column.
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS last_human_seen_at timestamptz;

COMMENT ON COLUMN public.chats.last_human_seen_at IS
  'Heartbeat of the last time a human was present in a has_ai_player arena; drives pause-when-empty (see touch_arena_presence + apply_game_ai_regime cold gate).';

-- 2. Callable regime helper (shared by the phase trigger + the wake RPC).
--    Body = the current select_game_ai_regime() logic keyed off p_round_id,
--    plus the cold gate.
CREATE OR REPLACE FUNCTION public.apply_game_ai_regime(p_round_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle_id  bigint;
  v_target    int;   -- TARGET_PROPOSERS (per-mode)
  v_max_bots  int;   -- MAX_FILL_BOTS (per-mode)
  v_chat_id   bigint;
  v_mode      text;
  v_has_ai    boolean;
  v_is_topic  boolean;
  v_last_seen timestamptz;
  v_humans    int;
  v_active    int;    -- how many agents are active this round
  v_role      text;   -- the role those active agents take
  v_idx       int := 0;
  v_agent     RECORD;
BEGIN
  SELECT r.cycle_id INTO v_cycle_id FROM rounds r WHERE r.id = p_round_id;
  IF v_cycle_id IS NULL THEN RETURN; END IF;

  SELECT c.chat_id, c.is_topic, ch.mode, ch.has_ai_player, ch.last_human_seen_at
    INTO v_chat_id, v_is_topic, v_mode, v_has_ai, v_last_seen
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = v_cycle_id;

  IF v_has_ai IS NOT TRUE THEN
    RETURN;
  END IF;

  -- COLD GATE (pause-when-empty): ARENA_COLD_THRESHOLD = 2 minutes. If no human
  -- has been seen recently, park EVERY agent 'off' and don't fill — bots must
  -- not run in an empty room. touch_arena_presence() re-warms + re-fills.
  IF v_last_seen IS NULL OR v_last_seen < now() - interval '2 minutes' THEN
    UPDATE participants
       SET agent_role = 'off'
     WHERE chat_id = v_chat_id AND is_agent = true AND status = 'active';
    RETURN;
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

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'apply_game_ai_regime error for round %: %', p_round_id, SQLERRM;
END;
$function$;

-- 2b. select_game_ai_regime() becomes a THIN wrapper: phase guards, then delegate.
CREATE OR REPLACE FUNCTION public.select_game_ai_regime()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.phase <> 'proposing' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.phase = 'proposing' THEN RETURN NEW; END IF;

  PERFORM public.apply_game_ai_regime(NEW.id);
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'select_game_ai_regime error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;
-- Trigger select_game_ai_regime_trg is unchanged (already points at this function).

-- 3. Wake RPC — client heartbeat + cold-room revival.
CREATE OR REPLACE FUNCTION public.touch_arena_presence(p_chat_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_updated     int;
  v_round_id    bigint;
  v_active_bots int;
  v_service_key text;
  v_url         text;
  v_request_id  bigint;
BEGIN
  -- Heartbeat: mark a human present. Only arenas (has_ai_player) track this.
  UPDATE chats
     SET last_human_seen_at = now()
   WHERE id = p_chat_id AND has_ai_player = true;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN;  -- not an arena
  END IF;

  -- The arena's latest round currently in proposing.
  SELECT r.id INTO v_round_id
  FROM rounds r JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = p_chat_id AND r.phase = 'proposing'
  ORDER BY r.id DESC
  LIMIT 1;

  IF v_round_id IS NULL THEN
    RETURN;  -- no live proposing round to wake
  END IF;

  -- Was the room frozen cold? (no active proposer/player agents for this chat)
  SELECT count(*) INTO v_active_bots
  FROM participants
  WHERE chat_id = p_chat_id AND is_agent = true AND status = 'active'
    AND agent_role IN ('proposer', 'player');

  IF v_active_bots > 0 THEN
    RETURN;  -- already warm — agents already running this round
  END IF;

  -- Cold → warm: heartbeat above just refreshed last_human_seen_at, so the
  -- regime will now fill (not park) the agents.
  PERFORM public.apply_game_ai_regime(v_round_id);

  -- Did the regime activate anyone? (it may not, e.g. plenty of humans already.)
  SELECT count(*) INTO v_active_bots
  FROM participants
  WHERE chat_id = p_chat_id AND is_agent = true AND status = 'active'
    AND agent_role IN ('proposer', 'player');

  IF v_active_bots = 0 THEN
    RETURN;  -- nothing to fire
  END IF;

  -- Kick the proposer edge fn for the revived round (same pattern as
  -- trigger_game_ai_proposer).
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'touch_arena_presence: game-ai-proposer skipped: edge_function_service_key not configured in vault';
    RETURN;
  END IF;

  v_url := get_edge_function_url('game-ai-proposer');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('round_id', v_round_id)
  ) INTO v_request_id;

  RAISE LOG 'touch_arena_presence woke chat % round % (request_id %)',
    p_chat_id, v_round_id, v_request_id;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'touch_arena_presence error for chat %: %', p_chat_id, SQLERRM;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.touch_arena_presence(bigint) TO anon, authenticated;

-- 4. Belt-and-suspenders: the proposer/voter fire triggers also honor the cold
--    gate, so they never invoke the edge fn in an empty room. Reproduced
--    verbatim from 20260709200000 except the cold-check additions (declaration
--    v_last_seen, the last_human_seen_at column in the SELECT ... INTO, and the
--    cold-check IF).
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
  v_last_seen   TIMESTAMPTZ;   -- COLD-CHECK ADDITION
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

  SELECT c.chat_id, c.is_topic, ch.mode, ch.has_ai_player, ch.last_human_seen_at
    INTO v_chat_id, v_is_topic, v_mode, v_has_ai, v_last_seen
  FROM cycles c
  JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  IF v_has_ai IS NOT TRUE OR v_is_topic IS TRUE THEN
    RETURN NEW;
  END IF;

  -- COLD-CHECK ADDITION: pause-when-empty (ARENA_COLD_THRESHOLD = 2 minutes).
  IF v_last_seen IS NULL OR v_last_seen < now() - interval '2 minutes' THEN
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
  v_last_seen   TIMESTAMPTZ;   -- COLD-CHECK ADDITION
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

  SELECT c.chat_id, c.is_topic, ch.mode, ch.has_ai_player, ch.last_human_seen_at
    INTO v_chat_id, v_is_topic, v_mode, v_has_ai, v_last_seen
  FROM cycles c
  JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  IF v_has_ai IS NOT TRUE OR v_is_topic IS TRUE THEN
    RETURN NEW;
  END IF;

  -- COLD-CHECK ADDITION: pause-when-empty (ARENA_COLD_THRESHOLD = 2 minutes).
  IF v_last_seen IS NULL OR v_last_seen < now() - interval '2 minutes' THEN
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
