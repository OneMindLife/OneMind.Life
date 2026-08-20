-- Solo game AI seat-fill — make the human count phantom-resistant.
--
-- PROBLEM: the wedge auto-join (ensureParticipant on chat mount) can create a
-- second anonymous session that joins as a never-acting "phantom" participant
-- (~11% of games observed 2026-06-25). The regime selector counted it as a real
-- human, so a SOLO host got 1 fill bot instead of 2 (2 "humans" → top up to 3).
--
-- FIX: when ANY human has already engaged in the chat (proposed a fresh idea,
-- cast a pairwise vote, or affirmed), count only humans who are the HOST or have
-- themselves engaged — dropping phantoms that joined but never acted. Before any
-- human has engaged (true first-touch: game 1, round 1) we can't tell a phantom
-- from a not-yet-acted real human, so we count everyone — which keeps genuine
-- multi-human games from being wrongly over-filled with bots at the very start.
-- (A solo+phantom game is therefore only mis-filled on its very first round; from
-- round 2 / the topic round onward it self-corrects to the right bot count.)

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
  v_any_eng  boolean; -- has any human engaged anywhere in the chat yet?
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

  -- Has ANY human engaged in this chat yet (fresh idea, vote, or affirm)?
  SELECT EXISTS (
    SELECT 1 FROM propositions p
      JOIN rounds r  ON r.id = p.round_id
      JOIN cycles cy ON cy.id = r.cycle_id
      JOIN participants pp ON pp.id = p.participant_id
      WHERE cy.chat_id = v_chat_id AND pp.is_agent = false AND p.carried_from_id IS NULL
    UNION ALL
    SELECT 1 FROM pairwise_comparisons pc
      JOIN rounds r  ON r.id = pc.round_id
      JOIN cycles cy ON cy.id = r.cycle_id
      JOIN participants pp ON pp.id = pc.participant_id
      WHERE cy.chat_id = v_chat_id AND pp.is_agent = false
    UNION ALL
    SELECT 1 FROM affirmations a
      JOIN participants pp ON pp.id = a.participant_id
      WHERE a.chat_id = v_chat_id AND pp.is_agent = false
  ) INTO v_any_eng;

  IF v_any_eng THEN
    -- Some human has acted → trust engagement: count the host + humans who have
    -- themselves engaged. Never-acting phantoms drop out.
    SELECT count(*) INTO v_humans
    FROM participants p
    WHERE p.chat_id = v_chat_id AND p.is_agent = false AND p.status = 'active'
      AND (
        p.is_host = true
        OR EXISTS (SELECT 1 FROM propositions x
             JOIN rounds r ON r.id = x.round_id JOIN cycles cy ON cy.id = r.cycle_id
             WHERE cy.chat_id = v_chat_id AND x.participant_id = p.id AND x.carried_from_id IS NULL)
        OR EXISTS (SELECT 1 FROM pairwise_comparisons x
             JOIN rounds r ON r.id = x.round_id JOIN cycles cy ON cy.id = r.cycle_id
             WHERE cy.chat_id = v_chat_id AND x.participant_id = p.id)
        OR EXISTS (SELECT 1 FROM affirmations x WHERE x.chat_id = v_chat_id AND x.participant_id = p.id)
      );
  ELSE
    -- True first-touch: nobody has acted yet, can't spot phantoms → count all.
    SELECT count(*) INTO v_humans
    FROM participants p
    WHERE p.chat_id = v_chat_id AND p.is_agent = false AND p.status = 'active';
  END IF;

  IF v_humans >= v_target THEN
    v_active := 1;
    v_role   := 'proposer';
  ELSE
    -- FILL: bots are 'player' (propose AND vote) on BOTH answer and topic rounds.
    -- Topic rounds need bot votes too: a solo human is otherwise the only voter,
    -- so skipping the pair leaves 0 votes and the topic round can't resolve.
    v_active := LEAST(GREATEST(v_target - v_humans, 1), v_max_bots);
    v_role   := 'player';
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
