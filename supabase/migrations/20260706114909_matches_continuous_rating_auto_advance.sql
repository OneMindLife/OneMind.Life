-- =============================================================================
-- Let CONTINUOUS matches chats early-advance the rating phase when the host
-- enabled rating auto-advance — closing a latent gap.
-- =============================================================================
-- Bug (documented by 135_matches_rating_early_advance_toggle_test.sql, Scenario C):
-- a matches-mode chat had NO working rating early-advance unless max_cycles = 1.
--   * matches_preview_maybe_finalize() was hard-gated to `max_cycles = 1`
--     (quick chats) and returned for every continuous chat.
--   * check_early_advance_on_rating() (the grid path) fires on grid_rankings and
--     reads grid counts — matches mode never writes grid_rankings, so it never
--     fires for a matches chat.
-- Net: a continuous matches chat (e.g. prod chat 1185) could turn the wizard's
-- "Rating auto-advance" toggle ON and still never advance on full turnout — only
-- the timer ended the phase.
--
-- Fix: relax the gate. matches rating rounds auto-finalize on full turnout for:
--   * Quick chats (max_cycles = 1): ALWAYS — unchanged. This also covers game
--     mode (game chats are always max_cycles = 1) and the seat-fill override.
--   * Continuous chats (max_cycles <> 1): OPT-IN — only when rating auto-advance
--     is enabled (rating_threshold_percent OR rating_threshold_count non-NULL)
--     AND the chat is not host-paced (start_mode <> 'manual'). This mirrors the
--     NULL-both = disabled contract already honored by check_early_advance_on_rating,
--     so the wizard toggle finally controls matches mode too. NULL-both (toggle
--     OFF) stays timer-only.
--
-- Semantics: "full turnout" = every eligible voter has acted (done >= eligible,
-- or no able voter still pending) with >= 1 real vote — identical to the quick
-- path. The threshold *values* (percent/count) are treated as an on/off signal
-- here; matches mode has no per-prop grid-coverage notion to map a fractional
-- percent onto. A fractional-turnout rule for matches would be a separate change.
--
-- Only the guard and its SELECT inputs change; the done/eligible/pending/votes
-- computation and the finalize call are byte-for-byte the prior body.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.matches_preview_maybe_finalize()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_round_id      BIGINT := NEW.round_id;
  v_phase         TEXT;
  v_completed     TIMESTAMPTZ;
  v_chat_id       BIGINT;
  v_rating_mode   TEXT;
  v_max_cycles    INTEGER;
  v_is_preview    BOOLEAN;
  v_agent_cnt     INTEGER;
  v_mode          TEXT;
  v_rating_thr_pct INTEGER;
  v_rating_thr_cnt INTEGER;
  v_start_mode    TEXT;
  v_has_player    BOOLEAN;
  v_prop_count    INTEGER;
  v_done          INTEGER;
  v_eligible      INTEGER;
  v_pending       INTEGER;
  v_votes         INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, c.chat_id, ch.rating_mode, ch.max_cycles,
         ch.is_preview, ch.rating_agent_count, ch.mode,
         ch.rating_threshold_percent, ch.rating_threshold_count, ch.start_mode
    INTO v_phase, v_completed, v_chat_id, v_rating_mode, v_max_cycles,
         v_is_preview, v_agent_cnt, v_mode,
         v_rating_thr_pct, v_rating_thr_cnt, v_start_mode
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  IF v_phase <> 'rating'
     OR v_completed IS NOT NULL
     OR v_rating_mode <> 'matches' THEN
    RETURN NEW;
  END IF;

  -- Quick chats (max_cycles = 1) always finalize on full turnout (unchanged;
  -- includes game mode + seat-fill). Continuous chats finalize ONLY when the
  -- host enabled rating auto-advance and isn't host-pacing the phases.
  IF v_max_cycles IS DISTINCT FROM 1 THEN
    IF (v_rating_thr_pct IS NULL AND v_rating_thr_cnt IS NULL)
       OR v_start_mode = 'manual' THEN
      RETURN NEW;
    END IF;
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

  -- pending = able voters who haven't acted. Under conditional self-inclusion
  -- (20260704160000) anyone can vote when the round has >= 2 props: they see
  -- all non-own props, plus their own when excluding it would leave fewer
  -- than 2. A "stranded" voter only exists when the board itself has < 2.
  SELECT COUNT(*) INTO v_prop_count
  FROM propositions WHERE round_id = v_round_id;

  IF v_prop_count < 2 THEN
    v_pending := 0;
  ELSE
    SELECT COUNT(*) INTO v_pending
    FROM participants p
    WHERE p.chat_id = v_chat_id
      AND p.status = 'active'
      AND (p.is_agent = false OR v_agent_cnt > 0)
      AND NOT EXISTS (SELECT 1 FROM rating_completions rc WHERE rc.round_id = v_round_id AND rc.participant_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM rating_skips rs WHERE rs.round_id = v_round_id AND rs.participant_id = p.id)
      AND NOT EXISTS (
        SELECT 1 FROM grid_rankings gr
        JOIN propositions gp ON gp.id = gr.proposition_id
        WHERE gp.round_id = v_round_id AND gr.participant_id = p.id
      );
  END IF;

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

  -- Finalize when everyone's accounted for (v_done >= v_eligible) OR no ABLE
  -- voter is still pending — and, for a real multi-user round, at least one
  -- real vote was cast.
  IF v_eligible > 0
     AND (v_done >= v_eligible OR v_pending = 0)
     AND (v_is_preview IS TRUE OR v_votes >= 1) THEN
    PERFORM complete_round_with_winner(v_round_id);
  END IF;

  RETURN NEW;
END;
$function$;
