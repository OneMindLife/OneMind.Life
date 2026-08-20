-- Fix get_cycle_leaderboard: show ALL players who were scored this game.
--
-- The original (copied from get_chat_leaderboard) only counted a round for a
-- participant if they joined BEFORE that round was created. In a game the host
-- starting proposing IS what creates R1, and everyone else joins DURING R1 — so
-- every non-host player was excluded and the leaderboard showed only the host.
--
-- A player belongs on the per-game leaderboard if they have a round rank in the
-- cycle, full stop (having a rank means they participated). Drop the join-time
-- filter and rank by average round rank across the cycle's scored rounds.

CREATE OR REPLACE FUNCTION public.get_cycle_leaderboard(p_cycle_id bigint)
RETURNS TABLE(participant_id bigint, display_name text, avg_rank real, rounds_participated integer, total_rounds integer)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id bigint;
  v_total_rounds integer;
BEGIN
  SELECT chat_id INTO v_chat_id FROM cycles WHERE id = p_cycle_id;
  IF v_chat_id IS NULL THEN
    RETURN;
  END IF;

  -- Scored rounds in this cycle (rounds that produced user_round_ranks).
  SELECT count(DISTINCT r.id) INTO v_total_rounds
  FROM rounds r
  WHERE r.cycle_id = p_cycle_id
    AND EXISTS (SELECT 1 FROM user_round_ranks u WHERE u.round_id = r.id);

  RETURN QUERY
  SELECT p.id,
         p.display_name,
         AVG(urr.rank)::real        AS avg_rank,
         COUNT(urr.id)::integer     AS rounds_participated,
         v_total_rounds             AS total_rounds
  FROM participants p
  JOIN user_round_ranks urr ON urr.participant_id = p.id
  JOIN rounds r            ON r.id = urr.round_id AND r.cycle_id = p_cycle_id
  WHERE p.chat_id = v_chat_id
    AND p.status = 'active'
  GROUP BY p.id, p.display_name
  ORDER BY AVG(urr.rank) DESC NULLS LAST;
END;
$function$;
