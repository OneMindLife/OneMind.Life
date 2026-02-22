-- =============================================================================
-- MIGRATION: Fix Early Advance Threshold Logic
-- =============================================================================
-- BUGS FIXED:
-- 1. check_early_advance_on_proposition() used LEAST(percent, count) which
--    picks the LOWER threshold. With percent=100% (need 6) and count=3, it
--    picked 3 — allowing advance with only 3/6 participants.
--    FIX: Check both thresholds independently with AND (matching process-timers).
--
-- 2. check_early_advance_on_proposition() lost skip awareness when rewritten
--    in migration 20260125211549. Skips should count toward participation for
--    the percent threshold.
--    FIX: Restore skip-aware logic from 20260123205805.
--
-- 3. check_early_advance_on_skip() didn't exclude AI propositions.
--    FIX: Add participant_id IS NOT NULL filter.
--
-- The corrected logic matches process-timers/checkThresholdsMet():
--   percentMet = (unique_submitters + skip_count) >= CEIL(total * percent / 100)
--   countMet   = unique_submitters >= MIN(count_threshold, max_possible)
--   advance    = percentMet AND countMet AND minimum met
-- =============================================================================

-- =============================================================================
-- STEP 1: Fix check_early_advance_on_proposition()
-- =============================================================================

CREATE OR REPLACE FUNCTION check_early_advance_on_proposition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_participant_count INTEGER;
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

    -- Count active participants
    SELECT COUNT(*) INTO v_participant_count
    FROM public.participants
    WHERE chat_id = v_chat.id AND status = 'active';

    -- Count skips for this round
    SELECT COUNT(*) INTO v_skip_count
    FROM public.round_skips
    WHERE round_id = NEW.round_id;

    -- Count NEW HUMAN propositions only (exclude carried forward AND AI)
    -- AI propositions (participant_id IS NULL) don't count toward threshold
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
    v_max_possible := v_participant_count - v_skip_count;

    -- Calculate percent-based requirement (rounded up)
    IF v_chat.proposing_threshold_percent IS NOT NULL THEN
        v_percent_required := CEIL(v_participant_count * v_chat.proposing_threshold_percent / 100.0);
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
    -- This matches the process-timers checkThresholdsMet() logic
    v_percent_met := v_participated_count >= v_percent_required;
    v_count_met := v_unique_submitters >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    RAISE NOTICE '[EARLY ADVANCE] Round %: % submitters + % skips = % participated (need %). Count: % (need %). Min: % (need %). Percent met: %, Count met: %, Min met: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_participated_count, v_percent_required,
        v_unique_submitters, v_effective_count_threshold,
        v_proposition_count, LEAST(v_chat.proposing_minimum, v_max_possible),
        v_percent_met, v_count_met, v_minimum_met;

    -- ALL three checks must pass
    IF v_percent_met AND v_count_met AND v_minimum_met THEN
        IF v_chat.rating_start_mode = 'auto' THEN
            -- Auto-advance to rating phase
            v_now := NOW();
            v_phase_ends_at := date_trunc('minute', v_now) +
                               INTERVAL '1 minute' * CEIL(v_chat.rating_duration_seconds / 60.0);

            RAISE NOTICE '[EARLY ADVANCE] Advancing round % to rating. % human props, % participants.',
                NEW.round_id, v_proposition_count, v_participant_count;

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

COMMENT ON FUNCTION check_early_advance_on_proposition IS
'Trigger function that checks if proposing threshold is met after each proposition insert.
Checks BOTH percent and count thresholds independently (AND logic):
- Percent: (submitters + skippers) >= CEIL(total * percent / 100)
- Count: unique_submitters >= MIN(count_threshold, max_possible)
- Minimum: propositions >= MIN(proposing_minimum, max_possible)
Only counts NEW HUMAN propositions (excludes carried forward AND AI).
If rating_start_mode=auto: Advances to rating phase immediately.
If rating_start_mode=manual: Goes to waiting phase for host to manually start rating.';

-- =============================================================================
-- STEP 2: Fix check_early_advance_on_skip()
-- =============================================================================

CREATE OR REPLACE FUNCTION check_early_advance_on_skip()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_participant_count INTEGER;
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

    -- Count active participants
    SELECT COUNT(*) INTO v_participant_count
    FROM public.participants
    WHERE chat_id = v_chat.id AND status = 'active';

    -- Count skips for this round (including the one just inserted)
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

    -- Max possible submissions
    v_max_possible := v_participant_count - v_skip_count;

    -- Calculate percent-based requirement
    IF v_chat.proposing_threshold_percent IS NOT NULL THEN
        v_percent_required := CEIL(v_participant_count * v_chat.proposing_threshold_percent / 100.0);
    ELSE
        v_percent_required := 0;
    END IF;

    -- Count-based with dynamic adjustment
    IF v_chat.proposing_threshold_count IS NOT NULL THEN
        v_effective_count_threshold := LEAST(v_chat.proposing_threshold_count, v_max_possible);
    ELSE
        v_effective_count_threshold := 0;
    END IF;

    -- Check BOTH thresholds independently (AND logic)
    v_percent_met := v_participated_count >= v_percent_required;
    v_count_met := v_unique_submitters >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    RAISE NOTICE '[EARLY ADVANCE ON SKIP] Round %: % submitters + % skips = % participated (need %). Count: % (need %). Min: % (need %). Percent met: %, Count met: %, Min met: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_participated_count, v_percent_required,
        v_unique_submitters, v_effective_count_threshold,
        v_proposition_count, LEAST(v_chat.proposing_minimum, v_max_possible),
        v_percent_met, v_count_met, v_minimum_met;

    -- ALL three checks must pass
    IF v_percent_met AND v_count_met AND v_minimum_met THEN
        IF v_chat.rating_start_mode = 'auto' THEN
            v_now := NOW();
            v_phase_ends_at := date_trunc('minute', v_now) +
                               INTERVAL '1 minute' * CEIL(v_chat.rating_duration_seconds / 60.0);

            RAISE NOTICE '[EARLY ADVANCE ON SKIP] Advancing round % to rating.',
                NEW.round_id;

            UPDATE public.rounds
            SET phase = 'rating',
                phase_started_at = v_now,
                phase_ends_at = v_phase_ends_at
            WHERE id = NEW.round_id;
        ELSE
            RAISE NOTICE '[EARLY ADVANCE ON SKIP] Round % waiting for manual rating start.',
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

COMMENT ON FUNCTION check_early_advance_on_skip IS
'Trigger function that checks if proposing threshold is met after each skip insert.
Uses same AND logic as check_early_advance_on_proposition:
- Percent: (submitters + skippers) >= CEIL(total * percent / 100)
- Count: unique_submitters >= MIN(count_threshold, max_possible)
- Minimum: propositions >= MIN(proposing_minimum, max_possible)
A skip might push participation over the percent threshold, triggering early advance.';

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
