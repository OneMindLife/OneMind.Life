-- Raise the proposition content limit to 600 characters (Joel, 2026-08-24).
--
-- Two check constraints had drifted apart on prod:
--   * propositions_content_check        -> length(content)      <= 500  (original baseline)
--   * propositions_content_length_check -> char_length(content) <= 300  (20260624000000)
-- The effective limit was the stricter 300, which truncated real user takes
-- (e.g. a 200-char app-side cut). Collapse both into a single 600 limit so
-- the DB matches the Flutter app + wedge UI limit.

ALTER TABLE public.propositions
  DROP CONSTRAINT IF EXISTS propositions_content_check;

ALTER TABLE public.propositions
  DROP CONSTRAINT IF EXISTS propositions_content_length_check;

ALTER TABLE public.propositions
  ADD CONSTRAINT propositions_content_length_check
  CHECK (char_length(content) <= 600);
