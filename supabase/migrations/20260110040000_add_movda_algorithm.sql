-- =============================================================================
-- MIGRATION: Add MOVDA (Margin of Victory Diminishing Adjustments) Algorithm
-- =============================================================================
-- This migration adds:
-- 1. movda_config table - Algorithm parameters
-- 2. proposition_movda_ratings table - MOVDA ratings per proposition per round
-- 3. grid_rankings table - User grid position rankings (0-100)
-- 4. proposition_global_scores table - Final normalized scores
-- 5. calculate_movda_scores_for_round() function - MOVDA algorithm implementation
-- 6. Trigger for auto-recalculation on grid insert
-- 7. Default MOVDA configuration values
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Create movda_config table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."movda_config" (
    "id" SERIAL PRIMARY KEY,
    "k_factor" REAL DEFAULT 32.0 NOT NULL,
    "tau" REAL DEFAULT 400.0 NOT NULL,
    "gamma" REAL DEFAULT 100.0 NOT NULL,
    "initial_rating" REAL DEFAULT 1500.0 NOT NULL,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    "updated_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    "singleton" BOOLEAN DEFAULT TRUE NOT NULL,
    CONSTRAINT "movda_config_singleton_check" CHECK (singleton = TRUE)
);

ALTER TABLE "public"."movda_config" OWNER TO "postgres";

COMMENT ON TABLE "public"."movda_config" IS
'MOVDA configuration parameters.
- k_factor: Learning rate for rating updates (default 32.0)
- tau: Rating difference scaling factor (default 400.0)
- gamma: Expected margin of victory scaling (default 100.0)
- initial_rating: Starting rating for new propositions (default 1500.0)';

COMMENT ON COLUMN "public"."movda_config"."singleton" IS 'Ensures only one configuration row exists. Always TRUE.';

-- Create unique constraint to enforce singleton
CREATE UNIQUE INDEX IF NOT EXISTS "movda_config_singleton_idx"
ON "public"."movda_config" (singleton) WHERE singleton = TRUE;

-- =============================================================================
-- STEP 2: Create proposition_movda_ratings table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."proposition_movda_ratings" (
    "id" BIGSERIAL PRIMARY KEY,
    "proposition_id" BIGINT NOT NULL REFERENCES "public"."propositions"("id") ON DELETE CASCADE,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "rating" REAL DEFAULT 1500.0 NOT NULL,
    "volatility" REAL DEFAULT 0.0,
    "comparisons_count" INTEGER DEFAULT 0,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    "updated_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT "unique_proposition_round_rating" UNIQUE ("proposition_id", "round_id")
);

ALTER TABLE "public"."proposition_movda_ratings" OWNER TO "postgres";

COMMENT ON TABLE "public"."proposition_movda_ratings" IS
'Stores MOVDA ratings for propositions. Ratings represent skill level with:
- Higher rating = stronger performance
- Volatility = rating uncertainty
- Comparisons count = data reliability indicator';

CREATE INDEX IF NOT EXISTS "idx_movda_ratings_round"
ON "public"."proposition_movda_ratings" ("round_id");

CREATE INDEX IF NOT EXISTS "idx_movda_ratings_proposition"
ON "public"."proposition_movda_ratings" ("proposition_id");

-- =============================================================================
-- STEP 3: Create grid_rankings table (user grid position rankings)
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."grid_rankings" (
    "id" BIGSERIAL PRIMARY KEY,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    "participant_id" BIGINT REFERENCES "public"."participants"("id") ON DELETE SET NULL,
    "session_token" UUID,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "proposition_id" BIGINT NOT NULL REFERENCES "public"."propositions"("id") ON DELETE CASCADE,
    "grid_position" REAL NOT NULL,
    CONSTRAINT "grid_position_range" CHECK (grid_position >= 0 AND grid_position <= 100),
    CONSTRAINT "grid_rankings_identity_check" CHECK (
        (participant_id IS NOT NULL) OR (session_token IS NOT NULL)
    )
);

ALTER TABLE "public"."grid_rankings" OWNER TO "postgres";

COMMENT ON TABLE "public"."grid_rankings" IS
'Stores direct grid ranking positions (0-100) for propositions as ranked by users.
Uses participant_id for authenticated users or session_token for anonymous users.';

CREATE INDEX IF NOT EXISTS "idx_grid_rankings_round"
ON "public"."grid_rankings" ("round_id");

CREATE INDEX IF NOT EXISTS "idx_grid_rankings_participant"
ON "public"."grid_rankings" ("participant_id");

CREATE INDEX IF NOT EXISTS "idx_grid_rankings_session"
ON "public"."grid_rankings" ("session_token");

-- Unique constraints: one ranking per user per proposition per round
-- For authenticated users (participant_id)
ALTER TABLE "public"."grid_rankings"
ADD CONSTRAINT "grid_rankings_round_proposition_participant_key"
UNIQUE ("round_id", "proposition_id", "participant_id");

-- For anonymous users (session_token) - partial unique index
CREATE UNIQUE INDEX IF NOT EXISTS "unique_grid_ranking_session"
ON "public"."grid_rankings" ("round_id", "proposition_id", "session_token")
WHERE session_token IS NOT NULL AND participant_id IS NULL;

-- =============================================================================
-- STEP 4: Create proposition_global_scores table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."proposition_global_scores" (
    "id" BIGSERIAL PRIMARY KEY,
    "proposition_id" BIGINT NOT NULL REFERENCES "public"."propositions"("id") ON DELETE CASCADE,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "global_score" REAL NOT NULL,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    "last_updated" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT "unique_proposition_round_score" UNIQUE ("proposition_id", "round_id"),
    CONSTRAINT "global_score_range" CHECK (global_score >= 0 AND global_score <= 100)
);

ALTER TABLE "public"."proposition_global_scores" OWNER TO "postgres";

COMMENT ON TABLE "public"."proposition_global_scores" IS
'Stores normalized global scores (0-100) for propositions after MOVDA calculation.';

CREATE INDEX IF NOT EXISTS "idx_global_scores_round"
ON "public"."proposition_global_scores" ("round_id");

CREATE INDEX IF NOT EXISTS "idx_global_scores_proposition"
ON "public"."proposition_global_scores" ("proposition_id");

-- =============================================================================
-- STEP 5: Create MOVDA scoring function
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."calculate_movda_scores_for_round"(
    "p_round_id" BIGINT,
    "p_seed" DOUBLE PRECISION DEFAULT NULL
) RETURNS VOID
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
    v_k_factor REAL;
    v_tau REAL;
    v_gamma REAL;
    v_initial_rating REAL;
    v_total_comparisons INT;
    v_iteration INT;
    v_max_iterations INT := 100;
    v_max_change REAL;
    v_convergence_threshold REAL := 0.5;

    -- Variables for sequential processing
    v_comparison RECORD;
    v_winner_rating REAL;
    v_loser_rating REAL;
    v_rating_diff REAL;
    v_expected REAL;
    v_expected_mov REAL;
    v_update REAL;
    v_iteration_max_change REAL;
BEGIN
    -- Set random seed if provided (for deterministic testing)
    IF p_seed IS NOT NULL THEN
        PERFORM setseed(p_seed);
    END IF;

    -- Load MOVDA configuration
    SELECT k_factor, tau, gamma, initial_rating
    INTO v_k_factor, v_tau, v_gamma, v_initial_rating
    FROM movda_config
    ORDER BY id DESC
    LIMIT 1;

    -- Use defaults if no config exists
    IF v_k_factor IS NULL THEN
        v_k_factor := 32.0;
        v_tau := 400.0;
        v_gamma := 100.0;
        v_initial_rating := 1500.0;
    END IF;

    RAISE NOTICE '[MOVDA] Starting SEQUENTIAL SGD for round % with params: K=%, τ=%, γ=%',
        p_round_id, v_k_factor, v_tau, v_gamma;

    -- Initialize ratings for ALL propositions that were ranked in this round
    INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating, comparisons_count)
    SELECT DISTINCT proposition_id, p_round_id, v_initial_rating, 0
    FROM grid_rankings
    WHERE round_id = p_round_id
    ON CONFLICT (proposition_id, round_id)
    DO UPDATE SET
        rating = v_initial_rating,
        comparisons_count = 0,
        updated_at = NOW();

    RAISE NOTICE '[MOVDA] Initialized ratings for % propositions',
        (SELECT COUNT(*) FROM proposition_movda_ratings WHERE round_id = p_round_id);

    -- Extract pairwise comparisons with margin of victory (MOV)
    -- Use random() for shuffling to break systematic biases
    DROP TABLE IF EXISTS movda_comparisons_shuffled;

    CREATE TEMP TABLE movda_comparisons_shuffled AS
    SELECT
        r1.proposition_id as winner_id,
        r2.proposition_id as loser_id,
        (r1.grid_position - r2.grid_position) as margin_of_victory
    FROM grid_rankings r1
    JOIN grid_rankings r2
        ON COALESCE(r1.participant_id::text, r1.session_token::text) =
           COALESCE(r2.participant_id::text, r2.session_token::text)
        AND r1.round_id = r2.round_id
        AND r1.grid_position > r2.grid_position
    WHERE r1.round_id = p_round_id
    ORDER BY random();  -- Shuffle comparisons for SGD

    GET DIAGNOSTICS v_total_comparisons = ROW_COUNT;
    RAISE NOTICE '[MOVDA] Extracted % pairwise comparisons (sequential SGD processing)', v_total_comparisons;

    -- Skip if no comparisons
    IF v_total_comparisons = 0 THEN
        RAISE NOTICE '[MOVDA] No comparisons found, skipping calculation';
        DROP TABLE IF EXISTS movda_comparisons_shuffled;
        RETURN;
    END IF;

    -- Sequential Stochastic Gradient Descent
    -- Process each comparison individually, updating ratings immediately
    FOR v_iteration IN 1..v_max_iterations LOOP
        v_iteration_max_change := 0;

        -- Process each comparison sequentially
        FOR v_comparison IN
            SELECT winner_id, loser_id, margin_of_victory
            FROM movda_comparisons_shuffled
        LOOP
            -- Get CURRENT ratings (updated throughout iteration)
            SELECT rating INTO v_winner_rating
            FROM proposition_movda_ratings
            WHERE proposition_id = v_comparison.winner_id
            AND round_id = p_round_id;

            SELECT rating INTO v_loser_rating
            FROM proposition_movda_ratings
            WHERE proposition_id = v_comparison.loser_id
            AND round_id = p_round_id;

            -- Calculate expected outcome using Elo formula
            v_rating_diff := v_winner_rating - v_loser_rating;
            v_expected := 1.0 / (1.0 + POWER(10, -v_rating_diff / v_tau));

            -- Calculate expected margin of victory
            v_expected_mov := v_gamma * TANH(v_rating_diff / v_tau);

            -- Calculate update signal
            -- Update = K * ((1 - E) + (Δ_MOV / γ))
            v_update := v_k_factor * (
                (1.0 - v_expected) +
                ((v_comparison.margin_of_victory - v_expected_mov) / v_gamma)
            );

            -- Scale down update for SGD (divide by total comparisons)
            -- This prevents overshooting and improves convergence
            v_update := v_update / v_total_comparisons;

            -- IMMEDIATELY update ratings (breaks circular dependency)
            UPDATE proposition_movda_ratings
            SET
                rating = rating + v_update,
                comparisons_count = comparisons_count + 1,
                updated_at = NOW()
            WHERE proposition_id = v_comparison.winner_id
            AND round_id = p_round_id;

            UPDATE proposition_movda_ratings
            SET
                rating = rating - v_update,
                comparisons_count = comparisons_count + 1,
                updated_at = NOW()
            WHERE proposition_id = v_comparison.loser_id
            AND round_id = p_round_id;

            -- Track max change for convergence detection
            v_iteration_max_change := GREATEST(v_iteration_max_change, ABS(v_update));
        END LOOP;

        -- Check convergence after full pass through all comparisons
        IF v_iteration_max_change < v_convergence_threshold THEN
            RAISE NOTICE '[MOVDA] Converged after % iterations (max change: %)', v_iteration, v_iteration_max_change;
            v_max_change := v_iteration_max_change;
            EXIT;
        END IF;

        v_max_change := v_iteration_max_change;
    END LOOP;

    RAISE NOTICE '[MOVDA] Completed SGD updates (% iterations, final max change: %)',
        v_iteration, v_max_change;

    -- Normalize comparisons_count (was incremented once per iteration, should be once total)
    UPDATE proposition_movda_ratings
    SET comparisons_count = comparisons_count / GREATEST(v_iteration, 1)
    WHERE round_id = p_round_id;

    -- Calculate volatility (rating uncertainty based on comparison count)
    UPDATE proposition_movda_ratings
    SET volatility = CASE
        WHEN comparisons_count = 0 THEN 350.0
        WHEN comparisons_count < 5 THEN 200.0
        WHEN comparisons_count < 10 THEN 100.0
        ELSE 50.0
    END
    WHERE round_id = p_round_id;

    -- Convert MOVDA ratings to normalized scores (0-100 scale)
    WITH rating_bounds AS (
        SELECT
            MIN(rating) as min_rating,
            MAX(rating) as max_rating,
            COUNT(*) as total_props
        FROM proposition_movda_ratings
        WHERE round_id = p_round_id
    )
    INSERT INTO proposition_global_scores (round_id, proposition_id, global_score)
    SELECT
        p_round_id,
        pmr.proposition_id,
        CASE
            WHEN rb.total_props = 1 THEN 100.0
            WHEN rb.max_rating = rb.min_rating THEN 50.0  -- All ratings equal
            ELSE 100.0 * (pmr.rating - rb.min_rating) / (rb.max_rating - rb.min_rating)
        END::REAL as global_score
    FROM proposition_movda_ratings pmr
    CROSS JOIN rating_bounds rb
    WHERE pmr.round_id = p_round_id
    ON CONFLICT (round_id, proposition_id)
    DO UPDATE SET
        global_score = EXCLUDED.global_score,
        last_updated = NOW();

    RAISE NOTICE '[MOVDA] Converted ratings to percentile scores';

    -- Log rating distribution
    RAISE NOTICE '[MOVDA] Rating distribution: min=%, max=%, avg=%',
        (SELECT MIN(rating)::NUMERIC(10,2) FROM proposition_movda_ratings WHERE round_id = p_round_id),
        (SELECT MAX(rating)::NUMERIC(10,2) FROM proposition_movda_ratings WHERE round_id = p_round_id),
        (SELECT AVG(rating)::NUMERIC(10,2) FROM proposition_movda_ratings WHERE round_id = p_round_id);

    DROP TABLE IF EXISTS movda_comparisons_shuffled;
END;
$$;

ALTER FUNCTION "public"."calculate_movda_scores_for_round"(BIGINT, DOUBLE PRECISION) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."calculate_movda_scores_for_round" IS
'Calculates MOVDA (Margin of Victory Diminishing Adjustments) scores for a round.
Uses Sequential Stochastic Gradient Descent to compute Elo-style ratings with
margin of victory adjustments, then normalizes to a 0-100 scale.

Parameters:
- p_round_id: The round to calculate scores for
- p_seed: Optional random seed for deterministic testing';

-- =============================================================================
-- STEP 6: Create trigger function for auto-recalculation
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."recalculate_movda_on_grid_insert"()
RETURNS TRIGGER
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
    v_round_id BIGINT;
    v_phase TEXT;
BEGIN
    v_round_id := NEW.round_id;

    -- Get round phase
    SELECT phase INTO v_phase
    FROM rounds
    WHERE id = v_round_id;

    -- Only recalculate if round is still in rating phase
    IF v_phase = 'rating' THEN
        RAISE NOTICE '[GRID RANKING TRIGGER] Recalculating MOVDA scores for round %', v_round_id;

        -- Recalculate MOVDA scores for this round
        PERFORM calculate_movda_scores_for_round(v_round_id);

        RAISE NOTICE '[GRID RANKING TRIGGER] Completed recalculation for round %', v_round_id;
    ELSE
        RAISE NOTICE '[GRID RANKING TRIGGER] Skipping round % (phase: %)', v_round_id, v_phase;
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."recalculate_movda_on_grid_insert"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."recalculate_movda_on_grid_insert" IS
'Trigger function that automatically recalculates MOVDA scores after grid ranking insert.
Only processes rounds that are still in rating phase.';

-- =============================================================================
-- STEP 7: Create trigger for auto-recalculation
-- =============================================================================

-- Use AFTER INSERT trigger (not statement-level for simpler implementation)
CREATE TRIGGER "trg_recalculate_movda_on_grid_insert"
AFTER INSERT ON "public"."grid_rankings"
FOR EACH ROW
EXECUTE FUNCTION "public"."recalculate_movda_on_grid_insert"();

-- =============================================================================
-- STEP 8: Enable RLS and create policies
-- =============================================================================

ALTER TABLE "public"."movda_config" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."proposition_movda_ratings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."grid_rankings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."proposition_global_scores" ENABLE ROW LEVEL SECURITY;

-- movda_config: Read-only for all, write for service_role
CREATE POLICY "Anyone can view movda_config" ON "public"."movda_config"
FOR SELECT USING (TRUE);

CREATE POLICY "Service role can manage movda_config" ON "public"."movda_config"
FOR ALL USING (TRUE);

-- proposition_movda_ratings: Read-only for all, managed by functions
CREATE POLICY "Anyone can view proposition_movda_ratings" ON "public"."proposition_movda_ratings"
FOR SELECT USING (TRUE);

CREATE POLICY "Service role can manage proposition_movda_ratings" ON "public"."proposition_movda_ratings"
FOR ALL USING (TRUE);

-- grid_rankings: Users can view all, insert their own
CREATE POLICY "Anyone can view grid_rankings" ON "public"."grid_rankings"
FOR SELECT USING (TRUE);

CREATE POLICY "Participants can insert own grid_rankings" ON "public"."grid_rankings"
FOR INSERT WITH CHECK (TRUE);

CREATE POLICY "Service role can manage grid_rankings" ON "public"."grid_rankings"
FOR ALL USING (TRUE);

-- proposition_global_scores: Read-only for all
CREATE POLICY "Anyone can view proposition_global_scores" ON "public"."proposition_global_scores"
FOR SELECT USING (TRUE);

CREATE POLICY "Service role can manage proposition_global_scores" ON "public"."proposition_global_scores"
FOR ALL USING (TRUE);

-- =============================================================================
-- STEP 9: Grant permissions
-- =============================================================================

GRANT SELECT ON "public"."movda_config" TO anon, authenticated;
GRANT ALL ON "public"."movda_config" TO service_role;

GRANT SELECT ON "public"."proposition_movda_ratings" TO anon, authenticated;
GRANT ALL ON "public"."proposition_movda_ratings" TO service_role;

GRANT SELECT, INSERT ON "public"."grid_rankings" TO anon, authenticated;
GRANT ALL ON "public"."grid_rankings" TO service_role;
GRANT USAGE, SELECT ON SEQUENCE "public"."grid_rankings_id_seq" TO anon, authenticated, service_role;

GRANT SELECT ON "public"."proposition_global_scores" TO anon, authenticated;
GRANT ALL ON "public"."proposition_global_scores" TO service_role;

GRANT EXECUTE ON FUNCTION "public"."calculate_movda_scores_for_round"(BIGINT, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION "public"."recalculate_movda_on_grid_insert"() TO service_role;

-- =============================================================================
-- STEP 10: Insert default MOVDA configuration
-- =============================================================================

INSERT INTO "public"."movda_config" (k_factor, tau, gamma, initial_rating, singleton)
VALUES (32.0, 400.0, 100.0, 1500.0, TRUE)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- STEP 11: Create helper function to get propositions with MOVDA scores
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."get_propositions_with_scores"(
    "p_round_id" BIGINT
)
RETURNS TABLE (
    proposition_id BIGINT,
    content TEXT,
    participant_id BIGINT,
    global_score REAL,
    movda_rating REAL,
    rank INTEGER,
    created_at TIMESTAMPTZ
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id as proposition_id,
        p.content,
        p.participant_id,
        COALESCE(pgs.global_score, 0.0) as global_score,
        COALESCE(pmr.rating, 1500.0) as movda_rating,
        ROW_NUMBER() OVER (ORDER BY COALESCE(pgs.global_score, 0.0) DESC)::INTEGER as rank,
        p.created_at
    FROM propositions p
    LEFT JOIN proposition_global_scores pgs
        ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
    LEFT JOIN proposition_movda_ratings pmr
        ON pmr.proposition_id = p.id AND pmr.round_id = p_round_id
    WHERE p.round_id = p_round_id
    ORDER BY COALESCE(pgs.global_score, 0.0) DESC;
END;
$$;

ALTER FUNCTION "public"."get_propositions_with_scores"(BIGINT) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."get_propositions_with_scores" IS
'Returns all propositions for a round with their MOVDA scores and rankings.
Ordered by global_score descending (best first).';

GRANT EXECUTE ON FUNCTION "public"."get_propositions_with_scores"(BIGINT) TO anon, authenticated, service_role;

-- =============================================================================
-- STEP 12: Create function to get unranked propositions for a user
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."get_unranked_propositions"(
    "p_round_id" BIGINT,
    "p_participant_id" BIGINT DEFAULT NULL,
    "p_session_token" UUID DEFAULT NULL
)
RETURNS TABLE (
    proposition_id BIGINT,
    content TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
BEGIN
    -- Get propositions that this user hasn't ranked yet
    -- Excludes the user's own propositions
    RETURN QUERY
    SELECT
        p.id as proposition_id,
        p.content,
        p.created_at
    FROM propositions p
    WHERE p.round_id = p_round_id
    -- Exclude own propositions (by participant_id if available)
    AND (p_participant_id IS NULL OR p.participant_id IS DISTINCT FROM p_participant_id)
    -- Exclude already ranked
    AND NOT EXISTS (
        SELECT 1 FROM grid_rankings gr
        WHERE gr.round_id = p_round_id
        AND gr.proposition_id = p.id
        AND (
            (p_participant_id IS NOT NULL AND gr.participant_id = p_participant_id)
            OR
            (p_session_token IS NOT NULL AND gr.session_token = p_session_token)
        )
    )
    ORDER BY p.created_at;
END;
$$;

ALTER FUNCTION "public"."get_unranked_propositions"(BIGINT, BIGINT, UUID) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."get_unranked_propositions" IS
'Returns propositions that a user has not yet ranked in a round.
Pass either participant_id or session_token to identify the user.
Excludes the user''s own propositions from the result.';

GRANT EXECUTE ON FUNCTION "public"."get_unranked_propositions"(BIGINT, BIGINT, UUID) TO anon, authenticated, service_role;

COMMIT;
