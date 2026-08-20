-- Never-empty AI-seat-filled arena rooms (e.g. chat 1216 GLOBAL).
--
-- The proposing early-advance trigger counts ALL props incl. agents, so the 4
-- seat-fill agents proposing within ~9s trip the threshold and flip proposing ->
-- rating in ~6s, before any human can type. Disabling the early-advance
-- (thresholds NULL) alone would STALL the room: maybe_resolve_expired_proposing
-- needs a human challenger/affirm, so a pure-agent or lurking-human round extends
-- forever at timer expiry.
--
-- This flag lets process-timers.checkMinimumMet advance an arena proposing round
-- on its TIMER once the agent-filled board is votable (>=2 new props),
-- independent of human participation. Purely additive + gated: non-arena chats
-- are unaffected.
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS is_arena BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.chats.is_arena IS
'True for never-empty AI-seat-filled public arena rooms. process-timers advances
their proposing phase on the timer when the agent board is votable, so a present
human always gets the full proposing window (agents no longer flip proposing ->
rating in ~6s). Also disable the proposing early-advance (thresholds NULL) on
these chats.';

UPDATE public.chats SET is_arena = true WHERE id = 1216;
