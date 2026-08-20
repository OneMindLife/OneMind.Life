-- =============================================================================
-- Enable Realtime for rating_completions.
-- =============================================================================
-- The matches-mode round-status bar subscribes to rating_completions so it
-- ticks up live when any rater finishes (ChatDetailNotifier ->
-- subscribeToRatingCompletions -> _refreshMatchesProgress). Postgres changes
-- only broadcast for tables in the supabase_realtime publication, so add it
-- here (mirrors rating_skips / round_skips / affirmations).
--
-- Default REPLICA IDENTITY is sufficient: we only act on INSERT (a completion
-- marker), and the handler re-queries get_matches_rating_progress rather than
-- reading payload columns, so DELETE old-record fidelity is irrelevant.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'rating_completions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.rating_completions;
  END IF;
END $$;
