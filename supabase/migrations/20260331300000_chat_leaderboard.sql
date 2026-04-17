-- =============================================================================
-- MIGRATION: Chat Leaderboard
-- =============================================================================
-- Adds an RPC function to get per-chat leaderboard rankings.
-- Aggregates user_round_ranks across all rounds in a chat, only counting
-- rounds that occurred after each participant joined.
-- =============================================================================

-- RPC function to get chat leaderboard
CREATE OR REPLACE FUNCTION get_chat_leaderboard(p_chat_id BIGINT)
RETURNS TABLE (
    participant_id BIGINT,
    display_name TEXT,
    avg_rank REAL,
    rounds_participated INTEGER,
    total_rounds INTEGER
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH chat_rounds AS (
        -- All completed rounds in this chat (have rankings)
        SELECT DISTINCT r.id as round_id, r.created_at as round_created_at
        FROM rounds r
        JOIN cycles cy ON cy.id = r.cycle_id
        WHERE cy.chat_id = p_chat_id
        AND EXISTS (SELECT 1 FROM user_round_ranks urr WHERE urr.round_id = r.id)
    ),
    participant_rounds AS (
        -- For each active participant, count eligible rounds (after they joined)
        SELECT
            p.id as participant_id,
            p.display_name,
            COUNT(cr.round_id)::INTEGER as total_rounds
        FROM participants p
        CROSS JOIN chat_rounds cr
        WHERE p.chat_id = p_chat_id
        AND p.status = 'active'
        AND cr.round_created_at >= p.created_at
        GROUP BY p.id, p.display_name
    ),
    ranked AS (
        -- Aggregate rankings for each participant
        SELECT
            pr.participant_id,
            pr.display_name,
            AVG(urr.rank)::REAL as avg_rank,
            COUNT(urr.id)::INTEGER as rounds_participated,
            pr.total_rounds
        FROM participant_rounds pr
        LEFT JOIN user_round_ranks urr ON urr.participant_id = pr.participant_id
            AND urr.round_id IN (
                SELECT cr.round_id FROM chat_rounds cr
                WHERE cr.round_created_at >= (
                    SELECT p2.created_at FROM participants p2 WHERE p2.id = pr.participant_id
                )
            )
        GROUP BY pr.participant_id, pr.display_name, pr.total_rounds
    )
    SELECT
        ranked.participant_id,
        ranked.display_name,
        ranked.avg_rank,
        ranked.rounds_participated,
        ranked.total_rounds
    FROM ranked
    ORDER BY ranked.avg_rank DESC NULLS LAST;
END;
$$;

ALTER FUNCTION get_chat_leaderboard(BIGINT) OWNER TO postgres;

COMMENT ON FUNCTION get_chat_leaderboard IS
'Returns per-chat leaderboard: average rank across all rounds after each participant joined.
Only counts rounds that have user_round_ranks (completed rounds).
Ordered by avg_rank DESC (best performers first).';

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_chat_leaderboard(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_leaderboard(BIGINT) TO anon;
