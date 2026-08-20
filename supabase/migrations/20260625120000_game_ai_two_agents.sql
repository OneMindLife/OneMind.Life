-- Step 1 of solo game-mode AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
-- Two AI identities per game chat + an agent_role lever.
--
-- Solo play needs up to 2 bots so a 1-human game still reaches 3 distinct
-- proposers (the engine's well-formed-round minimum: a rater can't rate its own
-- idea and needs >=2 others to compare). One agent can submit only ONE new
-- proposition per round (unique index idx_propositions_unique_new_per_round on
-- (round_id, participant_id)), so two distinct bot authors are required for two
-- distinct bot ideas. The bots are pre-provisioned and reused across games in
-- the room — carry-forward copies the winning prop's participant_id, so an
-- author identity that won a round must stay stable.
--
-- agent_role (game AI only), set per round by the regime selector (next
-- migration) from the live human count:
--   'off'      — idle this round (neither proposes nor votes)
--   'proposer' — proposes only, never votes (IDEATION regime: humans >= 3)
--   'player'   — proposes AND votes (FILL regime: humans < 3)
-- The bots are ALWAYS status='active'; participation is driven entirely by
-- agent_role, so we never mutate status and never delete an agent (its carried
-- idea may reference it). agent_role is read by game-ai-proposer / game-ai-voter;
-- it is NOT consumed by the eligible-rater counting — engaged-eligible
-- (get_matches_rating_progress, max_cycles=1) already counts a bot iff it votes.

ALTER TABLE public.participants
  ADD COLUMN IF NOT EXISTS agent_role text NOT NULL DEFAULT 'off';

ALTER TABLE public.participants
  DROP CONSTRAINT IF EXISTS participants_agent_role_check;
ALTER TABLE public.participants
  ADD CONSTRAINT participants_agent_role_check
  CHECK (agent_role IN ('off', 'proposer', 'player'));

COMMENT ON COLUMN public.participants.agent_role IS
  'Game AI only. off=idle, proposer=proposes only (IDEATION), player=proposes+votes (FILL). Set per round by the regime selector; read by game-ai-proposer/game-ai-voter. Non-agents are always ''off''.';

-- ── provision TWO agents ("AI 1","AI 2") when a game opts in ──
-- Both seeded active with role 'off'; the regime selector assigns roles at the
-- first round's proposing-open (and every round after).
CREATE OR REPLACE FUNCTION public.add_game_ai_participant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
  VALUES
    (NEW.id, gen_random_uuid(), 'AI 1', false, 'active', true),
    (NEW.id, gen_random_uuid(), 'AI 2', false, 'active', true);
  RETURN NEW;
END;
$function$;
-- (trigger add_game_ai_participant_trg is unchanged — still WHEN has_ai_player.)

-- ── backfill existing game chats: rename the lone 'AI' to 'AI 1', add 'AI 2' ──
DO $$
DECLARE
  v_chat RECORD;
BEGIN
  UPDATE participants SET display_name = 'AI 1'
   WHERE is_agent = true AND display_name = 'AI';

  FOR v_chat IN
    SELECT c.id
    FROM chats c
    WHERE c.has_ai_player = true
      AND (SELECT COUNT(*) FROM participants p
             WHERE p.chat_id = c.id AND p.is_agent = true) < 2
  LOOP
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
    VALUES (v_chat.id, gen_random_uuid(), 'AI 2', false, 'active', true);
  END LOOP;
END $$;
