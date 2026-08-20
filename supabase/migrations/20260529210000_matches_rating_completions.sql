-- =============================================================================
-- MIGRATION: rating_completions — per-rater "finished rating" marker
-- =============================================================================
-- Matches (pairwise) votes write to pairwise_comparisons, which the progress
-- bar and early-advance logic do NOT read (both count grid_rankings). So a
-- pure-human matches round never early-advances and its progress bar never
-- moves. Fix: an explicit "this participant finished rating this round" marker,
-- written by the matches panel when its pair-selector is exhausted (onDone).
--
-- Completion is then computed per-RATER (not per-proposition coverage), so it
-- works regardless of HOW a participant rated:
--   done(participant) = has a rating_completions row
--                       OR has grid_rankings coverage (grid raters / agents)
--                       OR has a rating_skips row (skipped)
-- progress% = done / eligible ; early-advance when done >= threshold.
--
-- Scoped to the marker + RLS only. The "done" union + progress% + advance
-- branch live in the client notifier and process-timers (separate changes).
-- See docs/MATCHES_RATING_MODE_SPEC.md.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.rating_completions (
  id             BIGSERIAL PRIMARY KEY,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  round_id       BIGINT NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
  participant_id BIGINT REFERENCES public.participants(id) ON DELETE CASCADE,
  session_token  UUID,
  CONSTRAINT rc_has_rater CHECK (participant_id IS NOT NULL OR session_token IS NOT NULL)
);

COMMENT ON TABLE public.rating_completions IS
  'One row per (rater, round) marking that the rater finished the rating phase. Written by the matches panel when its pair-selector is exhausted. Feeds matches-mode progress% and early-advance.';

-- One completion per rater per round.
CREATE UNIQUE INDEX IF NOT EXISTS rc_unique_rater_round
  ON public.rating_completions (
    round_id,
    COALESCE(participant_id::text, session_token::text)
  );
CREATE INDEX IF NOT EXISTS rc_round_idx ON public.rating_completions (round_id);

-- RLS mirrors grid_rankings / pairwise_comparisons (service-role bypass +
-- scoped owner/round checks). No cross-table DML, so no trigger.
ALTER TABLE public.rating_completions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Chat participants can view rating_completions" ON public.rating_completions;
CREATE POLICY "Chat participants can view rating_completions"
  ON public.rating_completions FOR SELECT
  USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
      SELECT 1 FROM participants p
      JOIN rounds r ON r.id = rating_completions.round_id
      JOIN cycles c ON c.id = r.cycle_id
      WHERE p.chat_id = c.chat_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Participants can insert own rating_completions" ON public.rating_completions;
CREATE POLICY "Participants can insert own rating_completions"
  ON public.rating_completions FOR INSERT
  WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (owns_participant(participant_id) AND participant_can_access_round(participant_id, round_id))
  );

DROP POLICY IF EXISTS "Participants can delete own rating_completions" ON public.rating_completions;
CREATE POLICY "Participants can delete own rating_completions"
  ON public.rating_completions FOR DELETE
  USING (
    (current_setting('role', true) = 'service_role')
    OR (owns_participant(participant_id) AND participant_can_access_round(participant_id, round_id))
  );

-- =============================================================================
-- get_matches_rating_progress — group rating progress for a MATCHES round.
-- =============================================================================
-- Returns (done, eligible) where a rater is "done" if they have a completion
-- marker, grid coverage, or a rating-skip — same per-rater union the
-- process-timers early-advance uses. The client notifier calls this ONLY when
-- chat.rating_mode = 'matches' (grid chats never pay for it), and drives the
-- round-status progress bar from done/eligible. SECURITY DEFINER so the counts
-- are consistent regardless of the caller's RLS visibility.
CREATE OR REPLACE FUNCTION public.get_matches_rating_progress(
  p_round_id BIGINT,
  p_chat_id  BIGINT
)
RETURNS TABLE (done INT, eligible INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT
    (
      SELECT COUNT(DISTINCT pid)::INT FROM (
        SELECT participant_id AS pid FROM rating_completions
          WHERE round_id = p_round_id AND participant_id IS NOT NULL
        UNION
        SELECT participant_id FROM grid_rankings
          WHERE round_id = p_round_id AND participant_id IS NOT NULL
        UNION
        SELECT participant_id FROM rating_skips
          WHERE round_id = p_round_id AND participant_id IS NOT NULL
      ) u
    ) AS done,
    COALESCE(public.get_rating_eligible_count(p_chat_id), 0)::INT AS eligible;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_matches_rating_progress(BIGINT, BIGINT)
  TO anon, authenticated, service_role;
