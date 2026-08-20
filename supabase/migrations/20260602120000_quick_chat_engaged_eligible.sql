-- =============================================================================
-- Quick chats: count only ENGAGED raters toward "eligible", not every joiner.
-- =============================================================================
-- Context: quick-chat invite links now auto-join on arrival (the link IS the
-- intent — see lib/screens/join/invite_join_screen.dart). That means a person
-- who opens the link just to peek becomes an active participant. With the old
-- eligible count (= every active participant), a single peeker made the host's
-- "X of Y here" never reach 100% and re-triggered the "you're ending early"
-- confirmation we deliberately removed for the solo/all-done case.
--
-- Fix: for HOST-CONTROLLED QUICK CHATS (max_cycles = 1) only, "eligible" counts
-- the distinct participants who have actually engaged with rating this round —
-- anyone with a pairwise vote, a grid ranking, a rating skip, or a completion
-- marker. A peeker who never votes is in neither "done" nor "eligible", so the
-- progress denominator only ever contains real voters. This reproduces the
-- behavior of a "join on first vote" model without the security-sensitive RLS
-- surgery that codeless non-participant viewing would require.
--
-- Regular (multi-cycle / timed) chats are UNCHANGED: they keep
-- get_rating_eligible_count (= every active participant), because their
-- timer-based early-advance must wait on everyone present, not just whoever
-- happened to start voting.
-- =============================================================================

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
BEGIN
  SELECT (c.max_cycles = 1)
    INTO v_is_quick_chat
    FROM chats c
    WHERE c.id = p_chat_id;
  v_is_quick_chat := COALESCE(v_is_quick_chat, FALSE);

  RETURN QUERY
  SELECT
    (
      -- "done" is unchanged: a rater is done when they have a completion
      -- marker, full grid coverage, or a rating-skip.
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
        -- Engaged-only: distinct participants who cast at least one vote this
        -- round (pairwise OR grid OR skip OR completion). Excludes peekers.
        (
          SELECT COUNT(DISTINCT pid)::INT FROM (
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
          ) e
        )
      ELSE
        COALESCE(public.get_rating_eligible_count(p_chat_id), 0)::INT
    END AS eligible;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_matches_rating_progress(BIGINT, BIGINT)
  TO anon, authenticated, service_role;
