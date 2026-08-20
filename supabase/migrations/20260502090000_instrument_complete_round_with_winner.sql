-- =============================================================================
-- Instrument complete_round_with_winner with stage-level timing.
-- =============================================================================
-- Stress runs at 20 bots show grid_rankings INSERT statements taking up to
-- 7.98s under load — right at the 8s statement_timeout. pg_stat_statements
-- attributes the time to the outer INSERT (since the trigger fires inside
-- it) and pg_stat_user_functions is disabled on Supabase by default, so we
-- can't see which stage of the round-close is the actual hot path.
--
-- This migration wraps each stage with clock_timestamp() boundaries and
-- inserts a row per stage into perf_logs (the same observability table
-- the Flutter PerfLogger writes into). The correlation_id ties every
-- stage of one round-close together so we can reconstruct the timeline:
--
--   SELECT phase, action, duration_ms
--   FROM perf_logs
--   WHERE correlation_id = '<id>'
--   ORDER BY created_at;
--
-- Behaviour is unchanged — log writes go through public.log_perf which
-- swallows exceptions, so a logging failure can't break a round-close.
-- The only added cost is ~0.1ms per stage for the INSERT, which is
-- negligible compared to the heavy work we're trying to measure.
-- =============================================================================

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
    v_corr UUID := gen_random_uuid();
    v_start TIMESTAMPTZ := clock_timestamp();
    v_stage_start TIMESTAMPTZ;
    v_chat_id BIGINT;
BEGIN
    SELECT * INTO v_round FROM rounds WHERE id = p_round_id;

    IF v_round IS NULL OR v_round.completed_at IS NOT NULL THEN
        -- Bail with a tiny telemetry breadcrumb so we can see how often
        -- this no-op fires (e.g. concurrent triggers re-acquiring the
        -- advisory lock after the winner has already been selected).
        SELECT cy.chat_id INTO v_chat_id
        FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
        WHERE r.id = p_round_id;
        PERFORM public.log_perf(
            p_correlation_id := v_corr,
            p_source         := 'db_func',
            p_action         := 'complete_round.bail_already_done',
            p_phase          := 'end',
            p_duration_ms    := EXTRACT(EPOCH FROM (clock_timestamp() - v_start))::INT * 1000,
            p_chat_id        := v_chat_id,
            p_round_id       := p_round_id
        );
        RETURN;
    END IF;

    SELECT cy.chat_id INTO v_chat_id
    FROM cycles cy
    WHERE cy.id = v_round.cycle_id;

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round',
        p_phase          := 'start',
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    -- Stage 1: MOVDA score calculation
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

    -- Stage 2: User rank computation
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

    -- Stage 3: Winner selection + INSERT round_winners
    v_stage_start := clock_timestamp();
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
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.winner_insert',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    -- Stage 4: UPDATE rounds — fires on_round_winner_set trigger which
    -- creates the next round, carries forward winners, funds participants,
    -- and may auto-skip stranded raters. This is the chain we suspect is
    -- the worst offender; isolating its time matters.
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

COMMENT ON FUNCTION public.complete_round_with_winner(bigint) IS
'Closes a round, computes MOVDA scores, and records the winner(s) in '
'round_winners. Sets rounds.is_sole_winner = TRUE only when no other '
'proposition has a global_score within convergence_tie_tolerance() of '
'the top — the same tolerance the rating-results UI uses to cluster '
'near-tied cards. Stage timings are logged to perf_logs via log_perf '
'with a shared correlation_id so a single round-close timeline can be '
'reconstructed. See migration 20260502090000.';
