-- Least-rated-first proposition selection for rating phase.
--
-- New RPC: get_least_rated_proposition
-- Returns the proposition with the fewest ratings that the user hasn't
-- rated yet and isn't their own. Breaks ties randomly.
--
-- Also used for initial 2 propositions: call twice or use get_least_rated_propositions (batch).

-- =============================================================================
-- RPC: Get the least-rated proposition for a user to rate next
-- =============================================================================
CREATE OR REPLACE FUNCTION get_least_rated_proposition(
    p_round_id BIGINT,
    p_participant_id BIGINT,
    p_exclude_ids BIGINT[] DEFAULT '{}'
)
RETURNS TABLE (
    id BIGINT,
    round_id BIGINT,
    participant_id BIGINT,
    content TEXT,
    carried_from_id BIGINT,
    created_at TIMESTAMPTZ,
    rating_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.round_id,
        p.participant_id,
        p.content,
        p.carried_from_id,
        p.created_at,
        COALESCE(gr_count.cnt, 0) AS rating_count
    FROM propositions p
    LEFT JOIN (
        SELECT gr.proposition_id, COUNT(*) AS cnt
        FROM grid_rankings gr
        WHERE gr.round_id = p_round_id
        GROUP BY gr.proposition_id
    ) gr_count ON gr_count.proposition_id = p.id
    WHERE p.round_id = p_round_id
      -- Exclude user's own propositions
      AND (p.participant_id IS NULL OR p.participant_id != p_participant_id)
      -- Exclude already fetched
      AND NOT (p.id = ANY(p_exclude_ids))
    ORDER BY COALESCE(gr_count.cnt, 0) ASC, random()
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_least_rated_proposition(BIGINT, BIGINT, BIGINT[]) IS
'Returns the proposition with the fewest ratings that the given participant has not yet rated. Breaks ties randomly. Used for least-rated-first selection in the rating phase.';

-- =============================================================================
-- RPC: Get N least-rated propositions (for initial load)
-- =============================================================================
CREATE OR REPLACE FUNCTION get_least_rated_propositions(
    p_round_id BIGINT,
    p_participant_id BIGINT,
    p_count INT DEFAULT 2,
    p_exclude_ids BIGINT[] DEFAULT '{}'
)
RETURNS TABLE (
    id BIGINT,
    round_id BIGINT,
    participant_id BIGINT,
    content TEXT,
    carried_from_id BIGINT,
    created_at TIMESTAMPTZ,
    rating_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.round_id,
        p.participant_id,
        p.content,
        p.carried_from_id,
        p.created_at,
        COALESCE(gr_count.cnt, 0) AS rating_count
    FROM propositions p
    LEFT JOIN (
        SELECT gr.proposition_id, COUNT(*) AS cnt
        FROM grid_rankings gr
        WHERE gr.round_id = p_round_id
        GROUP BY gr.proposition_id
    ) gr_count ON gr_count.proposition_id = p.id
    WHERE p.round_id = p_round_id
      AND (p.participant_id IS NULL OR p.participant_id != p_participant_id)
      AND NOT (p.id = ANY(p_exclude_ids))
    ORDER BY COALESCE(gr_count.cnt, 0) ASC, random()
    LIMIT p_count;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_least_rated_propositions(BIGINT, BIGINT, INT, BIGINT[]) IS
'Returns N propositions with the fewest ratings for a participant. Used for initial load in rating phase.';

-- Grant access to anon and authenticated roles
GRANT EXECUTE ON FUNCTION get_least_rated_proposition(BIGINT, BIGINT, BIGINT[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_least_rated_propositions(BIGINT, BIGINT, INT, BIGINT[]) TO anon, authenticated;
