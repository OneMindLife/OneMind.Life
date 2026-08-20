-- Game-mode affirmer scoring.
--
-- In a GAME chat, a participant who AFFIRMS the carried-forward idea (instead of
-- submitting a new one) is "backing the reigning champion as their horse." They
-- are scored on how that carried idea performs THIS round: the carried
-- proposition's global_score becomes the affirmer's proposing score, flat — all
-- affirmers (and the original author, if they also affirm) tie at the champion's
-- performance.
--
-- DECISION-MODE CHATS ARE UNCHANGED: affirmers still get no proposing credit
-- (carried props excluded), preserving the live decision product and the
-- existing 83_user_ranking / convergence tests. The only behavioral change is
-- gated on chats.mode = 'game'.
--
-- Affirm and submit are mutually exclusive per round (enforced by affirm_round),
-- so an affirmer never also has a new proposition — but we guard against double
-- insertion anyway.

CREATE OR REPLACE FUNCTION public.calculate_proposing_ranks(p_round_id bigint)
RETURNS TABLE(participant_id bigint, rank real, avg_score real, proposition_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_min_avg REAL;
    v_max_avg REAL;
    v_user RECORD;
    v_mode TEXT;
    v_carried_score REAL;
BEGIN
    -- Mode of the chat this round belongs to (round -> cycle -> chat).
    SELECT ch.mode INTO v_mode
    FROM rounds r
    JOIN cycles cy ON cy.id = r.cycle_id
    JOIN chats ch ON ch.id = cy.chat_id
    WHERE r.id = p_round_id;

    DROP TABLE IF EXISTS temp_proposing_scores;
    CREATE TEMP TABLE temp_proposing_scores AS
    SELECT
        p.participant_id,
        AVG(COALESCE(pgs.global_score, 50.0)) as avg_score,
        COUNT(*)::INTEGER as proposition_count
    FROM propositions p
    LEFT JOIN proposition_global_scores pgs
        ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
    WHERE p.round_id = p_round_id
    AND p.carried_from_id IS NULL
    AND p.participant_id IS NOT NULL
    GROUP BY p.participant_id;

    -- GAME MODE: credit affirmers with the carried idea's this-round performance.
    -- v_carried_score = avg of carried props' global scores (in practice a single
    -- carried winner). Each affirmer is inserted with that score (flat).
    IF v_mode = 'game' THEN
        SELECT AVG(COALESCE(pgs.global_score, 50.0))::REAL
        INTO v_carried_score
        FROM propositions p
        LEFT JOIN proposition_global_scores pgs
            ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
        WHERE p.round_id = p_round_id
        AND p.carried_from_id IS NOT NULL;

        IF v_carried_score IS NOT NULL THEN
            INSERT INTO temp_proposing_scores (participant_id, avg_score, proposition_count)
            SELECT a.participant_id, v_carried_score, 0
            FROM affirmations a
            WHERE a.round_id = p_round_id
            AND NOT EXISTS (
                SELECT 1 FROM temp_proposing_scores t
                WHERE t.participant_id = a.participant_id
            );
        END IF;
    END IF;

    SELECT MIN(t.avg_score), MAX(t.avg_score)
    INTO v_min_avg, v_max_avg
    FROM temp_proposing_scores t;

    FOR v_user IN
        SELECT * FROM temp_proposing_scores
    LOOP
        participant_id := v_user.participant_id;
        avg_score := v_user.avg_score;
        proposition_count := v_user.proposition_count;

        IF v_max_avg IS NULL OR v_min_avg IS NULL THEN
            rank := NULL;
        ELSIF v_max_avg = v_min_avg THEN
            rank := 100.0;
        ELSE
            -- Clamp to [0,100]: float4/float8 rounding can otherwise push the
            -- top user a hair over 100.
            rank := LEAST(100.0, GREATEST(0.0,
                ((v_user.avg_score - v_min_avg) / (v_max_avg - v_min_avg)) * 100.0));
        END IF;

        RETURN NEXT;
    END LOOP;

    DROP TABLE IF EXISTS temp_proposing_scores;
END;
$function$;
