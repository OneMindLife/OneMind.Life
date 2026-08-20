-- Quick-create matches: auto-finalize the PREVIEW the moment everyone's done.
--
-- Matches rating rounds normally finalize through process-timers, whose two passes
-- (timer-expiry and early-advance) BOTH require phase_ends_at to be set. The
-- quick-create solo preview leaned on a client-side process-timers "nudge" plus a
-- 24h timer to get the instant result. That's fragile and timer-coupled.
--
-- This trigger gives matches rounds a real, immediate all-done finalize (the
-- equivalent of grid mode's grid_rankings early-advance trigger), so a preview
-- finalizes the instant its last rater finishes — no timer, no nudge.
--
-- SCOPE — deliberately narrow to avoid any regression:
--   * rating_mode = 'matches'  (grid keeps its own grid_rankings trigger; grid never
--     writes rating_completions/rating_skips, so this wouldn't fire for it anyway)
--   * is_preview = TRUE         (PREVIEW chats only)
--
-- Why NOT real chats: in a real chat participants JOIN OVER TIME, so "done >= eligible"
-- briefly becomes true early (host + one fast voter finish before others click the
-- link) and a silent auto-seal would end the chat under the latecomers. Real chats
-- finalize via the host "End voting" button instead (host_end_voting). A preview has
-- a fixed participant set at creation (solo, or host + agents), so all-done is a true
-- signal there and can't seal prematurely.
--
-- "done" mirrors process-timers' getMatchesRatingProgress EXACTLY: distinct participants
-- across rating_completions ∪ grid_rankings ∪ rating_skips. "eligible" is
-- get_rating_eligible_count (active participants; agents only when rating_agent_count>0).
--
-- SECURITY DEFINER + search_path: this calls complete_round_with_winner, which does
-- cross-table DML (round_winners/rounds/cycles). Without DEFINER, RLS silently drops
-- those writes when the trigger fires from user/agent DML. (See CLAUDE.md.)

CREATE OR REPLACE FUNCTION public.matches_preview_maybe_finalize()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_round_id   BIGINT := NEW.round_id;
  v_phase      TEXT;
  v_completed  TIMESTAMPTZ;
  v_chat_id    BIGINT;
  v_rating_mode TEXT;
  v_is_preview BOOLEAN;
  v_done       INTEGER;
  v_eligible   INTEGER;
BEGIN
  -- Serialize concurrent completions on the same round so two simultaneous
  -- "last" raters don't both race into complete_round_with_winner.
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, c.chat_id, ch.rating_mode, ch.is_preview
    INTO v_phase, v_completed, v_chat_id, v_rating_mode, v_is_preview
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  -- Only matches PREVIEW rating rounds that are still open.
  IF v_phase <> 'rating'
     OR v_completed IS NOT NULL
     OR v_rating_mode <> 'matches'
     OR v_is_preview IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- done = distinct raters across all three completion signals (matches process-timers)
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

  IF v_eligible > 0 AND v_done >= v_eligible THEN
    PERFORM complete_round_with_winner(v_round_id);
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.matches_preview_maybe_finalize() IS
  'Finalizes a matches PREVIEW rating round the instant every eligible rater is done (done >= get_rating_eligible_count). Preview-only: real chats finalize via the host End-voting button to avoid sealing under late joiners.';

DROP TRIGGER IF EXISTS trg_matches_preview_finalize_completion ON public.rating_completions;
CREATE TRIGGER trg_matches_preview_finalize_completion
  AFTER INSERT ON public.rating_completions
  FOR EACH ROW
  EXECUTE FUNCTION public.matches_preview_maybe_finalize();

DROP TRIGGER IF EXISTS trg_matches_preview_finalize_skip ON public.rating_skips;
CREATE TRIGGER trg_matches_preview_finalize_skip
  AFTER INSERT ON public.rating_skips
  FOR EACH ROW
  EXECUTE FUNCTION public.matches_preview_maybe_finalize();
