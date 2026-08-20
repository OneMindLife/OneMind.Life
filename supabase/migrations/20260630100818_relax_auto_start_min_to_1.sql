-- ============================================================================
-- Relax the auto-start participant floor from 3 to 1.
-- ============================================================================
-- The >= 3 floor (20260113060000) predates AI seat-fill + the immediate-start
-- default. The ambient wizard now sets auto_start_participant_count = 1 so the
-- host's own join starts the chat immediately (seat-fill bots supply ideas to
-- vote on for a solo/sparse group). The old floor rejected every such insert
-- with chats_auto_start_participant_count_min_check (sqlstate 23514), which
-- surfaced as a PostgrestException and silently dead-ended the Create button —
-- a real tester got stuck here ("the app doesn't go forward no matter what I
-- try"). Floor of 1 keeps the only meaningful guard (can't auto-start at 0).
-- ============================================================================
ALTER TABLE public.chats
  DROP CONSTRAINT IF EXISTS chats_auto_start_participant_count_min_check;

ALTER TABLE public.chats
  ADD CONSTRAINT chats_auto_start_participant_count_min_check
  CHECK (auto_start_participant_count IS NULL OR auto_start_participant_count >= 1);
