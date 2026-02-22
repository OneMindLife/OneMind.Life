-- Fix early advance logic for rating phase.
-- Previously used avg_raters_per_prop which breaks when participants have uneven
-- proposition counts (e.g. carried forward + new = 2 props for one participant).
-- New approach: count participants who are "done" (finished all their ratings OR skipped),
-- then compare against the threshold.

-- ============================================================
-- 1. Update check_early_advance_on_rating (fires on grid_rankings INSERT)
-- ============================================================
CREATE OR REPLACE FUNCTION check_early_advance_on_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_proposition RECORD;
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_done_count INTEGER;
    v_required INTEGER;
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

    -- Skip manual mode (manual facilitation doesn't use auto-advance)
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- Count active participants
    SELECT COUNT(*) INTO v_total_participants
    FROM participants
    WHERE chat_id = v_proposition.chat_id AND status = 'active';

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count participants who are "done":
    -- either skipped rating OR rated all propositions except their own
    SELECT COUNT(*) INTO v_done_count
    FROM participants p
    WHERE p.chat_id = v_proposition.chat_id AND p.status = 'active'
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

    -- Cap at total participants (can't require more than exist)
    IF v_required IS NOT NULL AND v_required > v_total_participants THEN
        v_required := v_total_participants;
    END IF;

    -- Ensure required doesn't go below 1
    IF v_required IS NOT NULL AND v_required < 1 THEN
        v_required := 1;
    END IF;

    -- Check if enough participants are done
    IF v_required IS NOT NULL AND v_done_count >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating threshold met (% done / % required, % total participants). Completing round %.',
            v_done_count, v_required, v_total_participants, v_proposition.round_id;

        -- Complete the round with winner calculation
        PERFORM complete_round_with_winner(v_proposition.round_id);

        -- Apply adaptive duration for next round (if enabled)
        PERFORM apply_adaptive_duration(v_proposition.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 2. Update check_early_advance_on_rating_skip (fires on rating_skips INSERT)
-- ============================================================
CREATE OR REPLACE FUNCTION check_early_advance_on_rating_skip()
RETURNS TRIGGER AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_done_count INTEGER;
    v_required INTEGER;
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

    -- Count active participants
    SELECT COUNT(*) INTO v_total_participants
    FROM participants
    WHERE chat_id = v_round.chat_id AND status = 'active';

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count participants who are "done":
    -- either skipped rating OR rated all propositions except their own
    SELECT COUNT(*) INTO v_done_count
    FROM participants p
    WHERE p.chat_id = v_round.chat_id AND p.status = 'active'
    AND (
        -- Skipped rating
        EXISTS (
            SELECT 1 FROM rating_skips rs
            WHERE rs.round_id = NEW.round_id AND rs.participant_id = p.id
        )
        OR
        -- Rated all propositions except their own
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

    -- Cap at total participants
    IF v_required IS NOT NULL AND v_required > v_total_participants THEN
        v_required := v_total_participants;
    END IF;

    -- Ensure required doesn't go below 1
    IF v_required IS NOT NULL AND v_required < 1 THEN
        v_required := 1;
    END IF;

    -- Check if enough participants are done
    IF v_required IS NOT NULL AND v_done_count >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating skip triggered advance (% done / % required). Completing round %.',
            v_done_count, v_required, NEW.round_id;

        -- Complete the round with winner calculation
        PERFORM complete_round_with_winner(NEW.round_id);

        -- Apply adaptive duration for next round (if enabled)
        PERFORM apply_adaptive_duration(NEW.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
