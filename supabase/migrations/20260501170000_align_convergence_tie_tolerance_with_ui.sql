-- Align convergence tie-detection tolerance with the frontend's
-- visual stack bucket so that propositions which the UI displays as
-- "clustered together" are also treated as **tied** by the database
-- (no sole winner, no convergence chain advancement).
--
-- ============================================================
-- Background
-- ============================================================
-- Pre-fix: complete_round_with_winner() used strict equality
--   `WHERE global_score = v_max_score`
-- to detect ties. This meant a 0.001-point gap was enough to declare
-- a sole winner — but at the UI level the rating-results screen now
-- groups any propositions within 1.0 global_score points into a
-- single visual stack (commit 229b2f9 — context-aware UI bucket).
--
-- This created a real semantic mismatch: two propositions could
-- visually appear as a single stacked card in the UI while the
-- database recorded one as the "sole winner" of the round, allowing
-- the convergence chain to advance off what was statistically a
-- coin flip.
--
-- Concrete example surfaced by the NCDD Higher Ed Exchange demo
-- (chat 309, 2026-05-01): R1 winner ("ingrained patterns…") and
-- runner-up ("DEI question…") had global scores 100.00 and 99.91
-- respectively — a 0.09-point gap. The UI now groups them; the DB
-- declared the first a sole winner anyway.
--
-- ============================================================
-- The fix
-- ============================================================
-- Tie-detection now uses a tolerance of 1.0 global_score points,
-- matching `RatingStackTolerance.displayBucket` in the Flutter
-- rating widget. Any proposition whose global_score is within 1.0
-- of the maximum is considered tied for first.
--
-- Implications for behavior:
-- - Close races (gap ≤ 1.0) → tie → is_sole_winner = FALSE → does
--   NOT extend the convergence chain. (Previously these would have
--   been declared sole winners on what was statistically noise.)
-- - Clear winners (gap > 1.0) → unchanged.
-- - Convergence is now more conservative — same idea must win two
--   rounds in a row WITH MEANINGFUL margins, not just by coin-flip
--   margins twice.
--
-- Why 1.0:
-- - Matches the UI bucket so visible "clustered" cards = recorded tie.
-- - global_score is a per-round 0–100 percentile, so 1.0 is a
--   relative tolerance that scales with the spread of ratings in
--   the round.
-- - Far enough above floating-point precision noise that exact-tie
--   semantics still work (a true tie of 50.0 vs 50.0 still ties).
--
-- ============================================================
-- Note on retroactivity
-- ============================================================
-- This migration only changes behavior of FUTURE round completions.
-- Past `rounds.is_sole_winner` values are unchanged. The NCDD chat
-- 309 stays converged in the database — only the rule for future
-- rounds gets stricter.

-- Tie-detection tolerance for convergence (in global_score units).
-- Must stay in sync with RatingStackTolerance.displayBucket in
-- lib/widgets/rating/rating_model.dart. Exposed as a function so
-- tests can read the constant rather than hardcoding "1.0".
CREATE OR REPLACE FUNCTION public.convergence_tie_tolerance()
 RETURNS REAL
 LANGUAGE sql IMMUTABLE
AS $function$
    SELECT 1.0::REAL;
$function$;

COMMENT ON FUNCTION public.convergence_tie_tolerance() IS
'Returns the global_score gap below which two propositions are '
'considered tied for first in a round (used by '
'complete_round_with_winner / count_tied_top_propositions). Matches '
'the UI''s display-bucket grouping (RatingStackTolerance.displayBucket '
'in rating_model.dart). See migration 20260501170000.';

-- Counts propositions tied for first place in a round, using the
-- convergence_tie_tolerance() value. Extracted as a separate helper
-- so the tie-detection contract can be unit-tested independently of
-- the MOVDA recomputation that complete_round_with_winner does first.
CREATE OR REPLACE FUNCTION public.count_tied_top_propositions(p_round_id bigint)
 RETURNS INTEGER
 LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_max_score REAL;
    v_count INTEGER;
    v_tolerance REAL := convergence_tie_tolerance();
BEGIN
    SELECT MAX(global_score) INTO v_max_score
    FROM proposition_global_scores
    WHERE round_id = p_round_id;

    IF v_max_score IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*)::INTEGER INTO v_count
    FROM proposition_global_scores
    WHERE round_id = p_round_id
      AND global_score >= v_max_score - v_tolerance;

    RETURN v_count;
END;
$function$;

COMMENT ON FUNCTION public.count_tied_top_propositions(bigint) IS
'Returns the number of propositions whose global_score is within '
'convergence_tie_tolerance() of the round''s top score. Used by '
'complete_round_with_winner to decide is_sole_winner.';

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
        -- Tolerance-based tie detection via the testable helper.
        v_tied_count := count_tied_top_propositions(p_round_id);
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

    RAISE NOTICE '[COMPLETE ROUND] Completed round % with winner %, sole_winner=% (tied within ±% of top: %)',
        p_round_id, v_winner_id, v_is_sole_winner, convergence_tie_tolerance(), v_tied_count;
END;
$function$;

COMMENT ON FUNCTION public.complete_round_with_winner(bigint) IS
'Closes a round, computes MOVDA scores, and records the winner(s) in '
'round_winners. Sets rounds.is_sole_winner = TRUE only when no other '
'proposition has a global_score within convergence_tie_tolerance() of '
'the top — the same tolerance the rating-results UI uses to cluster '
'near-tied cards. See migration 20260501170000.';
