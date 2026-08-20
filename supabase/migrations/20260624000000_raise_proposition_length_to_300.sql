-- Raise the proposition content length limit from 200 to 300 characters.
-- The UI cap was 120 (well under the old 200 DB limit); we're raising both so
-- users can write a slightly longer idea (a few sentences). The display side
-- wraps + scrolls long propositions so they never run off-screen. A separate
-- legacy constraint (propositions_content_check, <= 500) remains as a hard
-- backstop; this 300 constraint is the binding product limit.
ALTER TABLE public.propositions
  DROP CONSTRAINT IF EXISTS propositions_content_length_check;

ALTER TABLE public.propositions
  ADD CONSTRAINT propositions_content_length_check
  CHECK (char_length(content) <= 300);

COMMENT ON CONSTRAINT propositions_content_length_check ON public.propositions IS
  'Proposition content capped at 300 chars (raised from 200, 2026-06-24). UI enforces the same limit.';
