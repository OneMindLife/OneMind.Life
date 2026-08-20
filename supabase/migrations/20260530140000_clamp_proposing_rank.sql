-- Clamp the proposing percentile rank to [0,100].
--
-- calculate_proposing_ranks normalizes a user's avg_score into a 0–100 percentile:
--   rank := ((avg_score - min) / (max - min)) * 100
-- but v_min_avg/v_max_avg are declared REAL (float4) while the temp table's avg_score
-- is AVG(...) = DOUBLE PRECISION (float8). For the top-ranked user the float8 avg_score
-- can be a hair larger than the float4-rounded v_max_avg, so the ratio comes out very
-- slightly above 1.0 and rank lands at ~100.0000076 — which violates the
-- `proposing_rank_range` CHECK (rank <= 100) on user_proposing_ranks. It's data-dependent
-- (only certain avg_score values round badly), which is why it surfaces intermittently.
--
-- A percentile rank is [0,100] by definition, so clamp it. This guarantees the constraint
-- regardless of float rounding. (Body is the live definition; only the rank line changes.)

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
            -- Clamp to [0,100]: float4/float8 rounding between avg_score (float8) and
            -- v_max_avg (float4) can otherwise push the top user a hair over 100.
            rank := LEAST(100.0, GREATEST(0.0,
                ((v_user.avg_score - v_min_avg) / (v_max_avg - v_min_avg)) * 100.0));
        END IF;

        RETURN NEXT;
    END LOOP;

    DROP TABLE IF EXISTS temp_proposing_scores;
END;
$function$;
