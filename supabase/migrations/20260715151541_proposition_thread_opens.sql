-- Thread-open tracking (Joel, 2026-07-15): "N people opened this thread" — the
-- honest social-proof metric for SUBTHREADS, where head-to-head votes are too
-- sparse (max ~2 voters) to show "N votes". Distinct people per idea-thread
-- (PK dedups). Locked down: RLS on, no direct policies — only the SECURITY
-- DEFINER RPCs below touch it. Starts empty and accrues from now; the UI shows
-- it only past a floor so it never reads as sparse.
CREATE TABLE IF NOT EXISTS public.proposition_views (
  proposition_id bigint NOT NULL REFERENCES public.propositions(id) ON DELETE CASCADE,
  participant_id bigint NOT NULL REFERENCES public.participants(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (proposition_id, participant_id)
);
CREATE INDEX IF NOT EXISTS idx_proposition_views_prop ON public.proposition_views (proposition_id);

ALTER TABLE public.proposition_views ENABLE ROW LEVEL SECURITY;
-- No policies: direct anon/authenticated access denied; the DEFINER RPCs are the
-- only path in and out.

-- Record that a participant opened an idea's thread (idempotent per person).
CREATE OR REPLACE FUNCTION public.record_thread_open(
  p_proposition_id bigint,
  p_participant_id bigint
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO public.proposition_views (proposition_id, participant_id)
  VALUES (p_proposition_id, p_participant_id)
  ON CONFLICT DO NOTHING;
$$;

-- Distinct-opener counts for every opened idea in a round (drives the card badge).
CREATE OR REPLACE FUNCTION public.get_round_open_counts(p_round_id bigint)
RETURNS TABLE(proposition_id bigint, opens bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT pv.proposition_id, count(*)::bigint AS opens
  FROM public.proposition_views pv
  JOIN public.propositions p ON p.id = pv.proposition_id
  WHERE p.round_id = p_round_id
  GROUP BY pv.proposition_id;
$$;

GRANT EXECUTE ON FUNCTION public.record_thread_open(bigint, bigint) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_round_open_counts(bigint) TO anon, authenticated;

COMMENT ON FUNCTION public.record_thread_open(bigint, bigint) IS
  'Record (idempotently) that a participant opened an idea''s thread. Powers the subthread "N opened" metric.';
COMMENT ON FUNCTION public.get_round_open_counts(bigint) IS
  'Distinct-opener count per opened idea in a round.';
