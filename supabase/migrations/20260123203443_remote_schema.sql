set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.calculate_proposing_ranks(p_round_id bigint)
 RETURNS TABLE(participant_id bigint, rank real, avg_score real, proposition_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_min_avg REAL;
    v_max_avg REAL;
    v_user RECORD;
BEGIN
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
            rank := ((v_user.avg_score - v_min_avg) / (v_max_avg - v_min_avg)) * 100.0;
        END IF;

        RETURN NEXT;
    END LOOP;

    DROP TABLE IF EXISTS temp_proposing_scores;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.complete_round_with_winner(p_round_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round RECORD;
    v_winner_id BIGINT;
    v_max_score REAL;
    v_tied_count INTEGER;
    v_is_sole_winner BOOLEAN;
BEGIN
    SELECT * INTO v_round FROM rounds WHERE id = p_round_id;

    IF v_round IS NULL OR v_round.completed_at IS NOT NULL THEN
        RETURN;
    END IF;

    PERFORM calculate_movda_scores_for_round(p_round_id);
    PERFORM store_round_ranks(p_round_id);

    SELECT proposition_id, global_score INTO v_winner_id, v_max_score
    FROM proposition_global_scores
    WHERE round_id = p_round_id
    ORDER BY global_score DESC
    LIMIT 1;

    IF v_winner_id IS NULL THEN
        SELECT id INTO v_winner_id
        FROM propositions
        WHERE round_id = p_round_id
        ORDER BY created_at ASC
        LIMIT 1;
        v_is_sole_winner := TRUE;

        IF v_winner_id IS NOT NULL THEN
            INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
            VALUES (p_round_id, v_winner_id, 1, NULL);
        END IF;
    ELSE
        SELECT COUNT(*) INTO v_tied_count
        FROM proposition_global_scores
        WHERE round_id = p_round_id AND global_score = v_max_score;

        v_is_sole_winner := (v_tied_count = 1);

        INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
        SELECT p_round_id, proposition_id,
               ROW_NUMBER() OVER (ORDER BY global_score DESC),
               global_score
        FROM proposition_global_scores
        WHERE round_id = p_round_id
        ORDER BY global_score DESC;
    END IF;

    UPDATE rounds
    SET winning_proposition_id = v_winner_id,
        is_sole_winner = v_is_sole_winner,
        completed_at = NOW()
    WHERE id = p_round_id;

    RAISE NOTICE '[COMPLETE ROUND] Completed round % with winner %, sole_winner=%',
        p_round_id, v_winner_id, v_is_sole_winner;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.store_round_ranks(p_round_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RAISE NOTICE '[USER RANKING] Storing user ranks for round %', p_round_id;

    INSERT INTO user_voting_ranks (round_id, participant_id, rank, correct_pairs, total_pairs)
    SELECT
        p_round_id,
        cvr.participant_id,
        cvr.rank,
        cvr.correct_pairs,
        cvr.total_pairs
    FROM calculate_voting_ranks(p_round_id) cvr
    ON CONFLICT (round_id, participant_id)
    DO UPDATE SET
        rank = EXCLUDED.rank,
        correct_pairs = EXCLUDED.correct_pairs,
        total_pairs = EXCLUDED.total_pairs;

    INSERT INTO user_proposing_ranks (round_id, participant_id, rank, avg_score, proposition_count)
    SELECT
        p_round_id,
        cpr.participant_id,
        cpr.rank,
        cpr.avg_score,
        cpr.proposition_count
    FROM calculate_proposing_ranks(p_round_id) cpr
    ON CONFLICT (round_id, participant_id)
    DO UPDATE SET
        rank = EXCLUDED.rank,
        avg_score = EXCLUDED.avg_score,
        proposition_count = EXCLUDED.proposition_count;

    INSERT INTO user_round_ranks (round_id, participant_id, rank, voting_rank, proposing_rank)
    SELECT
        p_round_id,
        crr.participant_id,
        crr.rank,
        crr.voting_rank,
        crr.proposing_rank
    FROM calculate_round_ranks(p_round_id) crr
    WHERE crr.rank IS NOT NULL
    ON CONFLICT (round_id, participant_id)
    DO UPDATE SET
        rank = EXCLUDED.rank,
        voting_rank = EXCLUDED.voting_rank,
        proposing_rank = EXCLUDED.proposing_rank;
END;
$function$
;


