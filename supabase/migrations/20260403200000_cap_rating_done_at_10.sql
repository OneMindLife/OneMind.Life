-- =============================================================================
-- MIGRATION: Per-proposition early advance for rating phase
-- =============================================================================
-- Replaces user-done-count model with per-proposition rating coverage model.
--
-- Old: Advance when enough USERS have rated all their propositions.
-- New: Advance when every PROPOSITION has enough ratings.
--
-- Threshold = min(10, max(active_raters - 1, 1))
--   where active_raters = active participants who have NOT skipped rating
--   - active_raters - 1 = max possible raters for any proposition (everyone
--     except the author; skippers can't rate anyone)
--   - Capped at 10 because beyond that, more ratings add diminishing signal
--   - Floor of 1 to avoid advancing with zero ratings
--
-- Advance when: min(rating_count across all propositions) >= threshold
--
-- Preserves:
--   - Advisory locks for concurrency
--   - Funding-aware participant counting
--   - Manual mode bypass
-- =============================================================================


-- 1. check_early_advance_on_rating — fires on grid_rankings INSERT
CREATE OR REPLACE FUNCTION check_early_advance_on_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_proposition RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 10;
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

    -- Serialize per round (concurrency fix)
    PERFORM pg_advisory_xact_lock(v_proposition.round_id);

    -- Re-check phase after acquiring lock
    SELECT phase INTO v_proposition.phase
    FROM rounds WHERE id = v_proposition.round_id;

    IF v_proposition.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Count active participants (funding-aware)
    v_total_participants := public.get_funded_participant_count(v_proposition.round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_proposition.chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count rating skippers (they can't contribute ratings)
    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips
    WHERE round_id = v_proposition.round_id;

    -- Active raters = participants who haven't skipped
    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        -- Everyone skipped — just advance
        PERFORM complete_round_with_winner(v_proposition.round_id);
        PERFORM apply_adaptive_duration(v_proposition.round_id);
        RETURN NEW;
    END IF;

    -- Threshold: min(cap, max(active_raters - 1, 1))
    -- active_raters - 1 because a proposition's author can't rate their own
    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

    -- Find the minimum rating count across all propositions in this round
    SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
    FROM (
        SELECT
            p.id,
            (
                SELECT COUNT(*) FROM grid_rankings gr
                WHERE gr.proposition_id = p.id
                  AND gr.round_id = v_proposition.round_id
            ) AS cnt
        FROM propositions p
        WHERE p.round_id = v_proposition.round_id
    ) prop_ratings;

    -- Advance when every proposition has enough ratings
    IF v_min_ratings >= v_threshold THEN
        RAISE NOTICE '[EARLY ADVANCE] Per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
            v_min_ratings, v_threshold, v_active_raters, v_skip_count, v_proposition.round_id;

        PERFORM complete_round_with_winner(v_proposition.round_id);
        PERFORM apply_adaptive_duration(v_proposition.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- 2. check_early_advance_on_rating_skip — fires on rating_skips INSERT
CREATE OR REPLACE FUNCTION check_early_advance_on_rating_skip()
RETURNS TRIGGER AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 10;
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

    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- Serialize per round
    PERFORM pg_advisory_xact_lock(NEW.round_id);

    -- Re-check phase after lock
    SELECT phase INTO v_round.phase
    FROM rounds WHERE id = NEW.round_id;

    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Count active participants (funding-aware)
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

    -- Count rating skippers
    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips
    WHERE round_id = NEW.round_id;

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        -- Everyone skipped — just advance
        PERFORM complete_round_with_winner(NEW.round_id);
        PERFORM apply_adaptive_duration(NEW.round_id);
        RETURN NEW;
    END IF;

    -- Threshold: min(cap, max(active_raters - 1, 1))
    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

    -- Min rating count across all propositions
    SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
    FROM (
        SELECT
            p.id,
            (
                SELECT COUNT(*) FROM grid_rankings gr
                WHERE gr.proposition_id = p.id
                  AND gr.round_id = NEW.round_id
            ) AS cnt
        FROM propositions p
        WHERE p.round_id = NEW.round_id
    ) prop_ratings;

    IF v_min_ratings >= v_threshold THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating skip — per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
            v_min_ratings, v_threshold, v_active_raters, v_skip_count, NEW.round_id;

        PERFORM complete_round_with_winner(NEW.round_id);
        PERFORM apply_adaptive_duration(NEW.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
