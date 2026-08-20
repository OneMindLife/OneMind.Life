-- Fix: the 30-minute live-score recompute skipped repository (never_seals)
-- chats, so GLOBAL's ranking went stale (8h+ observed) and newly-posted
-- opinions never got a score at all.
--
-- Why it was broken: `recompute_active_round_scores` only looped rounds with
-- `phase = 'rating'`. A never_seals repository chat (GLOBAL) has NO rating
-- phase — its single round sits permanently in `phase = 'proposing'` (browse,
-- vote, and add anytime, no phase gate). So the cron ran every 30 min, matched
-- zero of GLOBAL's rounds, and never rebuilt its scores. The scorer itself
-- (`calculate_pairwise_comparison_scores`) rebuilds ALL props in the round each
-- run, so an unscored opinion just means "the recompute hasn't run since it was
-- added" — which, for GLOBAL, was never.
--
-- Fix: also include repository rounds regardless of phase. Repository rounds are
-- always live/votable, so the "new votes since last compute" guard below is what
-- decides whether work is needed — the phase check was never meaningful for them.
-- rating_mode = 'matches' and the pairwise-comparisons EXISTS guard still scope
-- this to head-to-head-scored rounds (which GLOBAL is), so nothing else changes.

CREATE OR REPLACE FUNCTION public.recompute_active_round_scores()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT rd.id
    FROM rounds rd
    JOIN cycles c ON c.id = rd.cycle_id
    JOIN chats ch ON ch.id = c.chat_id
    WHERE (rd.phase = 'rating' OR ch.never_seals = true)  -- repository rounds have no rating phase
      AND rd.completed_at IS NULL
      AND ch.rating_mode = 'matches'
      AND EXISTS (SELECT 1 FROM pairwise_comparisons pc WHERE pc.round_id = rd.id)
      -- only if there are new votes since the last score computation
      AND COALESCE((SELECT max(pc.created_at) FROM pairwise_comparisons pc WHERE pc.round_id = rd.id), 'epoch'::timestamptz)
        > COALESCE((SELECT max(pgs.last_updated) FROM proposition_global_scores pgs WHERE pgs.round_id = rd.id), 'epoch'::timestamptz)
  LOOP
    BEGIN
      PERFORM public.calculate_movda_scores_for_round(r.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'recompute_active_round_scores: round % failed: %', r.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.recompute_active_round_scores() IS
  'Every 30 min (pg_cron): rebuild live global_scores for active matches-mode rounds that have new votes since last compute. Includes never_seals repository rounds (GLOBAL) which have no rating phase — added 20260718 after they were silently skipped and GLOBAL''s ranking went stale.';
