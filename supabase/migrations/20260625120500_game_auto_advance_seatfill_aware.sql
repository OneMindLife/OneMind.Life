-- Step 4d of solo game-mode AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
-- Make the quick-chat backend auto-advance triggers seat-fill aware.
--
-- THE BUG: matches_preview_maybe_finalize (rating) and
-- maybe_auto_advance_quick_proposing (R2+ proposing) both use
-- get_rating_eligible_count as the denominator — HUMANS ONLY (agents excluded
-- while rating_agent_count = 0). But seat-fill bots now ACT: a 'player' bot
-- votes, and 'player'/'proposer' bots submit challengers. Their actions land in
-- the NUMERATOR (done / responses) while the DENOMINATOR ignores them, so a solo
-- game advances the instant the bots act — before the human ever votes or
-- proposes. Both sides must count bots consistently.
--
-- FIX:
--   * RATING finalize — for a game round with an active 'player' agent, take
--     done/eligible from get_matches_rating_progress (which counts the 'player'
--     bots AND the host, and waits for all of them). Non-game chats keep the
--     EXACT 20260624100000 behavior, including the stranded-rater v_pending guard.
--   * R2+ PROPOSING advance — add the active proposing agents (role 'proposer'
--     or 'player') to the "everyone present" count, so the round waits for the
--     bots' (async) challengers too. game-ai-proposer writes a round_skip for an
--     agent whose generation fails, so a dead bot counts as "responded".
--
-- NB: this rebases matches_preview_maybe_finalize onto its LATEST committed
-- definition (20260624100000, the stranded-rater fix) — NOT the older
-- 20260624030000 — so the v_pending guard is preserved.

-- ── 1. RATING auto-finalize (20260624100000 base + game/player branch) ──
CREATE OR REPLACE FUNCTION public.matches_preview_maybe_finalize()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_round_id    BIGINT := NEW.round_id;
  v_phase       TEXT;
  v_completed   TIMESTAMPTZ;
  v_chat_id     BIGINT;
  v_rating_mode TEXT;
  v_max_cycles  INTEGER;
  v_is_preview  BOOLEAN;
  v_rating_min  INTEGER;
  v_agent_cnt   INTEGER;
  v_mode        TEXT;
  v_has_player  BOOLEAN;
  v_done        INTEGER;
  v_eligible    INTEGER;
  v_pending     INTEGER;
  v_votes       INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, c.chat_id, ch.rating_mode, ch.max_cycles,
         ch.is_preview, ch.rating_minimum, ch.rating_agent_count, ch.mode
    INTO v_phase, v_completed, v_chat_id, v_rating_mode, v_max_cycles,
         v_is_preview, v_rating_min, v_agent_cnt, v_mode
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  IF v_phase <> 'rating'
     OR v_completed IS NOT NULL
     OR v_rating_mode <> 'matches'
     OR v_max_cycles IS DISTINCT FROM 1 THEN
    RETURN NEW;
  END IF;

  -- done = distinct raters across all three completion signals.
  SELECT COUNT(*) INTO v_done FROM (
    SELECT participant_id FROM rating_completions WHERE round_id = v_round_id AND participant_id IS NOT NULL
    UNION
    SELECT gr.participant_id FROM grid_rankings gr
      JOIN propositions p ON p.id = gr.proposition_id
      WHERE p.round_id = v_round_id
    UNION
    SELECT participant_id FROM rating_skips WHERE round_id = v_round_id
  ) u;

  v_eligible := get_rating_eligible_count(v_chat_id);

  -- pending = active rater-eligible participants who CAN rate this round (enough
  -- props they didn't author to form a comparison) but haven't acted yet.
  SELECT COUNT(*) INTO v_pending
  FROM participants p
  WHERE p.chat_id = v_chat_id
    AND p.status = 'active'
    AND (p.is_agent = false OR v_agent_cnt > 0)
    AND (
      SELECT COUNT(*) FROM propositions pr
      WHERE pr.round_id = v_round_id
        AND (pr.participant_id IS NULL OR pr.participant_id <> p.id)
    ) >= COALESCE(v_rating_min, 2)
    AND NOT EXISTS (SELECT 1 FROM rating_completions rc WHERE rc.round_id = v_round_id AND rc.participant_id = p.id)
    AND NOT EXISTS (SELECT 1 FROM rating_skips rs WHERE rs.round_id = v_round_id AND rs.participant_id = p.id)
    AND NOT EXISTS (
      SELECT 1 FROM grid_rankings gr
      JOIN propositions gp ON gp.id = gr.proposition_id
      WHERE gp.round_id = v_round_id AND gr.participant_id = p.id
    );

  -- Seat-fill override: for a game round with an active 'player' agent, take
  -- done/eligible from the player+host-aware progress fn so the round waits for
  -- the async bots AND the host (v_pending still guards stranded humans).
  SELECT EXISTS (
    SELECT 1 FROM participants p
    WHERE p.chat_id = v_chat_id AND p.is_agent = true
      AND p.status = 'active' AND p.agent_role = 'player'
  ) INTO v_has_player;

  IF v_mode = 'game' AND v_has_player THEN
    SELECT done, eligible INTO v_done, v_eligible
    FROM get_matches_rating_progress(v_round_id, v_chat_id);
  END IF;

  SELECT COUNT(*) INTO v_votes
  FROM pairwise_comparisons
  WHERE round_id = v_round_id AND COALESCE(is_skip, false) = false;

  -- Finalize when everyone's accounted for (done >= eligible) OR no ABLE voter is
  -- still pending (stranded authors don't block) — and, for a real multi-user
  -- round, at least one real vote was cast.
  IF v_eligible > 0
     AND (v_done >= v_eligible OR v_pending = 0)
     AND (v_is_preview IS TRUE OR v_votes >= 1) THEN
    PERFORM complete_round_with_winner(v_round_id);
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 2. R2+ PROPOSING auto-advance (20260624030000 base + proposing-agent count) ──
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
  v_agents     INTEGER;
  v_challenges INTEGER;
  v_affirms    INTEGER;
  v_skips      INTEGER;
  v_responses  INTEGER;
  v_carried_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, r.custom_id, c.chat_id, ch.max_cycles
    INTO v_phase, v_completed, v_custom_id, v_chat_id, v_max_cycles
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  IF v_max_cycles IS DISTINCT FROM 1
     OR v_phase <> 'proposing'
     OR v_custom_id <= 1
     OR v_completed IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (SELECT 1 FROM round_winners WHERE round_id = v_round_id) THEN
    RETURN NEW;
  END IF;

  v_active := get_rating_eligible_count(v_chat_id);  -- active humans

  -- Seat-fill: active proposing agents (role 'proposer' or 'player') also submit
  -- a challenger this round (or a round_skip on generation failure), so they
  -- belong in the "everyone present" denominator. Non-game chats have none.
  SELECT COUNT(*) INTO v_agents
  FROM participants p
  WHERE p.chat_id = v_chat_id AND p.is_agent = true
    AND p.status = 'active' AND p.agent_role IN ('proposer', 'player');
  v_active := v_active + v_agents;

  -- A "response" = a new challenger idea, a keep (affirmation), or a skip. Bot
  -- challengers and bot round_skips are already counted here (they are real rows).
  SELECT COUNT(*) INTO v_challenges
  FROM propositions
  WHERE round_id = v_round_id AND carried_from_id IS NULL AND participant_id IS NOT NULL;
  SELECT COUNT(*) INTO v_affirms FROM affirmations WHERE round_id = v_round_id;
  SELECT COUNT(*) INTO v_skips   FROM round_skips  WHERE round_id = v_round_id;
  v_responses := v_challenges + v_affirms + v_skips;

  IF v_active < 1 OR v_responses < v_active OR v_responses < 2 THEN
    RETURN NEW;
  END IF;

  IF v_challenges = 0 THEN
    SELECT id INTO v_carried_id
    FROM propositions
    WHERE round_id = v_round_id AND carried_from_id IS NOT NULL
    ORDER BY created_at ASC
    LIMIT 1;
    IF v_carried_id IS NOT NULL THEN
      PERFORM resolve_carried_winner_for_round(v_round_id, v_carried_id);
    END IF;
  ELSE
    UPDATE rounds
    SET phase = 'rating', phase_started_at = NOW()
    WHERE id = v_round_id AND phase = 'proposing';
  END IF;

  RETURN NEW;
END;
$function$;
