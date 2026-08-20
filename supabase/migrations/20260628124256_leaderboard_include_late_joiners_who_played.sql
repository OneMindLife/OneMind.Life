-- Leaderboard fix: a participant should appear if they actually participated
-- in a round (have a user_round_ranks entry), regardless of whether they
-- joined before or after the round was created. The old filter
-- (round_created_at >= p.created_at) excluded invite-flow joiners — people
-- who join via the link AFTER round 1 has already started but still play.
CREATE OR REPLACE FUNCTION public.get_chat_leaderboard(p_chat_id bigint)
 RETURNS TABLE(participant_id bigint, display_name text, avg_rank real, rounds_participated integer, total_rounds integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
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
        AND p.is_agent = false
        AND (
            cr.round_created_at >= p.created_at
            OR EXISTS (SELECT 1 FROM user_round_ranks urr_e
                       WHERE urr_e.round_id = cr.round_id
                         AND urr_e.participant_id = p.id)
        )
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
                OR EXISTS (SELECT 1 FROM user_round_ranks urr_r
                           WHERE urr_r.round_id = cr.round_id
                             AND urr_r.participant_id = pr.participant_id)
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
$function$;
