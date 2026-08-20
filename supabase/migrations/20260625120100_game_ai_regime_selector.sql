-- Step 2 of solo game-mode AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
-- The regime selector: at each game round's proposing-open, assign agent_role
-- to the chat's active agents from the live HUMAN count.
--
--   humans >= TARGET_PROPOSERS (3)  → IDEATION: AI 1 = 'proposer', rest 'off'
--   humans <  TARGET_PROPOSERS      → FILL: first n agents = 'player', rest 'off'
--                                     n = clamp(TARGET_PROPOSERS - humans, 1, MAX_FILL_BOTS=2)
--
-- Worked: 1 human → 2 players; 2 humans → 1 player + 1 off; 3+ humans →
-- 1 proposer + 1 off. "Enough humans to vote" == humans alone reach the engine's
-- 3-distinct-proposer minimum, so AI stops voting at 3.
--
-- Runs at proposing-open only; the assigned roles persist through the round's
-- rating phase, so game-ai-voter (rating-open) reads the role set here. The
-- proposer/voter edge fns run async (pg_net) AFTER this trigger's transaction
-- commits, so they always observe the freshly-assigned roles regardless of
-- trigger firing order.

CREATE OR REPLACE FUNCTION public.select_game_ai_regime()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_target   CONSTANT int := 3;   -- TARGET_PROPOSERS
  v_max_bots CONSTANT int := 2;   -- MAX_FILL_BOTS
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

  IF v_mode IS DISTINCT FROM 'game' OR v_has_ai IS NOT TRUE THEN
    RETURN NEW;
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

DROP TRIGGER IF EXISTS select_game_ai_regime_trg ON public.rounds;
CREATE TRIGGER select_game_ai_regime_trg
AFTER INSERT OR UPDATE OF phase ON public.rounds
FOR EACH ROW
EXECUTE FUNCTION public.select_game_ai_regime();
