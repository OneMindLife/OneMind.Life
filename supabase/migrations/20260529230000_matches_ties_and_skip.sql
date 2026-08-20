-- =============================================================================
-- MIGRATION: Matches (pairwise) rating mode — ties-as-edges + skip rows
-- =============================================================================
-- Two refinements to the pairwise path introduced in
-- 20260529200000_matches_pairwise_mode.sql:
--
--   1. pairwise_comparisons.is_skip — a "skip" row records a pair the rater
--      passed on (no winner/loser outcome). Skips are EXCLUDED from MOVDA, but
--      still increment exposure (propositions.comparison_count via the existing
--      sync trigger) and occupy the unique-pair slot so the pair is not
--      re-offered to that rater.
--
--   2. calculate_movda_scores_for_round() — ties are now MOVDA edges. A tie
--      carries no ordering, but it means "these two are equal"; MOVDA is
--      margin-aware, so a tie is a legitimate margin-0 comparison that pulls
--      the two scores TOGETHER. Skip rows remain excluded.
--
-- The comparison_count trigger and the unique-pair index are UNCHANGED: skips
-- and ties still count toward exposure and still occupy a pair slot.
--
-- See docs/MATCHES_RATING_MODE_SPEC.md.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1. is_skip column
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.pairwise_comparisons
  ADD COLUMN IF NOT EXISTS is_skip BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.pairwise_comparisons.is_skip IS
  'A skip row records a pair the rater passed on (no winner/loser outcome). '
  'Excluded from MOVDA scoring, but still counts toward exposure '
  '(propositions.comparison_count) and occupies the unique-pair slot so the '
  'pair is not re-shown to that rater.';

-- ─────────────────────────────────────────────────────────────────────────
-- 2. MOVDA blend — verbatim copy of the live function (from
--    20260529200000_matches_pairwise_mode.sql) with exactly two changes in the
--    pairwise UNION subquery, both marked "MATCHES BLEND (b)":
--      - ties are now included as margin-0 edges
--      - skip rows are excluded
--    Everything else (grid handling, init, SGD, normalization, winner
--    selection) is unchanged.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_movda_scores_for_round(
  p_round_id BIGINT,
  p_seed DOUBLE PRECISION DEFAULT NULL::double precision
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
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

    -- MATCHES BLEND: fixed margin assigned to a direct pairwise win. The grid
    -- produces margins in [0,100] (position differences); a single binary pick
    -- carries no magnitude, so we assign a consistent moderate margin. Tunable;
    -- could move to movda_config later.
    v_match_margin REAL := 50.0;

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

    -- MATCHES BLEND (a): initialize ratings for ALL propositions ranked in this
    -- round via EITHER the grid OR pairwise matches.
    INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating, comparisons_count)
    SELECT DISTINCT pid, p_round_id, v_initial_rating, 0
    FROM (
        SELECT proposition_id AS pid FROM grid_rankings WHERE round_id = p_round_id
        UNION
        SELECT winner_proposition_id FROM pairwise_comparisons WHERE round_id = p_round_id
        UNION
        SELECT loser_proposition_id FROM pairwise_comparisons WHERE round_id = p_round_id
    ) ranked_props
    ON CONFLICT (proposition_id, round_id)
    DO UPDATE SET
        rating = v_initial_rating,
        comparisons_count = 0,
        updated_at = NOW();

    RAISE NOTICE '[MOVDA] Initialized ratings for % propositions',
        (SELECT COUNT(*) FROM proposition_movda_ratings WHERE round_id = p_round_id);

    -- Extract pairwise comparisons with margin of victory (MOV).
    -- MATCHES BLEND (b): UNION grid-derived comparisons with direct pairwise
    -- match edges. Ties are margin-0 edges (they pull the two scores together);
    -- skip rows are excluded (they record only that the rater passed). Whole
    -- set shuffled for SGD.
    DROP TABLE IF EXISTS movda_comparisons_shuffled;

    CREATE TEMP TABLE movda_comparisons_shuffled AS
    SELECT winner_id, loser_id, margin_of_victory
    FROM (
        -- grid-derived comparisons (existing behavior)
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

        UNION ALL

        -- pairwise match edges. A tie is a margin-0 edge (no ordering, but the
        -- two are equal); a skip is not an edge at all.
        SELECT
            pc.winner_proposition_id as winner_id,
            pc.loser_proposition_id as loser_id,
            CASE WHEN pc.is_tie THEN 0 ELSE v_match_margin END as margin_of_victory
        FROM pairwise_comparisons pc
        WHERE pc.round_id = p_round_id
          AND pc.is_skip = false
    ) all_comparisons
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
    FOR v_iteration IN 1..v_max_iterations LOOP
        v_iteration_max_change := 0;

        FOR v_comparison IN
            SELECT winner_id, loser_id, margin_of_victory
            FROM movda_comparisons_shuffled
        LOOP
            SELECT rating INTO v_winner_rating
            FROM proposition_movda_ratings
            WHERE proposition_id = v_comparison.winner_id
            AND round_id = p_round_id;

            SELECT rating INTO v_loser_rating
            FROM proposition_movda_ratings
            WHERE proposition_id = v_comparison.loser_id
            AND round_id = p_round_id;

            v_rating_diff := v_winner_rating - v_loser_rating;
            v_expected := 1.0 / (1.0 + POWER(10, -v_rating_diff / v_tau));
            v_expected_mov := v_gamma * TANH(v_rating_diff / v_tau);

            v_update := v_k_factor * (
                (1.0 - v_expected) +
                ((v_comparison.margin_of_victory - v_expected_mov) / v_gamma)
            );

            v_update := v_update / v_total_comparisons;

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

            v_iteration_max_change := GREATEST(v_iteration_max_change, ABS(v_update));
        END LOOP;

        IF v_iteration_max_change < v_convergence_threshold THEN
            RAISE NOTICE '[MOVDA] Converged after % iterations (max change: %)', v_iteration, v_iteration_max_change;
            v_max_change := v_iteration_max_change;
            EXIT;
        END IF;

        v_max_change := v_iteration_max_change;
    END LOOP;

    RAISE NOTICE '[MOVDA] Completed SGD updates (% iterations, final max change: %)',
        v_iteration, v_max_change;

    UPDATE proposition_movda_ratings
    SET comparisons_count = comparisons_count / GREATEST(v_iteration, 1)
    WHERE round_id = p_round_id;

    UPDATE proposition_movda_ratings
    SET volatility = CASE
        WHEN comparisons_count = 0 THEN 350.0
        WHEN comparisons_count < 5 THEN 200.0
        WHEN comparisons_count < 10 THEN 100.0
        ELSE 50.0
    END
    WHERE round_id = p_round_id;

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
            WHEN rb.max_rating = rb.min_rating THEN 50.0
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
$function$;

-- Preserve the lockdown from security_hardening_wave2 (function is host-only).
REVOKE EXECUTE ON FUNCTION public.calculate_movda_scores_for_round(BIGINT, DOUBLE PRECISION)
  FROM public, anon, authenticated;
