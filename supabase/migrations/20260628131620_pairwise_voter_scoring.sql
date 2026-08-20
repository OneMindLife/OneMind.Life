-- =============================================================================
-- MIGRATION: Score pairwise (matches-mode) voters in calculate_voting_ranks
-- =============================================================================
-- Background:
--   calculate_voting_ranks(p_round_id) originally derived a voter "accuracy"
--   rank ONLY from grid_rankings (the 0-100 grid rating mode). In matches
--   (pairwise) mode the grid is never populated — votes live in
--   pairwise_comparisons instead — so matches-mode voters received no
--   voting_rank. The downstream combine (calculate_round_ranks) then only
--   produced ranks for proposers, and the leaderboard showed pairwise voters
--   as unranked forever.
--
-- This migration redefines calculate_voting_ranks so it scores BOTH sources:
--   * Grid voters: unchanged — pairwise ordinal accuracy of their grid
--     positions vs the round's global MOVDA scores.
--   * Pairwise voters: for each NON-skip, NON-tie comparison the voter is
--     "correct" if the proposition they picked as winner has a global_score
--     >= the loser's (they chose the idea the group ranked at least as high).
--     For tie rows the voter is "correct" if the two props' global_scores are
--     within a small epsilon (|diff| < 1.0). Skip rows are ignored entirely.
--     accuracy = correct / total * 100.
--
--   A participant who voted via EITHER source gets an accuracy; if they
--   somehow have both (not possible per round in practice, since rating_mode
--   is per-chat), the per-vote correct/total counts are UNIONED so each cast
--   vote is counted exactly once — no double counting.
--
--   The min-max normalization across all voters in the round is IDENTICAL to
--   the original grid path (best voter = 100, worst = 0; all-equal = 100), so
--   the calculate_round_ranks combine step keeps working unchanged.
--
-- Signature, return shape, SECURITY DEFINER, and ownership are preserved, so
-- store_round_ranks / calculate_round_ranks / complete_round_with_winner need
-- no changes. CREATE OR REPLACE preserves the existing privilege grants set by
-- the security-hardening migration (20260207200000).
-- =============================================================================

BEGIN;

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
SET search_path = public, pg_temp
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
    -- Create temp table to store raw accuracy scores (one row per participant)
    DROP TABLE IF EXISTS temp_voting_scores;
    CREATE TEMP TABLE temp_voting_scores (
        participant_id BIGINT,
        accuracy REAL,
        correct_pairs INTEGER,
        total_pairs INTEGER
    );

    -- -------------------------------------------------------------------------
    -- GRID SOURCE (unchanged) — pairwise ordinal accuracy of grid positions.
    -- For each participant who submitted grid rankings, compare every pair of
    -- their ranked propositions against the global MOVDA ordering.
    -- -------------------------------------------------------------------------
    FOR v_user IN
        SELECT DISTINCT gr.participant_id
        FROM grid_rankings gr
        WHERE gr.round_id = p_round_id
        AND gr.participant_id IS NOT NULL
    LOOP
        v_correct := 0;
        v_total := 0;

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

                SELECT COALESCE(pgs.global_score, 50.0) INTO v_global_score_a
                FROM proposition_global_scores pgs
                WHERE pgs.round_id = p_round_id
                AND pgs.proposition_id = v_prop_a.proposition_id;

                SELECT COALESCE(pgs.global_score, 50.0) INTO v_global_score_b
                FROM proposition_global_scores pgs
                WHERE pgs.round_id = p_round_id
                AND pgs.proposition_id = v_prop_b.proposition_id;

                v_global_score_a := COALESCE(v_global_score_a, 50.0);
                v_global_score_b := COALESCE(v_global_score_b, 50.0);

                v_total := v_total + 1;

                IF (v_user_pos_a > v_user_pos_b AND v_global_score_a >= v_global_score_b) OR
                   (v_user_pos_a < v_user_pos_b AND v_global_score_a <= v_global_score_b) OR
                   (v_user_pos_a = v_user_pos_b AND v_global_score_a = v_global_score_b) THEN
                    v_correct := v_correct + 1;
                END IF;
            END LOOP;
        END LOOP;

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

    -- -------------------------------------------------------------------------
    -- PAIRWISE SOURCE (new) — matches-mode accuracy.
    -- Aggregate each voter's non-skip comparisons: a non-tie is correct when
    -- the chosen winner's global_score >= the loser's; a tie is correct when
    -- the two global_scores are within epsilon (|diff| < 1.0). Missing scores
    -- COALESCE to 50.0 to mirror the grid path.
    -- -------------------------------------------------------------------------
    DROP TABLE IF EXISTS temp_pairwise_scores;
    CREATE TEMP TABLE temp_pairwise_scores AS
    SELECT
        pc.participant_id AS participant_id,
        SUM(
            CASE
                WHEN COALESCE(pc.is_tie, FALSE) THEN
                    CASE WHEN ABS(COALESCE(ws.global_score, 50.0) - COALESCE(ls.global_score, 50.0)) < 1.0
                         THEN 1 ELSE 0 END
                ELSE
                    CASE WHEN COALESCE(ws.global_score, 50.0) >= COALESCE(ls.global_score, 50.0)
                         THEN 1 ELSE 0 END
            END
        )::INTEGER AS correct_pairs,
        COUNT(*)::INTEGER AS total_pairs
    FROM pairwise_comparisons pc
    LEFT JOIN proposition_global_scores ws
        ON ws.round_id = p_round_id AND ws.proposition_id = pc.winner_proposition_id
    LEFT JOIN proposition_global_scores ls
        ON ls.round_id = p_round_id AND ls.proposition_id = pc.loser_proposition_id
    WHERE pc.round_id = p_round_id
      AND pc.participant_id IS NOT NULL
      AND COALESCE(pc.is_skip, FALSE) = FALSE
    GROUP BY pc.participant_id;

    -- Participants who voted in BOTH sources (defensive — not expected per round):
    -- union their per-vote counts so each cast vote counts once, then recompute
    -- the combined accuracy.
    UPDATE temp_voting_scores t
    SET correct_pairs = t.correct_pairs + ps.correct_pairs,
        total_pairs   = t.total_pairs + ps.total_pairs,
        accuracy = CASE
            WHEN (t.total_pairs + ps.total_pairs) = 0 THEN 100.0
            ELSE ((t.correct_pairs + ps.correct_pairs)::REAL
                  / (t.total_pairs + ps.total_pairs)::REAL) * 100.0
        END
    FROM temp_pairwise_scores ps
    WHERE ps.participant_id = t.participant_id;

    -- Pairwise-only participants (no grid row): insert fresh accuracy.
    INSERT INTO temp_voting_scores (participant_id, accuracy, correct_pairs, total_pairs)
    SELECT
        ps.participant_id,
        CASE WHEN ps.total_pairs = 0 THEN 100.0
             ELSE (ps.correct_pairs::REAL / ps.total_pairs::REAL) * 100.0 END,
        ps.correct_pairs,
        ps.total_pairs
    FROM temp_pairwise_scores ps
    WHERE NOT EXISTS (
        SELECT 1 FROM temp_voting_scores t WHERE t.participant_id = ps.participant_id
    );

    DROP TABLE IF EXISTS temp_pairwise_scores;

    -- -------------------------------------------------------------------------
    -- NORMALIZE (unchanged) — min-max across all voters in the round.
    -- -------------------------------------------------------------------------
    SELECT MIN(t.accuracy), MAX(t.accuracy)
    INTO v_min_accuracy, v_max_accuracy
    FROM temp_voting_scores t;

    FOR v_user IN
        SELECT * FROM temp_voting_scores
    LOOP
        participant_id := v_user.participant_id;
        correct_pairs := v_user.correct_pairs;
        total_pairs := v_user.total_pairs;

        IF v_max_accuracy IS NULL OR v_min_accuracy IS NULL THEN
            rank := NULL;
        ELSIF v_max_accuracy = v_min_accuracy THEN
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
'Calculates voting accuracy rank for all participants in a round, across BOTH
rating modes:
- Grid mode: pairwise ordinal accuracy of grid positions vs global MOVDA scores.
- Matches (pairwise) mode: a non-skip comparison is correct when the chosen
  winner''s global_score >= the loser''s; a tie is correct when the two scores
  are within epsilon (|diff| < 1.0). Skips are ignored.
A participant who voted via either source gets a rank; both sources union their
per-vote counts so no vote is double-counted.
NORMALIZED: best voter in round = 100, worst = 0; all-equal = 100.';

COMMIT;
