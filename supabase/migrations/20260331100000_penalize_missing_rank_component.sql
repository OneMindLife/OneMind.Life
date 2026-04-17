-- =============================================================================
-- MIGRATION: Penalize Missing Rank Component
-- =============================================================================
-- Updates calculate_round_ranks so that if a user didn't propose or didn't vote,
-- the missing component is treated as 0 instead of being ignored.
-- This prevents users from gaming the system by only participating in one phase.
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."calculate_round_ranks"(
    "p_round_id" BIGINT
)
RETURNS TABLE (
    participant_id BIGINT,
    rank REAL,
    voting_rank REAL,
    proposing_rank REAL
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
    v_min_raw REAL;
    v_max_raw REAL;
BEGIN
    -- Create temp table with raw combined scores
    DROP TABLE IF EXISTS temp_combined_ranks;
    CREATE TEMP TABLE temp_combined_ranks AS
    WITH voting AS (
        SELECT
            cvr.participant_id,
            cvr.rank as voting_rank
        FROM calculate_voting_ranks(p_round_id) cvr
    ),
    proposing AS (
        SELECT
            cpr.participant_id,
            cpr.rank as proposing_rank
        FROM calculate_proposing_ranks(p_round_id) cpr
    ),
    combined AS (
        SELECT
            COALESCE(v.participant_id, pr.participant_id) as participant_id,
            v.voting_rank,
            pr.proposing_rank
        FROM voting v
        FULL OUTER JOIN proposing pr ON v.participant_id = pr.participant_id
    )
    SELECT
        c.participant_id,
        -- Missing component = 0 (penalizes non-participation)
        ((COALESCE(c.voting_rank, 0) + COALESCE(c.proposing_rank, 0)) / 2.0)::REAL as raw_rank,
        c.voting_rank,
        c.proposing_rank
    FROM combined c
    WHERE c.voting_rank IS NOT NULL OR c.proposing_rank IS NOT NULL;

    -- Get min/max for normalization
    SELECT MIN(t.raw_rank), MAX(t.raw_rank)
    INTO v_min_raw, v_max_raw
    FROM temp_combined_ranks t;

    -- Return normalized ranks
    RETURN QUERY
    SELECT
        t.participant_id,
        (CASE
            WHEN v_max_raw IS NULL OR v_min_raw IS NULL THEN
                NULL
            WHEN v_max_raw = v_min_raw THEN
                100.0  -- All same score → everyone gets 100
            ELSE
                ((t.raw_rank - v_min_raw) / (v_max_raw - v_min_raw)) * 100.0
        END)::REAL as rank,
        t.voting_rank,
        t.proposing_rank
    FROM temp_combined_ranks t;

    DROP TABLE IF EXISTS temp_combined_ranks;
END;
$$;

COMMENT ON FUNCTION "public"."calculate_round_ranks" IS
'Calculates combined round rank for all participants.
NORMALIZED: Best performer in round = 100, worst = 0.
Formula: (COALESCE(voting_rank, 0) + COALESCE(proposing_rank, 0)) / 2, then normalized.
Missing component (didn''t vote or didn''t propose) is treated as 0, penalizing non-participation.
Returns nothing for participants who neither voted nor proposed.';
