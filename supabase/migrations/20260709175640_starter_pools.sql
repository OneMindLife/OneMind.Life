-- Starter pools: one cached batch of LLM-generated starter takes per round,
-- shared by every visitor (H-GLOBALCHAT starter chips). Before this, each
-- visitor triggered their own generate-options LLM call (2-4s), and ~55% of
-- ad visitors bounced before the chips ever rendered. The pool makes chips
-- near-instant for everyone after the round's first visitor, and drops cost
-- to one LLM call per round.
--
-- Access model: ONLY the generate-options edge function (service role)
-- reads/writes this table. RLS is enabled with NO policies, so
-- anon/authenticated get nothing — an anonymous public room must not let
-- clients poison the chips every visitor sees.

CREATE TABLE public.starter_pools (
  round_id BIGINT PRIMARY KEY REFERENCES public.rounds(id) ON DELETE CASCADE,
  options JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.starter_pools ENABLE ROW LEVEL SECURITY;

-- Belt and braces: no client-role grants at all (service role bypasses).
REVOKE ALL ON public.starter_pools FROM PUBLIC, anon, authenticated;
