-- Repository mode (Joel, 2026-07-15): the room never seals. Rounds oscillate
-- proposing <-> rating forever — always growing (Grow) or ranking (Sort),
-- never a completed winner. Scoped by an explicit per-chat flag so ONLY the
-- GLOBAL public-opinion repository is affected; every other chat seals as before.
-- The reopen-instead-of-seal logic lives in process-timers (advancePhase +
-- processTreeNodeRound), gated on this flag.
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS never_seals boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.chats.never_seals IS
  'Repository mode: process-timers reopens the proposing phase instead of completing a round at rating-expiry, so the chat is always alive (Grow/Sort) and never sealed. Set for the GLOBAL public-opinion repository (chat 1260).';

UPDATE public.chats SET never_seals = true WHERE id = 1260;
