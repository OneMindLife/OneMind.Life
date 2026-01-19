-- =============================================================================
-- MIGRATION: Fix complete_round_with_winner to Calculate MOVDA Scores
-- =============================================================================
-- BUG: When rating auto-advances via trigger, MOVDA scores weren't calculated
--      because the trigger was removed for performance. This caused:
--      1. proposition_global_scores to be empty
--      2. round_winners table not populated
--      3. Carried forward propositions not created
--
-- FIX: Call calculate_movda_scores_for_round() at the start of complete_round_with_winner
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

    RAISE NOTICE '[EARLY ADVANCE] Completed round % with winner %, sole_winner=%',
        p_round_id, v_winner_id, v_is_sole_winner;
END;
$$;

COMMENT ON FUNCTION complete_round_with_winner IS
'Completes a round by calculating MOVDA scores, determining the winner,
populating round_winners table, and updating the round. This triggers
on_round_winner_set which handles consensus checking and carry forward.';
