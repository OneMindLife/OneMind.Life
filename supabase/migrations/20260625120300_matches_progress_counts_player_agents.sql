-- Step 4a of solo game-mode AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
-- In a FILL game round, count the committed-but-maybe-not-yet-engaged voters in
-- the matches "eligible" set: the active 'player' agents AND the host.
--
-- WHY: game-ai-voter votes asynchronously (LLM latency) and the host drives the
-- round. With the pure engaged-eligible model the advance race is symmetric:
--   - human votes before the bots  → done==eligible==1 for a beat → advances
--     before the bots ever vote (solo winner decided by the human alone), OR
--   - bots vote before the host    → done==eligible==(#bots) → advances before
--     the host votes (solo winner decided without the human — the whole point).
-- Fix: whenever an active 'player' agent exists (FILL regime), add BOTH the
-- 'player' agents and the host to "eligible", so the round waits for all of
-- them. game-ai-voter writes a rating_skip on failure, so a dead bot lands in
-- "done" and can never strand the round; the host can also host_end_voting.
--
-- Scoped to FILL game rounds: the additive set is empty unless a 'player' agent
-- exists (only the game regime selector sets that), so non-game quick chats and
-- IDEATION rounds keep the unchanged engaged-only behavior (peeker-safe).
-- "done" is unchanged (completion / grid / skip).

CREATE OR REPLACE FUNCTION public.get_matches_rating_progress(
  p_round_id BIGINT,
  p_chat_id  BIGINT
)
RETURNS TABLE (done INT, eligible INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_quick_chat BOOLEAN;
  v_has_player    BOOLEAN;
BEGIN
  SELECT (c.max_cycles = 1) INTO v_is_quick_chat FROM chats c WHERE c.id = p_chat_id;
  v_is_quick_chat := COALESCE(v_is_quick_chat, FALSE);

  SELECT EXISTS (
    SELECT 1 FROM participants p
    WHERE p.chat_id = p_chat_id AND p.is_agent = true
      AND p.status = 'active' AND p.agent_role = 'player'
  ) INTO v_has_player;

  RETURN QUERY
  SELECT
    (
      -- "done": completion marker, full grid coverage, or rating-skip. (A
      -- 'player' bot that fails to vote writes a rating_skip, so it lands here.)
      SELECT COUNT(DISTINCT pid)::INT FROM (
        SELECT participant_id AS pid FROM rating_completions
          WHERE round_id = p_round_id AND participant_id IS NOT NULL
        UNION
        SELECT participant_id FROM grid_rankings
          WHERE round_id = p_round_id AND participant_id IS NOT NULL
        UNION
        SELECT participant_id FROM rating_skips
          WHERE round_id = p_round_id AND participant_id IS NOT NULL
      ) u
    ) AS done,
    CASE
      WHEN v_is_quick_chat THEN
        (
          SELECT COUNT(DISTINCT pid)::INT FROM (
            -- engaged-only humans (excludes peekers)
            SELECT participant_id AS pid FROM pairwise_comparisons
              WHERE round_id = p_round_id AND participant_id IS NOT NULL
            UNION
            SELECT participant_id FROM grid_rankings
              WHERE round_id = p_round_id AND participant_id IS NOT NULL
            UNION
            SELECT participant_id FROM rating_skips
              WHERE round_id = p_round_id AND participant_id IS NOT NULL
            UNION
            SELECT participant_id FROM rating_completions
              WHERE round_id = p_round_id AND participant_id IS NOT NULL
            UNION
            -- FILL game only: committed voters not yet engaged — 'player' bots
            -- (async LLM votes) + the host (drives the round). Empty otherwise.
            SELECT p.id FROM participants p
              WHERE v_has_player
                AND p.chat_id = p_chat_id
                AND p.status = 'active'
                AND (
                  p.agent_role = 'player'
                  OR (p.is_agent = false AND p.is_host = true)
                )
          ) e
        )
      ELSE
        COALESCE(public.get_rating_eligible_count(p_chat_id), 0)::INT
    END AS eligible;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_matches_rating_progress(BIGINT, BIGINT)
  TO anon, authenticated, service_role;
