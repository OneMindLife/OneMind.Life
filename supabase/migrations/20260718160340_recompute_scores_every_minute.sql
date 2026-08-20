-- Make the live-score recompute near-real-time: run every MINUTE instead of
-- every 30 minutes. Safe because `recompute_active_round_scores` is already
-- guarded to no-op unless there are new votes since the last computation, so an
-- idle minute costs one cheap indexed check. When it does fire, the recompute is
-- sub-millisecond at current scale (~97 opinions), and proposition_global_scores
-- is NOT in the realtime publication, so rewriting the scores broadcasts nothing
-- (no cascade). This makes the "live" ranking honest — a new opinion or vote is
-- reflected within ~60s instead of up to 30 min.
--
-- Watch-item (not a concern at current scale): the scorer does DELETE+INSERT of
-- all the round's score rows each run, so every-minute recompute during active
-- voting generates ~N dead tuples/min. Autovacuum handles this easily at N≈100;
-- if a round ever grows to thousands of opinions, switch the scorer to an UPSERT
-- to cut the churn before worrying about the cadence.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'recompute-round-scores') THEN
      PERFORM cron.unschedule('recompute-round-scores');
    END IF;
    PERFORM cron.schedule('recompute-round-scores', '* * * * *',
                          'SELECT public.recompute_active_round_scores()');
  END IF;
END $$;
