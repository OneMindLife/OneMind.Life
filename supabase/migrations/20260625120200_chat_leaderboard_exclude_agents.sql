-- Step 5 of solo game-mode AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
-- get_chat_leaderboard: exclude agents.
--
-- The per-CYCLE leaderboard (get_cycle_leaderboard, 20260624070000) and
-- proposing-rank scoring (calculate_proposing_ranks) already exclude agents.
-- The cross-game get_chat_leaderboard (20260331300000) never got the filter
-- because, until seat-fill, no agent ever produced a user_round_ranks row.
-- Voting fill bots DO get scored (their vote is part of the group signal), so
-- without this they would surface on the cross-game leaderboard. Exclude their
-- ROW from the display; their votes still count toward consensus + human MOVDA
-- ranks. (Authorship reveal in game results is separate and still shows "AI N".)
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
        SELECT DISTINCT r.id as round_id, r.created_at as round_created_at
        FROM rounds r
        JOIN cycles cy ON cy.id = r.cycle_id
        WHERE cy.chat_id = p_chat_id
        AND EXISTS (SELECT 1 FROM user_round_ranks urr WHERE urr.round_id = r.id)
    ),
    participant_rounds AS (
        SELECT
            p.id as participant_id,
            p.display_name,
            COUNT(cr.round_id)::INTEGER as total_rounds
        FROM participants p
        CROSS JOIN chat_rounds cr
        WHERE p.chat_id = p_chat_id
        AND p.status = 'active'
        AND p.is_agent = false   -- exclude AI players from the leaderboard
        AND cr.round_created_at >= p.created_at
        GROUP BY p.id, p.display_name
    ),
    ranked AS (
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
GRANT EXECUTE ON FUNCTION get_chat_leaderboard(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_leaderboard(BIGINT) TO anon;
