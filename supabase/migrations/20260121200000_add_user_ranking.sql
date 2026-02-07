-- =============================================================================
-- MIGRATION: Add User Ranking System
-- =============================================================================
-- This migration adds user ranking calculation for rounds with formula:
--   round_rank = (voting_rank + proposing_rank) / 2
--
-- Where:
-- - voting_rank (0-100): Ordinal pairwise comparison accuracy against final MOVDA scores
-- - proposing_rank (0-100): Normalized average performance of user's propositions
--
-- Tables:
-- 1. user_voting_ranks - Pairwise comparison accuracy per user per round
-- 2. user_proposing_ranks - Proposition performance per user per round
-- 3. user_round_ranks - Combined ranking (50/50 average)
--
-- Functions:
-- - calculate_voting_ranks(p_round_id) - Pairwise comparison accuracy
-- - calculate_proposing_ranks(p_round_id) - Proposition performance (excludes carryover)
-- - calculate_round_ranks(p_round_id) - Combines both (50/50)
-- - store_round_ranks(p_round_id) - Persists to tables
--
-- Integration:
-- - Modifies complete_round_with_winner() to call store_round_ranks() after MOVDA
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Create user_voting_ranks table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."user_voting_ranks" (
    "id" BIGSERIAL PRIMARY KEY,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "participant_id" BIGINT NOT NULL REFERENCES "public"."participants"("id") ON DELETE CASCADE,
    "rank" REAL,  -- NULL if user didn't vote
    "correct_pairs" INTEGER NOT NULL DEFAULT 0,
    "total_pairs" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    CONSTRAINT "unique_user_voting_rank" UNIQUE ("round_id", "participant_id"),
    CONSTRAINT "rank_range" CHECK (rank IS NULL OR (rank >= 0 AND rank <= 100))
);

ALTER TABLE "public"."user_voting_ranks" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_voting_ranks" IS
'Stores voting accuracy rank for each user per round.
- rank: 0-100 (100 = perfect accuracy, NULL = user did not vote)
- correct_pairs: Number of pairwise comparisons that matched global ordering
- total_pairs: Total pairwise comparisons from user rankings';

CREATE INDEX IF NOT EXISTS "idx_user_voting_ranks_round"
ON "public"."user_voting_ranks" ("round_id");

CREATE INDEX IF NOT EXISTS "idx_user_voting_ranks_participant"
ON "public"."user_voting_ranks" ("participant_id");

-- =============================================================================
-- STEP 2: Create user_proposing_ranks table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."user_proposing_ranks" (
    "id" BIGSERIAL PRIMARY KEY,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "participant_id" BIGINT NOT NULL REFERENCES "public"."participants"("id") ON DELETE CASCADE,
    "rank" REAL,  -- NULL if user has no propositions (excludes carryover)
    "avg_score" REAL,  -- Average global score of user's propositions
    "proposition_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    CONSTRAINT "unique_user_proposing_rank" UNIQUE ("round_id", "participant_id"),
    CONSTRAINT "proposing_rank_range" CHECK (rank IS NULL OR (rank >= 0 AND rank <= 100))
);

ALTER TABLE "public"."user_proposing_ranks" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_proposing_ranks" IS
'Stores proposing performance rank for each user per round.
- rank: 0-100 (normalized performance, NULL = user has no propositions)
- avg_score: Average global_score of user''s propositions in this round
- proposition_count: Number of original propositions (excludes carryover)';

CREATE INDEX IF NOT EXISTS "idx_user_proposing_ranks_round"
ON "public"."user_proposing_ranks" ("round_id");

CREATE INDEX IF NOT EXISTS "idx_user_proposing_ranks_participant"
ON "public"."user_proposing_ranks" ("participant_id");

-- =============================================================================
-- STEP 3: Create user_round_ranks table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."user_round_ranks" (
    "id" BIGSERIAL PRIMARY KEY,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "participant_id" BIGINT NOT NULL REFERENCES "public"."participants"("id") ON DELETE CASCADE,
    "rank" REAL NOT NULL,  -- Combined rank (always present if user participated)
    "voting_rank" REAL,  -- NULL if user didn't vote
    "proposing_rank" REAL,  -- NULL if user didn't propose
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    CONSTRAINT "unique_user_round_rank" UNIQUE ("round_id", "participant_id"),
    CONSTRAINT "round_rank_range" CHECK (rank >= 0 AND rank <= 100)
);

ALTER TABLE "public"."user_round_ranks" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_round_ranks" IS
'Stores combined round rank for each user.
- rank: Combined score (voting_rank + proposing_rank) / 2, or single value if only one present
- voting_rank: Copy from user_voting_ranks (NULL if didn''t vote)
- proposing_rank: Copy from user_proposing_ranks (NULL if didn''t propose)
- Not inserted if user did neither (voting_rank AND proposing_rank are NULL)';

CREATE INDEX IF NOT EXISTS "idx_user_round_ranks_round"
ON "public"."user_round_ranks" ("round_id");

CREATE INDEX IF NOT EXISTS "idx_user_round_ranks_participant"
ON "public"."user_round_ranks" ("participant_id");

CREATE INDEX IF NOT EXISTS "idx_user_round_ranks_rank"
ON "public"."user_round_ranks" ("round_id", "rank" DESC);

-- =============================================================================
-- STEP 4: Create calculate_voting_ranks function
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."calculate_voting_ranks"(
    "p_round_id" BIGINT
)
RETURNS TABLE (
    participant_id BIGINT,
    rank REAL,
    correct_pairs INTEGER,
    total_pairs INTEGER
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
    v_user RECORD;
    v_prop_a RECORD;
    v_prop_b RECORD;
    v_user_pos_a REAL;
    v_user_pos_b REAL;
    v_global_score_a REAL;
    v_global_score_b REAL;
    v_correct INTEGER;
    v_total INTEGER;
    v_min_accuracy REAL;
    v_max_accuracy REAL;
BEGIN
    -- Create temp table to store raw accuracy scores
    DROP TABLE IF EXISTS temp_voting_scores;
    CREATE TEMP TABLE temp_voting_scores (
        participant_id BIGINT,
        accuracy REAL,
        correct_pairs INTEGER,
        total_pairs INTEGER
    );

    -- For each participant who submitted grid rankings
    FOR v_user IN
        SELECT DISTINCT gr.participant_id
        FROM grid_rankings gr
        WHERE gr.round_id = p_round_id
        AND gr.participant_id IS NOT NULL
    LOOP
        v_correct := 0;
        v_total := 0;

        -- Get all propositions this user ranked
        -- Compare each pair
        FOR v_prop_a IN
            SELECT gr.proposition_id, gr.grid_position
            FROM grid_rankings gr
            WHERE gr.round_id = p_round_id
            AND gr.participant_id = v_user.participant_id
        LOOP
            FOR v_prop_b IN
                SELECT gr.proposition_id, gr.grid_position
                FROM grid_rankings gr
                WHERE gr.round_id = p_round_id
                AND gr.participant_id = v_user.participant_id
                AND gr.proposition_id > v_prop_a.proposition_id  -- Avoid duplicate pairs
            LOOP
                v_user_pos_a := v_prop_a.grid_position;
                v_user_pos_b := v_prop_b.grid_position;

                -- Get global scores for these propositions
                SELECT COALESCE(pgs.global_score, 50.0) INTO v_global_score_a
                FROM proposition_global_scores pgs
                WHERE pgs.round_id = p_round_id
                AND pgs.proposition_id = v_prop_a.proposition_id;

                SELECT COALESCE(pgs.global_score, 50.0) INTO v_global_score_b
                FROM proposition_global_scores pgs
                WHERE pgs.round_id = p_round_id
                AND pgs.proposition_id = v_prop_b.proposition_id;

                -- Default to 50.0 if no global scores exist
                v_global_score_a := COALESCE(v_global_score_a, 50.0);
                v_global_score_b := COALESCE(v_global_score_b, 50.0);

                v_total := v_total + 1;

                -- Check if user's ordering matches global ordering
                IF (v_user_pos_a > v_user_pos_b AND v_global_score_a >= v_global_score_b) OR
                   (v_user_pos_a < v_user_pos_b AND v_global_score_a <= v_global_score_b) OR
                   (v_user_pos_a = v_user_pos_b AND v_global_score_a = v_global_score_b) THEN
                    v_correct := v_correct + 1;
                END IF;
            END LOOP;
        END LOOP;

        -- Store raw accuracy score
        IF v_total = 0 THEN
            -- User only ranked 1 proposition (no pairs) → 100% accuracy
            INSERT INTO temp_voting_scores VALUES (v_user.participant_id, 100.0, 0, 0);
        ELSE
            INSERT INTO temp_voting_scores VALUES (
                v_user.participant_id,
                (v_correct::REAL / v_total::REAL) * 100.0,
                v_correct,
                v_total
            );
        END IF;
    END LOOP;

    -- Get min/max for normalization
    SELECT MIN(t.accuracy), MAX(t.accuracy)
    INTO v_min_accuracy, v_max_accuracy
    FROM temp_voting_scores t;

    -- Return normalized ranks
    FOR v_user IN
        SELECT * FROM temp_voting_scores
    LOOP
        participant_id := v_user.participant_id;
        correct_pairs := v_user.correct_pairs;
        total_pairs := v_user.total_pairs;

        -- Normalize to 0-100 scale (best voter = 100, worst = 0)
        IF v_max_accuracy IS NULL OR v_min_accuracy IS NULL THEN
            rank := NULL;
        ELSIF v_max_accuracy = v_min_accuracy THEN
            -- All same accuracy → everyone gets 100
            rank := 100.0;
        ELSE
            rank := ((v_user.accuracy - v_min_accuracy) / (v_max_accuracy - v_min_accuracy)) * 100.0;
        END IF;

        RETURN NEXT;
    END LOOP;

    DROP TABLE IF EXISTS temp_voting_scores;
END;
$$;

ALTER FUNCTION "public"."calculate_voting_ranks"(BIGINT) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."calculate_voting_ranks" IS
'Calculates voting accuracy rank for all participants in a round.
Compares user pairwise orderings against global MOVDA scores.
NORMALIZED: Best voter in round = 100, worst voter = 0.
If all voters have same accuracy, everyone gets 100.';

-- =============================================================================
-- STEP 5: Create calculate_proposing_ranks function
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."calculate_proposing_ranks"(
    "p_round_id" BIGINT
)
RETURNS TABLE (
    participant_id BIGINT,
    rank REAL,
    avg_score REAL,
    proposition_count INTEGER
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
    v_min_avg REAL;
    v_max_avg REAL;
    v_user RECORD;
BEGIN
    -- Create temp table with average scores per participant
    -- Only count original propositions (carried_from_id IS NULL)
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
    AND p.carried_from_id IS NULL  -- Exclude carryover propositions
    AND p.participant_id IS NOT NULL
    GROUP BY p.participant_id;

    -- Get min/max for normalization
    SELECT MIN(t.avg_score), MAX(t.avg_score)
    INTO v_min_avg, v_max_avg
    FROM temp_proposing_scores t;

    -- Return normalized ranks
    FOR v_user IN
        SELECT * FROM temp_proposing_scores
    LOOP
        participant_id := v_user.participant_id;
        avg_score := v_user.avg_score;
        proposition_count := v_user.proposition_count;

        -- Normalize to 0-100 scale
        IF v_max_avg IS NULL OR v_min_avg IS NULL THEN
            -- No propositions with scores
            rank := NULL;
        ELSIF v_max_avg = v_min_avg THEN
            -- All same score → everyone gets 100 (or could use 50)
            rank := 100.0;
        ELSE
            rank := ((v_user.avg_score - v_min_avg) / (v_max_avg - v_min_avg)) * 100.0;
        END IF;

        RETURN NEXT;
    END LOOP;

    DROP TABLE IF EXISTS temp_proposing_scores;
END;
$$;

ALTER FUNCTION "public"."calculate_proposing_ranks"(BIGINT) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."calculate_proposing_ranks" IS
'Calculates proposing performance rank for all participants in a round.
Uses average global_score of user''s propositions (excludes carryover).
Normalizes to 0-100 scale relative to other proposers in the round.
Single proposer gets 100. All same score = everyone gets 100.';

-- =============================================================================
-- STEP 6: Create calculate_round_ranks function
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
        (CASE
            WHEN c.voting_rank IS NOT NULL AND c.proposing_rank IS NOT NULL THEN
                (c.voting_rank + c.proposing_rank) / 2.0
            WHEN c.voting_rank IS NOT NULL THEN
                c.voting_rank
            WHEN c.proposing_rank IS NOT NULL THEN
                c.proposing_rank
            ELSE
                NULL
        END)::REAL as raw_rank,
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

ALTER FUNCTION "public"."calculate_round_ranks"(BIGINT) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."calculate_round_ranks" IS
'Calculates combined round rank for all participants.
NORMALIZED: Best performer in round = 100, worst = 0.
Formula: (voting_rank + proposing_rank) / 2
If only one is present, uses that value alone.
Returns nothing for participants who neither voted nor proposed.';

-- =============================================================================
-- STEP 7: Create store_round_ranks function
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."store_round_ranks"(
    "p_round_id" BIGINT
)
RETURNS VOID
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
BEGIN
    RAISE NOTICE '[USER RANKING] Storing user ranks for round %', p_round_id;

    -- Store voting ranks
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

    RAISE NOTICE '[USER RANKING] Stored % voting ranks',
        (SELECT COUNT(*) FROM user_voting_ranks WHERE round_id = p_round_id);

    -- Store proposing ranks
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

    RAISE NOTICE '[USER RANKING] Stored % proposing ranks',
        (SELECT COUNT(*) FROM user_proposing_ranks WHERE round_id = p_round_id);

    -- Store combined round ranks
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

    RAISE NOTICE '[USER RANKING] Stored % combined round ranks',
        (SELECT COUNT(*) FROM user_round_ranks WHERE round_id = p_round_id);
END;
$$;

ALTER FUNCTION "public"."store_round_ranks"(BIGINT) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."store_round_ranks" IS
'Persists calculated user ranks to tables. Idempotent - safe to call multiple times.
Stores voting ranks, proposing ranks, and combined round ranks.';

-- =============================================================================
-- STEP 8: Update complete_round_with_winner to call store_round_ranks
-- =============================================================================

CREATE OR REPLACE FUNCTION complete_round_with_winner(p_round_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_winner_id BIGINT;
    v_max_score REAL;
    v_tied_count INTEGER;
    v_is_sole_winner BOOLEAN;
BEGIN
    -- Get round info
    SELECT * INTO v_round FROM rounds WHERE id = p_round_id;

    IF v_round IS NULL OR v_round.completed_at IS NOT NULL THEN
        RETURN; -- Round doesn't exist or already completed
    END IF;

    -- CRITICAL: Calculate MOVDA scores first!
    -- This populates proposition_global_scores which is needed for winner selection
    PERFORM calculate_movda_scores_for_round(p_round_id);

    -- Calculate and store user rankings
    PERFORM store_round_ranks(p_round_id);

    -- Get the winner(s) from proposition_global_scores (MOVDA now calculated)
    SELECT proposition_id, global_score INTO v_winner_id, v_max_score
    FROM proposition_global_scores
    WHERE round_id = p_round_id
    ORDER BY global_score DESC
    LIMIT 1;

    IF v_winner_id IS NULL THEN
        -- No scores yet (no ratings at all), use oldest proposition
        SELECT id INTO v_winner_id
        FROM propositions
        WHERE round_id = p_round_id
        ORDER BY created_at ASC
        LIMIT 1;
        v_is_sole_winner := TRUE;

        -- Still need to populate round_winners for carry forward
        IF v_winner_id IS NOT NULL THEN
            INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
            VALUES (p_round_id, v_winner_id, 1, NULL);
        END IF;
    ELSE
        -- Check for ties
        SELECT COUNT(*) INTO v_tied_count
        FROM proposition_global_scores
        WHERE round_id = p_round_id AND global_score = v_max_score;

        v_is_sole_winner := (v_tied_count = 1);

        -- Insert all winners into round_winners table
        INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
        SELECT p_round_id, proposition_id,
               ROW_NUMBER() OVER (ORDER BY global_score DESC),
               global_score
        FROM proposition_global_scores
        WHERE round_id = p_round_id
        ORDER BY global_score DESC;
    END IF;

    -- Update round with winner (triggers on_round_winner_set for consensus check)
    UPDATE rounds
    SET winning_proposition_id = v_winner_id,
        is_sole_winner = v_is_sole_winner,
        completed_at = NOW()
    WHERE id = p_round_id;

    RAISE NOTICE '[COMPLETE ROUND] Completed round % with winner %, sole_winner=%',
        p_round_id, v_winner_id, v_is_sole_winner;
END;
$$;

COMMENT ON FUNCTION complete_round_with_winner IS
'Completes a round by:
1. Calculating MOVDA scores (proposition rankings)
2. Calculating and storing user rankings (voting + proposing)
3. Determining the winner(s)
4. Populating round_winners table
5. Updating the round (triggers on_round_winner_set for consensus/carry forward)';

-- =============================================================================
-- STEP 9: Enable RLS and create policies
-- =============================================================================

ALTER TABLE "public"."user_voting_ranks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."user_proposing_ranks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."user_round_ranks" ENABLE ROW LEVEL SECURITY;

-- Anyone can view user ranks (public leaderboard)
CREATE POLICY "Anyone can view user_voting_ranks" ON "public"."user_voting_ranks"
FOR SELECT USING (TRUE);

CREATE POLICY "Anyone can view user_proposing_ranks" ON "public"."user_proposing_ranks"
FOR SELECT USING (TRUE);

CREATE POLICY "Anyone can view user_round_ranks" ON "public"."user_round_ranks"
FOR SELECT USING (TRUE);

-- Service role can manage (for functions running with SECURITY DEFINER)
CREATE POLICY "Service role can manage user_voting_ranks" ON "public"."user_voting_ranks"
FOR ALL USING (TRUE);

CREATE POLICY "Service role can manage user_proposing_ranks" ON "public"."user_proposing_ranks"
FOR ALL USING (TRUE);

CREATE POLICY "Service role can manage user_round_ranks" ON "public"."user_round_ranks"
FOR ALL USING (TRUE);

-- =============================================================================
-- STEP 10: Grant permissions
-- =============================================================================

GRANT SELECT ON "public"."user_voting_ranks" TO anon, authenticated;
GRANT ALL ON "public"."user_voting_ranks" TO service_role;
GRANT USAGE, SELECT ON SEQUENCE "public"."user_voting_ranks_id_seq" TO anon, authenticated, service_role;

GRANT SELECT ON "public"."user_proposing_ranks" TO anon, authenticated;
GRANT ALL ON "public"."user_proposing_ranks" TO service_role;
GRANT USAGE, SELECT ON SEQUENCE "public"."user_proposing_ranks_id_seq" TO anon, authenticated, service_role;

GRANT SELECT ON "public"."user_round_ranks" TO anon, authenticated;
GRANT ALL ON "public"."user_round_ranks" TO service_role;
GRANT USAGE, SELECT ON SEQUENCE "public"."user_round_ranks_id_seq" TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."calculate_voting_ranks"(BIGINT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION "public"."calculate_proposing_ranks"(BIGINT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION "public"."calculate_round_ranks"(BIGINT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION "public"."store_round_ranks"(BIGINT) TO anon, authenticated, service_role;

COMMIT;
