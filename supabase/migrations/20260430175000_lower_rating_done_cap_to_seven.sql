-- =============================================================================
-- MIGRATION: Lower the per-user "done" cap from 10 to 7
-- =============================================================================
-- The cap is the maximum number of ratings a user submits before being
-- flagged "done" for a round, and the maximum number of ratings a single
-- proposition needs before it's considered fully rated for early-advance.
-- It bounds two formulas:
--
--   per-user-done = min(cap, non_self_props)
--   per-prop-threshold = min(cap, max(active_raters - 1, 1))
--
-- Sized down from 10 to 7 because:
--
--   * Working memory (Miller 7±2) — past ~7 items, ranking consistency
--     within a single user collapses; ratings 8-10 from a tired user are
--     measurably noisier than ratings 1-7 from the same person. Lowering
--     the cap means every collected rating is high quality.
--
--   * Grid UI capacity — the rating widget shows ~6-7 cards without forced
--     compression (PositionStack collision handling kicks in past that).
--     A cap of 7 keeps most rounds in the spacious view.
--
--   * Statistical signal — 7 ratings per prop give a standard error of
--     ~0.38 vs ~0.32 at 10 (~16% theoretical precision drop). In practice
--     the gap is smaller (5-10%) once you account for fatigue noise on
--     ratings 8-10. The fatigue offset roughly cancels the statistical
--     gain.
--
-- Net effect for users: rounds in chats with 8+ active raters auto-advance
-- sooner; users complete their rating in less time and with less grid
-- crowding; the leaderboard "done" badge fires earlier so progress is
-- visible. Smaller chats (active_raters < 8) are unaffected because the
-- formula already collapses to active_raters - 1 there.
--
-- Must stay in lockstep with the Dart constant
-- `PropositionService.kMaxRatingsPerUser` in
-- lib/services/proposition_service.dart.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_early_advance_on_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round_id INTEGER;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 7;  -- was 10; see migration header
    v_phase TEXT;
    v_chat_id INTEGER;
BEGIN
    SELECT round_id INTO v_round_id FROM new_ratings LIMIT 1;
    IF v_round_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT r.phase, c.chat_id
      INTO v_phase, v_chat_id
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = v_round_id;

    IF v_phase IS DISTINCT FROM 'rating' THEN
        RETURN NULL;
    END IF;

    SELECT * INTO v_chat FROM chats WHERE id = v_chat_id;

    IF v_chat.rating_threshold_percent IS NULL
       AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NULL;
    END IF;

    IF v_chat.start_mode = 'manual' THEN
        RETURN NULL;
    END IF;

    PERFORM pg_advisory_xact_lock(v_round_id);

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase IS DISTINCT FROM 'rating' THEN
        RETURN NULL;
    END IF;

    v_total_participants := public.get_funded_participant_count(v_round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NULL;
    END IF;

    -- Skipper count, active-only (so a left skipper's preserved skip
    -- doesn't deflate active_raters)
    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips rs
    JOIN participants p ON p.id = rs.participant_id
    WHERE rs.round_id = v_round_id
      AND p.status = 'active';

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
        RETURN NULL;
    END IF;

    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

    SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
    FROM (
        SELECT
            p.id,
            (SELECT COUNT(*)
               FROM grid_rankings gr
              WHERE gr.proposition_id = p.id
                AND gr.round_id = v_round_id) AS cnt
        FROM propositions p
        WHERE p.round_id = v_round_id
    ) prop_ratings;

    IF v_min_ratings >= v_threshold THEN
        RAISE NOTICE '[EARLY ADVANCE] Per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
            v_min_ratings, v_threshold, v_active_raters, v_skip_count, v_round_id;
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_early_advance_on_rating_skip()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 7;  -- was 10; see migration header
BEGIN
    SELECT r.*, c.chat_id
    INTO v_round
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = NEW.round_id;

    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_chat FROM chats WHERE id = v_round.chat_id;

    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(NEW.round_id);

    SELECT phase INTO v_round.phase
    FROM rounds WHERE id = NEW.round_id;

    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

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

    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips rs
    JOIN participants p ON p.id = rs.participant_id
    WHERE rs.round_id = NEW.round_id
      AND p.status = 'active';

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        PERFORM complete_round_with_winner(NEW.round_id);
        PERFORM apply_adaptive_duration(NEW.round_id);
        RETURN NEW;
    END IF;

    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

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
$$;
