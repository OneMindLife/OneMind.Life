-- pairwise_comparisons had the same deep-join SELECT policy the June
-- realtime fix (20260602150000) removed from its sibling round-child tables:
-- rounds→cycles→participants EXISTS whose inner tables' own RLS inlines as
-- nested subplans — 141 rows cost 123k buffer hits / ~1s per query, and the
-- /g voting UI fires several at mount (the "matches take seconds to load"
-- report, 2026-07-14). Same cure: denormalized chat_id + the flat
-- is_chat_participant(chat_id) DEFINER-helper policy.

ALTER TABLE public.pairwise_comparisons
  ADD COLUMN IF NOT EXISTS chat_id BIGINT REFERENCES public.chats(id) ON DELETE CASCADE;

UPDATE public.pairwise_comparisons tt SET chat_id = c.chat_id
FROM public.rounds r JOIN public.cycles c ON c.id = r.cycle_id
WHERE r.id = tt.round_id AND tt.chat_id IS NULL;

ALTER TABLE public.pairwise_comparisons ALTER COLUMN chat_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pairwise_comparisons_chat_id
  ON public.pairwise_comparisons(chat_id);

-- Reuse the shared round-child trigger (ENABLE ALWAYS, mirrors siblings).
DROP TRIGGER IF EXISTS set_pairwise_comparisons_chat_id ON public.pairwise_comparisons;
CREATE TRIGGER set_pairwise_comparisons_chat_id
  BEFORE INSERT ON public.pairwise_comparisons
  FOR EACH ROW EXECUTE FUNCTION public.set_round_child_chat_id();
ALTER TABLE public.pairwise_comparisons
  ENABLE ALWAYS TRIGGER set_pairwise_comparisons_chat_id;

DROP POLICY IF EXISTS "Chat participants can view pairwise_comparisons" ON public.pairwise_comparisons;
CREATE POLICY "Chat participants can view pairwise_comparisons"
  ON public.pairwise_comparisons FOR SELECT
  USING (
    (current_setting('role', true) = 'service_role')
    OR public.is_chat_participant(chat_id)
  );
