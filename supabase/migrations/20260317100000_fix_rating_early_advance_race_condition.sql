-- =============================================================================
-- MIGRATION: Fix Rating Early Advance Race Condition
-- =============================================================================
-- Fixes a concurrency bug where two participants submitting ratings in
-- overlapping transactions (~500ms apart) causes BOTH triggers to miss the
-- early advance. Each trigger only saw its own transaction's rows due to
-- PostgreSQL MVCC, so done_count was N-1 in both.
--
-- Fix: Add pg_advisory_xact_lock(round_id) to serialize the done-count check.
-- When two triggers fire concurrently for the same round, one blocks until the
-- other's transaction commits. The second trigger then sees all committed rows
-- and correctly advances the round.
--
-- Production evidence: Chat 228 (ASHRIK's Family 3), Round 2074, 2026-03-17.
-- Two agents submitted ratings 567ms apart. Neither trigger advanced.
-- Round completed 2+ minutes later via process-timers cron.
--
-- Affected functions:
--   check_early_advance_on_rating()      — grid_rankings INSERT trigger
--   check_early_advance_on_rating_skip() — rating_skips INSERT trigger
-- =============================================================================


-- 1. check_early_advance_on_rating — add advisory lock
CREATE OR REPLACE FUNCTION check_early_advance_on_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_proposition RECORD;
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_done_count INTEGER;
    v_required INTEGER;
    v_has_funding BOOLEAN;
BEGIN
    -- Get proposition and round info
    SELECT p.*, r.id as round_id, r.phase, r.cycle_id, c.chat_id
    INTO v_proposition
    FROM propositions p
    JOIN rounds r ON r.id = p.round_id
    JOIN cycles c ON c.id = r.cycle_id
    WHERE p.id = NEW.proposition_id;

    -- Only check during rating phase
    IF v_proposition.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM chats
    WHERE id = v_proposition.chat_id;

    -- Skip if no thresholds configured
    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip manual mode
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- =========================================================================
    -- CONCURRENCY FIX: Serialize the done-count check per round.
    -- Without this lock, two concurrent transactions inserting ratings can both
    -- see done_count = N-1 (due to MVCC) and neither advances the round.
    -- The lock ensures the second trigger waits for the first to commit,
    -- then sees all committed rows and correctly counts done_count = N.
    -- =========================================================================
    PERFORM pg_advisory_xact_lock(v_proposition.round_id);

    -- Re-check phase after acquiring lock (another transaction may have advanced)
    SELECT phase INTO v_proposition.phase
    FROM rounds WHERE id = v_proposition.round_id;

    IF v_proposition.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Use FUNDED participant count (unfunded spectators don't count)
    v_total_participants := public.get_funded_participant_count(v_proposition.round_id);
    v_has_funding := v_total_participants > 0;

    -- Fallback: if no funding records, use active count (backward compat for pre-credit rounds)
    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_proposition.chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count participants who are "done":
    -- either skipped rating OR rated all propositions except their own
    -- When funding records exist, only count funded participants.
    -- When no funding records (pre-credit rounds), count all active participants.
    SELECT COUNT(*) INTO v_done_count
    FROM participants p
    WHERE p.chat_id = v_proposition.chat_id AND p.status = 'active'
    -- Only filter by funding when funding records exist
    AND (
        NOT v_has_funding
        OR EXISTS (
            SELECT 1 FROM round_funding rf
            WHERE rf.round_id = v_proposition.round_id AND rf.participant_id = p.id
        )
    )
    AND (
        -- Skipped rating
        EXISTS (
            SELECT 1 FROM rating_skips rs
            WHERE rs.round_id = v_proposition.round_id AND rs.participant_id = p.id
        )
        OR
        -- Rated all propositions except their own
        (
            SELECT COUNT(*) FROM grid_rankings gr
            WHERE gr.participant_id = p.id
            AND gr.proposition_id IN (
                SELECT id FROM propositions WHERE round_id = v_proposition.round_id
            )
        ) >= (
            SELECT COUNT(*) FROM propositions
            WHERE round_id = v_proposition.round_id
            AND (participant_id IS NULL OR participant_id != p.id)
        )
    );

    -- Calculate required threshold
    v_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    -- Cap at total participants
    IF v_required IS NOT NULL AND v_required > v_total_participants THEN
        v_required := v_total_participants;
    END IF;

    IF v_required IS NOT NULL AND v_required < 1 THEN
        v_required := 1;
    END IF;

    -- Check if enough participants are done
    IF v_required IS NOT NULL AND v_done_count >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating threshold met (% done / % required, % funded). Completing round %.',
            v_done_count, v_required, v_total_participants, v_proposition.round_id;

        PERFORM complete_round_with_winner(v_proposition.round_id);
        PERFORM apply_adaptive_duration(v_proposition.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- 2. check_early_advance_on_rating_skip — add advisory lock
CREATE OR REPLACE FUNCTION check_early_advance_on_rating_skip()
RETURNS TRIGGER AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_done_count INTEGER;
    v_required INTEGER;
    v_has_funding BOOLEAN;
BEGIN
    -- Get round info
    SELECT r.*, c.chat_id
    INTO v_round
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = NEW.round_id;

    -- Only check during rating phase
    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM chats
    WHERE id = v_round.chat_id;

    -- Skip if no thresholds configured
    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip manual mode
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- =========================================================================
    -- CONCURRENCY FIX: Same advisory lock as check_early_advance_on_rating.
    -- Serializes rating + rating_skip triggers for the same round.
    -- =========================================================================
    PERFORM pg_advisory_xact_lock(NEW.round_id);

    -- Re-check phase after acquiring lock
    SELECT phase INTO v_round.phase
    FROM rounds WHERE id = NEW.round_id;

    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Use FUNDED participant count
    v_total_participants := public.get_funded_participant_count(NEW.round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_round.chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count participants who are "done"
    -- When funding records exist, only count funded participants.
    -- When no funding records (pre-credit rounds), count all active participants.
    SELECT COUNT(*) INTO v_done_count
    FROM participants p
    WHERE p.chat_id = v_round.chat_id AND p.status = 'active'
    AND (
        NOT v_has_funding
        OR EXISTS (
            SELECT 1 FROM round_funding rf
            WHERE rf.round_id = NEW.round_id AND rf.participant_id = p.id
        )
    )
    AND (
        EXISTS (
            SELECT 1 FROM rating_skips rs
            WHERE rs.round_id = NEW.round_id AND rs.participant_id = p.id
        )
        OR
        (
            SELECT COUNT(*) FROM grid_rankings gr
            WHERE gr.participant_id = p.id
            AND gr.proposition_id IN (
                SELECT id FROM propositions WHERE round_id = NEW.round_id
            )
        ) >= (
            SELECT COUNT(*) FROM propositions
            WHERE round_id = NEW.round_id
            AND (participant_id IS NULL OR participant_id != p.id)
        )
    );

    -- Calculate required threshold
    v_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    IF v_required IS NOT NULL AND v_required > v_total_participants THEN
        v_required := v_total_participants;
    END IF;

    IF v_required IS NOT NULL AND v_required < 1 THEN
        v_required := 1;
    END IF;

    IF v_required IS NOT NULL AND v_done_count >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating skip triggered advance (% done / % required, % funded). Completing round %.',
            v_done_count, v_required, v_total_participants, NEW.round_id;

        PERFORM complete_round_with_winner(NEW.round_id);
        PERFORM apply_adaptive_duration(NEW.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
