-- =============================================================================
-- MIGRATION: Matches (pairwise) rating mode — DB layer
-- =============================================================================
-- Adds a pairwise-comparison rating path alongside the existing 0-100 grid.
-- A "match" records that a rater preferred one proposition over another (or
-- tied them). These feed the SAME MOVDA scoring engine: MOVDA already derives
-- (winner, loser, margin) comparisons from grid positions; we simply UNION in
-- direct pairwise edges with a fixed margin. Winner selection, normalization,
-- the read-only results grid, and round-advance are all unchanged.
--
-- Scope of THIS migration (DB layer, reviewed before the UI is built):
--   1. pairwise_comparisons table + integrity index + lookup indexes
--   2. propositions.comparison_count denorm + maintaining trigger
--   3. RLS on pairwise_comparisons (mirrors grid_rankings)
--   4. calculate_movda_scores_for_round() — blended to read BOTH sources
--   5. chats.rating_mode / chats.match_objective config columns
--
-- Deferred to later phases (NOT here): skip_rating_with_cleanup extension to
-- clear pairwise rows, live recalc-on-insert trigger for adaptive pairing,
-- agent-rate matches path, process-timers tweaks. The final winner is computed
-- by the existing complete_round_with_winner -> calculate_movda_scores_for_round
-- path, which this migration makes pairwise-aware, so core scoring is correct
-- without those.
--
-- See docs/MATCHES_RATING_MODE_SPEC.md.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1. pairwise_comparisons
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pairwise_comparisons (
  id                    BIGSERIAL PRIMARY KEY,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  round_id              BIGINT NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
  participant_id        BIGINT REFERENCES public.participants(id) ON DELETE CASCADE,
  session_token         UUID,
  winner_proposition_id BIGINT NOT NULL REFERENCES public.propositions(id) ON DELETE CASCADE,
  loser_proposition_id  BIGINT NOT NULL REFERENCES public.propositions(id) ON DELETE CASCADE,
  is_tie                BOOLEAN NOT NULL DEFAULT false,
  CONSTRAINT pc_distinct_props CHECK (winner_proposition_id <> loser_proposition_id),
  CONSTRAINT pc_has_rater CHECK (participant_id IS NOT NULL OR session_token IS NOT NULL)
);

COMMENT ON TABLE public.pairwise_comparisons IS
  'One row per match: a rater preferred winner over loser (or tied them). Feeds MOVDA alongside grid_rankings.';

-- One vote per unordered {A,B} pair per rater per round. Expression unique
-- index (LEAST/GREATEST makes the pair order-independent). Enforcement only —
-- the pair-selector never re-offers an already-voted pair, so the app inserts
-- (no upsert needed). A re-vote attempt errors, which is the desired guard.
CREATE UNIQUE INDEX IF NOT EXISTS pc_unique_pair_per_rater
  ON public.pairwise_comparisons (
    round_id,
    COALESCE(participant_id::text, session_token::text),
    LEAST(winner_proposition_id, loser_proposition_id),
    GREATEST(winner_proposition_id, loser_proposition_id)
  );

-- Lookups: by round (scoring + group tallies), by rater (per-user exposure).
CREATE INDEX IF NOT EXISTS pc_round_idx ON public.pairwise_comparisons (round_id);
CREATE INDEX IF NOT EXISTS pc_round_rater_idx ON public.pairwise_comparisons (
  round_id, COALESCE(participant_id::text, session_token::text)
);

-- ─────────────────────────────────────────────────────────────────────────
-- 2. propositions.comparison_count (coverage denorm, mirrors rating_count)
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.propositions
  ADD COLUMN IF NOT EXISTS comparison_count INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.propositions.comparison_count IS
  'Number of pairwise_comparisons rows involving this proposition (both winner and loser side). Maintained by sync_proposition_comparison_count_trg. Used for coverage-balanced pair selection.';

-- SECURITY DEFINER + search_path: cross-table write from a trigger on
-- pairwise_comparisons into propositions. Without DEFINER, RLS silently drops
-- the UPDATE when the trigger fires from anon/authenticated DML
-- (see CLAUDE.md "trigger SECURITY DEFINER" rule + memory).
CREATE OR REPLACE FUNCTION public.sync_proposition_comparison_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.propositions SET comparison_count = comparison_count + 1
      WHERE id = NEW.winner_proposition_id;
    UPDATE public.propositions SET comparison_count = comparison_count + 1
      WHERE id = NEW.loser_proposition_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.propositions SET comparison_count = GREATEST(comparison_count - 1, 0)
      WHERE id = OLD.winner_proposition_id;
    UPDATE public.propositions SET comparison_count = GREATEST(comparison_count - 1, 0)
      WHERE id = OLD.loser_proposition_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS sync_proposition_comparison_count_trg ON public.pairwise_comparisons;
CREATE TRIGGER sync_proposition_comparison_count_trg
  AFTER INSERT OR DELETE ON public.pairwise_comparisons
  FOR EACH ROW EXECUTE FUNCTION public.sync_proposition_comparison_count();

-- ─────────────────────────────────────────────────────────────────────────
-- 2b. Cross-round/chat injection guard.
-- The INSERT RLS policy proves the rater can access round_id, but NOT that the
-- two propositions belong to that round. Without this, a chat participant
-- could insert a comparison referencing propositions from another round/chat,
-- polluting this round's MOVDA scoring (cross-chat injection). grid_rankings
-- shares this structural gap historically; we close it for the new table.
-- SECURITY DEFINER so the membership read is reliable regardless of RLS
-- visibility (and so the trigger-security-audit lint accepts it). SELECT-only,
-- no cross-table DML.
CREATE OR REPLACE FUNCTION public.validate_pairwise_comparison_props()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM propositions
                 WHERE id = NEW.winner_proposition_id AND round_id = NEW.round_id) THEN
    RAISE EXCEPTION 'winner_proposition_id % does not belong to round %',
      NEW.winner_proposition_id, NEW.round_id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM propositions
                 WHERE id = NEW.loser_proposition_id AND round_id = NEW.round_id) THEN
    RAISE EXCEPTION 'loser_proposition_id % does not belong to round %',
      NEW.loser_proposition_id, NEW.round_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_pairwise_comparison_props_trg ON public.pairwise_comparisons;
CREATE TRIGGER validate_pairwise_comparison_props_trg
  BEFORE INSERT OR UPDATE ON public.pairwise_comparisons
  FOR EACH ROW EXECUTE FUNCTION public.validate_pairwise_comparison_props();

-- ─────────────────────────────────────────────────────────────────────────
-- 3. RLS (mirrors grid_rankings exactly: service-role bypass + scoped checks)
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.pairwise_comparisons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Chat participants can view pairwise_comparisons" ON public.pairwise_comparisons;
CREATE POLICY "Chat participants can view pairwise_comparisons"
  ON public.pairwise_comparisons FOR SELECT
  USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
      SELECT 1 FROM participants p
      JOIN rounds r ON r.id = pairwise_comparisons.round_id
      JOIN cycles c ON c.id = r.cycle_id
      WHERE p.chat_id = c.chat_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Participants can insert own pairwise_comparisons" ON public.pairwise_comparisons;
CREATE POLICY "Participants can insert own pairwise_comparisons"
  ON public.pairwise_comparisons FOR INSERT
  WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (owns_participant(participant_id) AND participant_can_access_round(participant_id, round_id))
  );

DROP POLICY IF EXISTS "Participants can update own pairwise_comparisons" ON public.pairwise_comparisons;
CREATE POLICY "Participants can update own pairwise_comparisons"
  ON public.pairwise_comparisons FOR UPDATE
  USING (
    (current_setting('role', true) = 'service_role')
    OR (owns_participant(participant_id) AND participant_can_access_round(participant_id, round_id))
  )
  WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (owns_participant(participant_id) AND participant_can_access_round(participant_id, round_id))
  );

-- ─────────────────────────────────────────────────────────────────────────
-- 4. chats.rating_mode / match_objective config
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS rating_mode TEXT NOT NULL DEFAULT 'grid'
    CHECK (rating_mode IN ('grid', 'matches'));
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS match_objective TEXT NOT NULL DEFAULT 'winner_only'
    CHECK (match_objective IN ('winner_only', 'full_rank'));

COMMENT ON COLUMN public.chats.rating_mode IS
  'grid = 0-100 placement grid (default, legacy). matches = inline pairwise voting.';
COMMENT ON COLUMN public.chats.match_objective IS
  'Only relevant when rating_mode=matches. winner_only = bracket (fewest comparisons). full_rank = leveled Swiss passes.';

-- ─────────────────────────────────────────────────────────────────────────
-- 5. MOVDA blend — read comparisons from BOTH grid_rankings AND
--    pairwise_comparisons. Verbatim copy of the live function with exactly two
--    changes, both marked "MATCHES BLEND":
--      (a) initialize ratings from props appearing in EITHER source
--      (b) UNION ALL the direct pairwise edges (fixed margin) into the
--          comparison set
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
    -- match edges (fixed margin; ties excluded). Whole set shuffled for SGD.
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

        -- pairwise match edges (fixed margin; ties carry no ordering signal)
        SELECT
            pc.winner_proposition_id as winner_id,
            pc.loser_proposition_id as loser_id,
            v_match_margin as margin_of_victory
        FROM pairwise_comparisons pc
        WHERE pc.round_id = p_round_id
          AND pc.is_tie = false
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
