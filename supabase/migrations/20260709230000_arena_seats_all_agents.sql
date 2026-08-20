-- Arena seats ALL its agents when warm (ghost-count fix), 2026-07-09.
--
-- apply_game_ai_regime chose IDEATION-vs-FILL from the active non-agent
-- participant count. That's fine for small sealed GAME chats, but broken for the
-- continuous global ARENA: anonymous visitors never go inactive, so an official
-- room accumulates thousands of "active" ghosts → the regime thinks 5+ humans are
-- present → IDEATION (1 proposer, 0 voters) → the arena can't vote and stalls.
--
-- Fix: in ARENA (non-game) mode, when the room is warm, seat EVERY agent as a
-- player (they propose AND vote) regardless of the participant count — the bots
-- are the room's constant "regulars"; real humans add on top. GAME mode keeps its
-- scale-down-with-humans logic unchanged. The cold gate (pause-when-empty) is
-- unchanged: no human in 2 min → all agents off.
--
-- Reproduced from 20260709220000_arena_pause_when_empty.sql except the warm-fill
-- branch is now split by mode.

CREATE OR REPLACE FUNCTION public.apply_game_ai_regime(p_round_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle_id  bigint;
  v_target    int;
  v_max_bots  int;
  v_chat_id   bigint;
  v_mode      text;
  v_has_ai    boolean;
  v_is_topic  boolean;
  v_last_seen timestamptz;
  v_humans    int;
  v_active    int;
  v_role      text;
  v_idx       int := 0;
  v_agent     RECORD;
BEGIN
  SELECT r.cycle_id INTO v_cycle_id FROM rounds r WHERE r.id = p_round_id;
  IF v_cycle_id IS NULL THEN RETURN; END IF;

  SELECT c.chat_id, c.is_topic, ch.mode, ch.has_ai_player, ch.last_human_seen_at
    INTO v_chat_id, v_is_topic, v_mode, v_has_ai, v_last_seen
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = v_cycle_id;

  IF v_has_ai IS NOT TRUE THEN RETURN; END IF;

  -- COLD GATE (pause-when-empty): no human seen in 2 min → park all agents off.
  IF v_last_seen IS NULL OR v_last_seen < now() - interval '2 minutes' THEN
    UPDATE participants SET agent_role = 'off'
     WHERE chat_id = v_chat_id AND is_agent = true AND status = 'active';
    RETURN;
  END IF;

  IF v_mode = 'game' THEN
    -- GAME: scale bots down as real humans arrive (small sealed games; no ghost
    -- problem). humans>=3 → IDEATION (1 proposer); else FILL up to 3 (max 2 bots).
    v_target := 3; v_max_bots := 2;
    SELECT count(*) INTO v_humans
    FROM participants
    WHERE chat_id = v_chat_id AND is_agent = false AND status = 'active';
    IF v_humans >= v_target THEN
      v_active := 1;
      v_role   := 'proposer';
    ELSE
      v_active := LEAST(GREATEST(v_target - v_humans, 1), v_max_bots);
      v_role   := CASE WHEN v_is_topic THEN 'proposer' ELSE 'player' END;
    END IF;
  ELSE
    -- ARENA (continuous, non-game): seat EVERY agent when warm. The active-
    -- participant count is meaningless here (anonymous ghosts never go inactive),
    -- so the bots are the room's constant "regulars"; real humans add on top.
    SELECT count(*) INTO v_active
    FROM participants
    WHERE chat_id = v_chat_id AND is_agent = true AND status = 'active';
    v_role := CASE WHEN v_is_topic THEN 'proposer' ELSE 'player' END;
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
