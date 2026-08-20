-- AI game participant — pacing fix (foundation; the agent + driver + edge fn
-- follow). The AI participant ALWAYS proposes a fresh alternative and NEVER
-- affirms/votes. That breaks two assumptions in the R2+ proposing auto-advance:
--
--   1. PACE: the round advances when "everyone present responded". The AI's
--      proposition must NOT count toward that — humans decide when the round is
--      done. (Eligible count already excludes agents; we now also exclude the
--      AI's challenger from the response tally so it can't trip the gate early.)
--   2. BRANCH: "no challenger -> converge unchallenged". The AI's challenger
--      DOES count here — if it (or anyone) challenged, there's something to vote
--      on, so we open rating. With an AI always challenging, convergence happens
--      only when the group's leader out-votes the AI's alternative twice. That's
--      intended: the AI keeps the group honest.

CREATE OR REPLACE FUNCTION public.maybe_auto_advance_quick_proposing()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_round_id   BIGINT := NEW.round_id;
  v_phase      TEXT;
  v_completed  TIMESTAMPTZ;
  v_custom_id  INTEGER;
  v_chat_id    BIGINT;
  v_max_cycles INTEGER;
  v_active     INTEGER;
  v_challenges INTEGER;   -- ALL challengers (incl. AI) — branch decision
  v_human_challenges INTEGER;  -- human challengers — pace gate
  v_affirms    INTEGER;
  v_skips      INTEGER;
  v_responses  INTEGER;   -- HUMAN responses — pace gate
  v_carried_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, r.custom_id, c.chat_id, ch.max_cycles
    INTO v_phase, v_completed, v_custom_id, v_chat_id, v_max_cycles
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  -- Quick chats only; proposing; NOT round 1 (assembly = host-paced); still open.
  IF v_max_cycles IS DISTINCT FROM 1
     OR v_phase <> 'proposing'
     OR v_custom_id <= 1
     OR v_completed IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- A sibling transaction may have already resolved the round.
  IF EXISTS (SELECT 1 FROM round_winners WHERE round_id = v_round_id) THEN
    RETURN NEW;
  END IF;

  v_active := get_rating_eligible_count(v_chat_id);  -- active HUMAN participants

  -- All challengers (incl. the AI participant) — decides converge vs. rating.
  SELECT COUNT(*) INTO v_challenges
  FROM propositions
  WHERE round_id = v_round_id AND carried_from_id IS NULL AND participant_id IS NOT NULL;

  -- HUMAN responses only gate the pace (the AI always proposes, but humans
  -- decide when the round is "done" — its challenger must not trip the gate).
  SELECT COUNT(*) INTO v_human_challenges
  FROM propositions p
  JOIN participants pt ON pt.id = p.participant_id
  WHERE p.round_id = v_round_id AND p.carried_from_id IS NULL AND pt.is_agent = false;
  SELECT COUNT(*) INTO v_affirms FROM affirmations WHERE round_id = v_round_id;
  SELECT COUNT(*) INTO v_skips   FROM round_skips  WHERE round_id = v_round_id;
  v_responses := v_human_challenges + v_affirms + v_skips;

  -- Everyone present has responded, and the ≥2 floor is met (a lone host doesn't
  -- advance — mirrors the frontend NEED_RESPONSES gate).
  IF v_active < 1 OR v_responses < v_active OR v_responses < 2 THEN
    RETURN NEW;
  END IF;

  IF v_challenges = 0 THEN
    -- Nobody (not even the AI) challenged → the carried leader wins unchallenged.
    SELECT id INTO v_carried_id
    FROM propositions
    WHERE round_id = v_round_id AND carried_from_id IS NOT NULL
    ORDER BY created_at ASC
    LIMIT 1;
    IF v_carried_id IS NOT NULL THEN
      PERFORM resolve_carried_winner_for_round(v_round_id, v_carried_id);
    END IF;
  ELSE
    -- At least one challenger (human or AI) → open rating.
    UPDATE rounds
    SET phase = 'rating', phase_started_at = NOW()
    WHERE id = v_round_id AND phase = 'proposing';
  END IF;

  RETURN NEW;
END;
$function$;
