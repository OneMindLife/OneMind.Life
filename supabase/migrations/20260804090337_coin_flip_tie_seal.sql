-- Coin-flip tie-break for Instant-mode rounds.
--
-- The bug (observed on GLOBAL / chat 1269, 2026-08-04): two people split their
-- votes 1-1, the round tied at the top (both scored 50, is_sole_winner=false),
-- and complete_round_with_winner did two contradictory things:
--   1. stamped ONE tied idea as the round's winning_proposition_id (the feed
--      then shows it as a settled permanent message), AND
--   2. left is_sole_winner=false so the cycle did NOT seal -- instead every
--      rank-1 winner carried into a fresh "tiebreaker" round.
-- That tiebreaker round can only open voting once it has >=2 NEW propositions,
-- so in an empty room it extends its timer forever. Net effect: an idea shown
-- as "won" in the permanent chat while its round is simultaneously stuck being
-- re-contested. Incoherent, and a permanent freeze with nobody present.
--
-- Fix (Instant mode only): a tie is broken by an actual coin flip. Pick ONE of
-- the tied-top ideas uniformly at random, mark it the sole winner, and let
-- Instant mode (confirmation_rounds_required = 1) crown it immediately. No
-- tiebreaker round is created, so the empty-room freeze cannot happen, and the
-- feed's winner is the real, sealed outcome.
--
-- Scope: ONLY confirmation_rounds_required = 1 (Instant). Convergence mode
-- (>= 2) deliberately keeps re-contesting ties across rounds -- a repeated
-- mandate shouldn't be granted by a coin flip -- so its behavior and the
-- 102_convergence_tie_tolerance_test contract are unchanged (that test's chat
-- is conf = 2). count_tied_top_propositions, the +/-1.0 tie tolerance, the
-- rank-storage contract (all propositions recorded), and the no-scores
-- fallback are all preserved.
--
-- Everything below the tie branch is identical to the prior version
-- (20260529115515); only the ELSE branch and one lookup changed.

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
    v_conf_rounds INTEGER;
    v_corr UUID := gen_random_uuid();
    v_start TIMESTAMPTZ := clock_timestamp();
    v_stage_start TIMESTAMPTZ;
    v_chat_id BIGINT;
BEGIN
    SELECT * INTO v_round FROM rounds WHERE id = p_round_id;

    IF v_round IS NULL OR v_round.completed_at IS NOT NULL THEN
        SELECT cy.chat_id INTO v_chat_id
        FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
        WHERE r.id = p_round_id;
        PERFORM public.log_perf(
            p_correlation_id := v_corr,
            p_source         := 'db_func',
            p_action         := 'complete_round.bail_already_done',
            p_phase          := 'end',
            p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000)::INT,
            p_chat_id        := v_chat_id,
            p_round_id       := p_round_id
        );
        RETURN;
    END IF;

    -- confirmation_rounds_required decides whether ties coin-flip (Instant) or
    -- re-contest (Convergence). NULL -> 2 so it can never accidentally coin-flip.
    SELECT cy.chat_id, COALESCE(ch.confirmation_rounds_required, 2)
    INTO v_chat_id, v_conf_rounds
    FROM cycles cy
    JOIN chats ch ON ch.id = cy.chat_id
    WHERE cy.id = v_round.cycle_id;

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round',
        p_phase          := 'start',
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    PERFORM calculate_movda_scores_for_round(p_round_id);
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.movda',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    PERFORM store_round_ranks(p_round_id);
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.store_ranks',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    SELECT proposition_id, global_score INTO v_winner_id, v_max_score
    FROM proposition_global_scores
    WHERE round_id = p_round_id
    ORDER BY global_score DESC
    LIMIT 1;

    IF v_winner_id IS NULL THEN
        -- No votes at all: the earliest proposition wins by default (sole).
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
        v_tied_count := count_tied_top_propositions(p_round_id);

        IF v_tied_count > 1 AND v_conf_rounds = 1 THEN
            -- COIN-FLIP TIE-BREAK (Instant mode). Pick one tied-top idea at
            -- random and seal it as THE sole winner. Instant mode then crowns
            -- it immediately (on_round_winner_set), so no tiebreaker round is
            -- created and an empty room cannot freeze.
            SELECT proposition_id INTO v_winner_id
            FROM proposition_global_scores
            WHERE round_id = p_round_id
              AND global_score >= v_max_score - convergence_tie_tolerance()
            ORDER BY random()
            LIMIT 1;

            v_is_sole_winner := TRUE;

            -- Record every proposition (preserves the rank-storage contract),
            -- but force the coin-flip winner to rank 1 so any rank = 1 consumer
            -- (e.g. carry-forward) sees exactly one winner.
            INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
            SELECT p_round_id, proposition_id,
                   ROW_NUMBER() OVER (
                       ORDER BY (proposition_id = v_winner_id) DESC, global_score DESC),
                   global_score
            FROM proposition_global_scores
            WHERE round_id = p_round_id;

            RAISE NOTICE '[COMPLETE ROUND] Coin-flip broke a %-way tie in Instant round %, sealed winner %',
                v_tied_count, p_round_id, v_winner_id;
        ELSE
            -- Sole winner, or a tie in Convergence mode (unchanged: the tie
            -- doesn't seal, all propositions are ranked by score, and the
            -- rank-1 idea(s) re-contest next round).
            v_is_sole_winner := (v_tied_count = 1);

            INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
            SELECT p_round_id, proposition_id,
                   ROW_NUMBER() OVER (ORDER BY global_score DESC),
                   global_score
            FROM proposition_global_scores
            WHERE round_id = p_round_id
            ORDER BY global_score DESC;
        END IF;
    END IF;
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.winner_insert',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    UPDATE rounds
    SET winning_proposition_id = v_winner_id,
        is_sole_winner = v_is_sole_winner,
        completed_at = NOW()
    WHERE id = p_round_id;
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.update_rounds_and_chain',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    RAISE NOTICE '[COMPLETE ROUND] Completed round % with winner %, sole_winner=% (tied within +/-% of top: %)',
        p_round_id, v_winner_id, v_is_sole_winner, convergence_tie_tolerance(), v_tied_count;
END;
$function$;
