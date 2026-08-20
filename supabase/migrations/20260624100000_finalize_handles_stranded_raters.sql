-- Fix: a quick-chat matches RATING round could STALL when some voters are
-- "stranded" — they authored the only ideas on the board, so they have no
-- votable pair (e.g. a round with a leader + one challenger and everyone else
-- affirming; common in small groups). Such voters can't produce a completion or
-- vote, so v_done never reaches v_eligible (= all active humans) and the round
-- never finalizes.
--
-- The old FRONTEND auto-end handled this (it ended once the *able* voters were
-- done). We moved auto-advance to the backend this session and removed that
-- fallback, exposing the gap. Fix it at the source: finalize when there is no
-- *able* voter still pending (a voter with >= rating_minimum rateable props who
-- hasn't completed/skipped/graded) — stranded voters no longer block. The
-- existing "everyone done" path and the ">=1 real vote" guard are unchanged.

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
  v_done        INTEGER;
  v_eligible    INTEGER;
  v_pending     INTEGER;
  v_votes       INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, c.chat_id, ch.rating_mode, ch.max_cycles,
         ch.is_preview, ch.rating_minimum, ch.rating_agent_count
    INTO v_phase, v_completed, v_chat_id, v_rating_mode, v_max_cycles,
         v_is_preview, v_rating_min, v_agent_cnt
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
  -- props they didn't author to form a comparison) but haven't acted yet. When
  -- this hits 0, every voter who *could* weigh in has — stranded authors aside.
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

  SELECT COUNT(*) INTO v_votes
  FROM pairwise_comparisons
  WHERE round_id = v_round_id AND COALESCE(is_skip, false) = false;

  -- Finalize when everyone's accounted for (v_done >= v_eligible) OR no ABLE
  -- voter is still pending (stranded authors don't block) — and, for a real
  -- multi-user round, at least one real vote was cast.
  IF v_eligible > 0
     AND (v_done >= v_eligible OR v_pending = 0)
     AND (v_is_preview IS TRUE OR v_votes >= 1) THEN
    PERFORM complete_round_with_winner(v_round_id);
  END IF;

  RETURN NEW;
END;
$function$;
