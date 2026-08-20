-- Game mode foundation.
--
-- The wedge quick-chat engine is being reframed as a social "best ideas win"
-- GAME, distinct from the serious sealed-decision quick chat. The game is a
-- PERSISTENT room (each game = one cycle) with a per-game leaderboard and a
-- "play again" action that starts a fresh cycle with the SAME participants.
--
-- This migration adds the chat-level mode flag, a per-cycle question (so a room
-- that plays many games preserves per-game history), the start_new_game RPC,
-- and a per-cycle (per-game) leaderboard. Decision-mode behavior is unchanged.

-- 1. chats.mode — 'decision' (default, unchanged) | 'game'
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'decision';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chats_mode_check'
  ) THEN
    ALTER TABLE public.chats
      ADD CONSTRAINT chats_mode_check CHECK (mode IN ('decision','game'));
  END IF;
END $$;

COMMENT ON COLUMN public.chats.mode IS
  'decision = serious sealed-decision quick chat (default). game = social "best ideas win" mode: persistent room, per-game leaderboard, authorship revealed in results, affirmers scored on the carried idea''s performance, play-again starts a new cycle.';

-- 2. cycles.question — each game (cycle) remembers its own prompt. NULL for
--    legacy/decision cycles, which derive their question from chats.initial_message.
ALTER TABLE public.cycles
  ADD COLUMN IF NOT EXISTS question text;

COMMENT ON COLUMN public.cycles.question IS
  'The prompt for this cycle/game (game mode). NULL = derive from chats.initial_message (decision/legacy).';

-- 3. start_new_game(chat_id, question) — host-only "play again" for a game-mode
--    chat. Reopens the sealed room with a fresh cycle + question. Participants
--    are chat-scoped, so they carry over automatically. Each game = one cycle.
CREATE OR REPLACE FUNCTION public.start_new_game(p_chat_id bigint, p_question text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_service_role boolean;
  v_caller uuid;
  v_is_host boolean;
  v_mode text;
  v_new_cycle_id bigint;
BEGIN
  v_is_service_role := COALESCE(current_setting('role', true) = 'service_role', false)
                    OR COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', false);

  SELECT mode INTO v_mode FROM chats WHERE id = p_chat_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chat % not found', p_chat_id;
  END IF;
  IF v_mode <> 'game' THEN
    RAISE EXCEPTION 'start_new_game is only available for game-mode chats';
  END IF;

  IF p_question IS NULL OR length(btrim(p_question)) = 0 THEN
    RAISE EXCEPTION 'A question is required to start a new game';
  END IF;

  -- Authz: active host (or service role).
  IF NOT v_is_service_role THEN
    v_caller := auth.uid();
    IF v_caller IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;
    SELECT is_host INTO v_is_host
    FROM participants
    WHERE chat_id = p_chat_id AND user_id = v_caller AND status = 'active';
    IF v_is_host IS NOT TRUE THEN
      RAISE EXCEPTION 'Only the host can start a new game';
    END IF;
  END IF;

  -- Reopen the room with the new question; participants carry over (chat-scoped).
  UPDATE chats
  SET ended_at = NULL,
      initial_message = p_question
  WHERE id = p_chat_id;

  -- New cycle = the new game; stamp its question for per-game history.
  INSERT INTO cycles (chat_id, question)
  VALUES (p_chat_id, p_question)
  RETURNING id INTO v_new_cycle_id;

  -- First round opens directly in PROPOSING — the group is already present from
  -- the previous game, so skip the waiting/start gather step (mirrors the
  -- wedge's startGroupChat). Manual quick chat = no timer (phase_ends_at null).
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_new_cycle_id, 1, 'proposing', NOW());

  RETURN v_new_cycle_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.start_new_game(bigint, text) FROM public;
GRANT EXECUTE ON FUNCTION public.start_new_game(bigint, text) TO anon, authenticated, service_role;

-- 4. get_cycle_leaderboard(cycle_id) — per-GAME leaderboard (one cycle), vs
--    get_chat_leaderboard which aggregates across all cycles. Mirrors the chat
--    leaderboard logic but scopes the round set to a single cycle.
CREATE OR REPLACE FUNCTION public.get_cycle_leaderboard(p_cycle_id bigint)
RETURNS TABLE(participant_id bigint, display_name text, avg_rank real, rounds_participated integer, total_rounds integer)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id bigint;
BEGIN
  SELECT chat_id INTO v_chat_id FROM cycles WHERE id = p_cycle_id;
  IF v_chat_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH cycle_rounds AS (
    SELECT r.id AS round_id, r.created_at AS round_created_at
    FROM rounds r
    WHERE r.cycle_id = p_cycle_id
    AND EXISTS (SELECT 1 FROM user_round_ranks urr WHERE urr.round_id = r.id)
  ),
  participant_rounds AS (
    SELECT p.id AS participant_id, p.display_name,
           COUNT(cr.round_id)::INTEGER AS total_rounds
    FROM participants p
    CROSS JOIN cycle_rounds cr
    WHERE p.chat_id = v_chat_id
    AND p.status = 'active'
    AND cr.round_created_at >= p.created_at
    GROUP BY p.id, p.display_name
  ),
  ranked AS (
    SELECT pr.participant_id, pr.display_name,
           AVG(urr.rank)::REAL AS avg_rank,
           COUNT(urr.id)::INTEGER AS rounds_participated,
           pr.total_rounds
    FROM participant_rounds pr
    LEFT JOIN user_round_ranks urr ON urr.participant_id = pr.participant_id
      AND urr.round_id IN (SELECT cr.round_id FROM cycle_rounds cr)
    GROUP BY pr.participant_id, pr.display_name, pr.total_rounds
  )
  SELECT ranked.participant_id, ranked.display_name, ranked.avg_rank,
         ranked.rounds_participated, ranked.total_rounds
  FROM ranked
  ORDER BY ranked.avg_rank DESC NULLS LAST;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_cycle_leaderboard(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_cycle_leaderboard(bigint) TO anon, authenticated, service_role;
