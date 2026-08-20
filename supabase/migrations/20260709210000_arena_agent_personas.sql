-- Arena seat-fill agent personas.
--
-- The continuous arena's seat-fill bots ("game AI") used to be two generic
-- identities ("AI 1","AI 2") speaking with one flat voice. This gives them a
-- DATA-DRIVEN roster of distinct personas: one catalog table is the single
-- source of truth, one agent is seeded per row, and the two edge functions
-- (game-ai-proposer / game-ai-voter) prepend each persona's `voice` to the
-- agent's system prompt.
--
-- To add or tune a persona, edit rows in arena_agent_personas — every NEW
-- has_ai_player chat then seeds one agent per row. Existing game chats are left
-- untouched (they keep whatever agents they already have; see the deliberate
-- absence of a backfill below), so this is fully backward compatible.

-- ── catalog: one row per seat-fill persona ──
CREATE TABLE IF NOT EXISTS public.arena_agent_personas (
  key          text PRIMARY KEY,
  display_name text NOT NULL,
  voice        text NOT NULL,
  sort         int  NOT NULL DEFAULT 0
);

COMMENT ON TABLE public.arena_agent_personas IS
  'Catalog of seat-fill agent personas; edit rows to add/tune personas — new has_ai_player chats seed one agent per row.';

-- Non-sensitive catalog. Edge fns use the service role (bypasses RLS) and
-- seeding is SECURITY DEFINER; this read policy just keeps a client read from
-- ever breaking.
ALTER TABLE public.arena_agent_personas ENABLE ROW LEVEL SECURITY;
CREATE POLICY arena_personas_read ON public.arena_agent_personas
  FOR SELECT USING (true);

-- ── seed the 4 voices (re-runnable: upserts in place) ──
INSERT INTO public.arena_agent_personas (key, display_name, voice, sort) VALUES
  ('skeptic', 'Keen Fox',
   'You tend to question the popular answer and name the thing everyone is tiptoeing around. Skeptical and a little provocative, but never cynical for its own sake.',
   1),
  ('pragmatist', 'Steady Heron',
   'You care about what actually works in the real world. You cut past idealism and buzzwords to the practical reality most people ignore.',
   2),
  ('idealist', 'Warm Lark',
   'You argue from values and how things ought to be. Earnest and principled, drawn to the deeper meaning behind the question.',
   3),
  ('wildcard', 'Odd Finch',
   'You bring the lateral, unexpected angle nobody else at the table would think of. Playful and original — occasionally absurd, but it always makes a point.',
   4)
ON CONFLICT (key) DO UPDATE
  SET display_name = EXCLUDED.display_name,
      voice        = EXCLUDED.voice,
      sort         = EXCLUDED.sort;

-- ── remember which persona each seat-fill agent is ──
ALTER TABLE public.participants
  ADD COLUMN IF NOT EXISTS agent_persona text;

COMMENT ON COLUMN public.participants.agent_persona IS
  'Seat-fill agent''s persona key → arena_agent_personas.key; NULL for legacy/generic agents and all non-agents.';

-- ── seed ONE agent per catalog persona when a game opts in ──
-- (was a hardcoded 2-row INSERT of "AI 1","AI 2"). Roles still start 'off';
-- the regime selector assigns them at the first round's proposing-open.
CREATE OR REPLACE FUNCTION public.add_game_ai_participant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent, agent_persona)
  SELECT NEW.id, gen_random_uuid(), ap.display_name, false, 'active', true, ap.key
  FROM arena_agent_personas ap
  ORDER BY ap.sort;
  RETURN NEW;
END;
$function$;
-- (trigger add_game_ai_participant_trg is unchanged — still WHEN has_ai_player.)
-- No backfill: existing game chats keep their current agents.
