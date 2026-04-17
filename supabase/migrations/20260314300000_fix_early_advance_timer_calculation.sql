-- Fix phase_ends_at calculation in early advance triggers
--
-- BUG: Both check_early_advance_on_skip() and check_early_advance_on_proposition()
-- calculated phase_ends_at as:
--   date_trunc('minute', NOW()) + INTERVAL '1 minute' * CEIL(duration / 60.0)
--
-- This truncates NOW() to the start of the current minute BEFORE adding the
-- duration, producing a timer as short as 1 second when the trigger fires
-- late in a minute (e.g. at :55, timer = 5 seconds instead of ~65 seconds).
--
-- FIX: Add duration to NOW() first, then round up to the next minute boundary.
-- This matches the calculateRoundMinuteEnd() logic in process-timers.

-- =============================================================================
-- Fix check_early_advance_on_skip
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_early_advance_on_skip()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_funded_count INTEGER;
    v_proposition_count INTEGER;
    v_skip_count INTEGER;
    v_unique_submitters INTEGER;
    v_participated_count INTEGER;
    v_max_possible INTEGER;
    v_percent_required INTEGER;
    v_effective_count_threshold INTEGER;
    v_percent_met BOOLEAN;
    v_count_met BOOLEAN;
    v_minimum_met BOOLEAN;
    v_now TIMESTAMPTZ;
    v_phase_ends_at TIMESTAMPTZ;
    v_min_end TIMESTAMPTZ;
BEGIN
    -- Get round info
    SELECT * INTO v_round
    FROM public.rounds
    WHERE id = NEW.round_id;

    -- Only check during proposing phase
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM public.chats
    WHERE id = (SELECT chat_id FROM public.cycles WHERE id = v_round.cycle_id);

    -- Skip if no proposing threshold configured
    IF v_chat.proposing_threshold_count IS NULL AND v_chat.proposing_threshold_percent IS NULL THEN
        RETURN NEW;
    END IF;

    -- Use FUNDED participant count
    v_funded_count := public.get_funded_participant_count(NEW.round_id);

    IF v_funded_count = 0 THEN
        SELECT COUNT(*) INTO v_funded_count
        FROM public.participants
        WHERE chat_id = v_chat.id AND status = 'active';
    END IF;

    -- Count skips for this round (including the one just inserted)
    SELECT COUNT(*) INTO v_skip_count
    FROM public.round_skips
    WHERE round_id = NEW.round_id;

    -- Count NEW HUMAN propositions only
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    -- Count unique human submitters
    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    v_participated_count := v_unique_submitters + v_skip_count;
    v_max_possible := v_funded_count - v_skip_count;

    IF v_chat.proposing_threshold_percent IS NOT NULL THEN
        v_percent_required := CEIL(v_funded_count * v_chat.proposing_threshold_percent / 100.0);
    ELSE
        v_percent_required := 0;
    END IF;

    IF v_chat.proposing_threshold_count IS NOT NULL THEN
        v_effective_count_threshold := LEAST(v_chat.proposing_threshold_count, v_max_possible);
    ELSE
        v_effective_count_threshold := 0;
    END IF;

    v_percent_met := v_participated_count >= v_percent_required;
    v_count_met := v_unique_submitters >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    RAISE NOTICE '[EARLY ADVANCE ON SKIP] Round %: % submitters + % skips = % participated (need %). Count: % (need %). Min: % (need %). Funded: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_participated_count, v_percent_required,
        v_unique_submitters, v_effective_count_threshold,
        v_proposition_count, LEAST(v_chat.proposing_minimum, v_max_possible),
        v_funded_count;

    IF v_percent_met AND v_count_met AND v_minimum_met THEN
        IF v_chat.rating_start_mode = 'auto' THEN
            v_now := NOW();
            -- Add duration first, then round up to next minute boundary
            -- (matches calculateRoundMinuteEnd in process-timers)
            v_min_end := v_now + INTERVAL '1 second' * v_chat.rating_duration_seconds;
            IF EXTRACT(SECOND FROM v_min_end) = 0 THEN
                v_phase_ends_at := v_min_end;
            ELSE
                v_phase_ends_at := date_trunc('minute', v_min_end) + INTERVAL '1 minute';
            END IF;

            UPDATE public.rounds
            SET phase = 'rating',
                phase_started_at = v_now,
                phase_ends_at = v_phase_ends_at
            WHERE id = NEW.round_id;
        ELSE
            UPDATE public.rounds
            SET phase = 'waiting',
                phase_started_at = NULL,
                phase_ends_at = NULL
            WHERE id = NEW.round_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- =============================================================================
-- Fix check_early_advance_on_proposition
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_early_advance_on_proposition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_funded_count INTEGER;
    v_proposition_count INTEGER;
    v_skip_count INTEGER;
    v_unique_submitters INTEGER;
    v_participated_count INTEGER;
    v_max_possible INTEGER;
    v_percent_required INTEGER;
    v_effective_count_threshold INTEGER;
    v_percent_met BOOLEAN;
    v_count_met BOOLEAN;
    v_minimum_met BOOLEAN;
    v_now TIMESTAMPTZ;
    v_phase_ends_at TIMESTAMPTZ;
    v_min_end TIMESTAMPTZ;
BEGIN
    -- Get round info
    SELECT * INTO v_round
    FROM public.rounds
    WHERE id = NEW.round_id;

    -- Only check during proposing phase
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM public.chats
    WHERE id = (SELECT chat_id FROM public.cycles WHERE id = v_round.cycle_id);

    -- Skip if no proposing threshold configured
    IF v_chat.proposing_threshold_count IS NULL AND v_chat.proposing_threshold_percent IS NULL THEN
        RETURN NEW;
    END IF;

    -- Use FUNDED participant count (unfunded spectators don't count toward thresholds)
    v_funded_count := public.get_funded_participant_count(NEW.round_id);

    -- Fallback: if no funding records yet, use active count (backward compat)
    IF v_funded_count = 0 THEN
        SELECT COUNT(*) INTO v_funded_count
        FROM public.participants
        WHERE chat_id = v_chat.id AND status = 'active';
    END IF;

    -- Count skips for this round
    SELECT COUNT(*) INTO v_skip_count
    FROM public.round_skips
    WHERE round_id = NEW.round_id;

    -- Count NEW HUMAN propositions only (exclude carried forward AND AI)
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    -- Count unique human submitters
    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    -- Participated = unique submitters + skippers
    v_participated_count := v_unique_submitters + v_skip_count;

    -- Max possible submissions (can't have more submitters than non-skippers)
    v_max_possible := v_funded_count - v_skip_count;

    -- Calculate percent-based requirement (rounded up)
    IF v_chat.proposing_threshold_percent IS NOT NULL THEN
        v_percent_required := CEIL(v_funded_count * v_chat.proposing_threshold_percent / 100.0);
    ELSE
        v_percent_required := 0;
    END IF;

    -- Count-based requirement with dynamic adjustment for skips
    IF v_chat.proposing_threshold_count IS NOT NULL THEN
        v_effective_count_threshold := LEAST(v_chat.proposing_threshold_count, v_max_possible);
    ELSE
        v_effective_count_threshold := 0;
    END IF;

    -- Check BOTH thresholds independently (AND, not LEAST/GREATEST)
    v_percent_met := v_participated_count >= v_percent_required;
    v_count_met := v_unique_submitters >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    RAISE NOTICE '[EARLY ADVANCE] Round %: % submitters + % skips = % participated (need %). Count: % (need %). Min: % (need %). Funded: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_participated_count, v_percent_required,
        v_unique_submitters, v_effective_count_threshold,
        v_proposition_count, LEAST(v_chat.proposing_minimum, v_max_possible),
        v_funded_count;

    -- ALL three checks must pass
    IF v_percent_met AND v_count_met AND v_minimum_met THEN
        IF v_chat.rating_start_mode = 'auto' THEN
            -- Auto-advance to rating phase
            v_now := NOW();
            -- Add duration first, then round up to next minute boundary
            -- (matches calculateRoundMinuteEnd in process-timers)
            v_min_end := v_now + INTERVAL '1 second' * v_chat.rating_duration_seconds;
            IF EXTRACT(SECOND FROM v_min_end) = 0 THEN
                v_phase_ends_at := v_min_end;
            ELSE
                v_phase_ends_at := date_trunc('minute', v_min_end) + INTERVAL '1 minute';
            END IF;

            RAISE NOTICE '[EARLY ADVANCE] Advancing round % to rating. % human props, % funded participants.',
                NEW.round_id, v_proposition_count, v_funded_count;

            UPDATE public.rounds
            SET phase = 'rating',
                phase_started_at = v_now,
                phase_ends_at = v_phase_ends_at
            WHERE id = NEW.round_id;
        ELSE
            -- Manual rating start mode: go to waiting phase
            RAISE NOTICE '[EARLY ADVANCE] Round % waiting for manual rating start.',
                NEW.round_id;

            UPDATE public.rounds
            SET phase = 'waiting',
                phase_started_at = NULL,
                phase_ends_at = NULL
            WHERE id = NEW.round_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
