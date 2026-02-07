-- =============================================================================
-- MIGRATION: Update Early Advance Trigger to Support Skips
-- =============================================================================
-- Modifies the early advance logic so that:
-- 1. Skippers count toward "participated" for percent-based threshold
-- 2. Count threshold uses dynamic adjustment: MIN(host_setting, max_possible)
--    where max_possible = total_participants - skip_count
-- 3. Also triggers early advance check when someone skips
-- =============================================================================

-- Updated trigger function that counts skips toward participation
CREATE OR REPLACE FUNCTION check_early_advance_on_proposition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_participant_count INTEGER;
    v_proposition_count INTEGER;  -- Count of NEW propositions (not carried forward)
    v_skip_count INTEGER;
    v_participated_count INTEGER;  -- submitters + skippers
    v_unique_submitters INTEGER;
    v_required_count INTEGER;
    v_percent_required INTEGER;
    v_count_required INTEGER;
    v_max_possible INTEGER;
    v_effective_count_threshold INTEGER;
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

    -- Count NEW propositions only (exclude carried forward)
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL;

    -- Count unique submitters (for participation)
    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL;

    -- Participated = unique submitters + skippers
    v_participated_count := v_unique_submitters + v_skip_count;

    -- Calculate max possible submissions (can't have more submitters than non-skippers)
    v_max_possible := v_participant_count - v_skip_count;

    -- Calculate percent-based requirement (rounded up)
    IF v_chat.proposing_threshold_percent IS NOT NULL THEN
        v_percent_required := CEIL(v_participant_count * v_chat.proposing_threshold_percent / 100.0);
    ELSE
        v_percent_required := 0;
    END IF;

    -- Count-based requirement with dynamic adjustment
    -- effective_threshold = MIN(host_setting, max_possible)
    IF v_chat.proposing_threshold_count IS NOT NULL THEN
        v_effective_count_threshold := LEAST(v_chat.proposing_threshold_count, v_max_possible);
    ELSE
        v_effective_count_threshold := 0;
    END IF;

    -- Use GREATEST (the MORE restrictive of percent-based participation and adjusted count)
    -- For percent check: participated >= percent_required
    -- For count check: propositions >= effective_count_threshold
    v_required_count := GREATEST(v_percent_required, v_effective_count_threshold);

    -- Also ensure we meet the absolute minimum (proposing_minimum), adjusted for skips
    v_required_count := GREATEST(v_required_count, LEAST(v_chat.proposing_minimum, v_max_possible));

    RAISE NOTICE '[EARLY ADVANCE CHECK] Round %: % unique submitters, % skips, % participated (vs % percent required). % propositions (vs % effective count threshold). Max possible: %. Required: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_participated_count, v_percent_required,
        v_proposition_count, v_effective_count_threshold, v_max_possible, v_required_count;

    -- Check if thresholds met:
    -- 1. Participated (submitters + skippers) >= percent requirement
    -- 2. Propositions >= effective count threshold
    IF v_participated_count >= v_percent_required AND v_proposition_count >= v_effective_count_threshold THEN
        -- Also verify we meet the adjusted minimum
        IF v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible) THEN
            -- Check rating_start_mode to determine what to do
            IF v_chat.rating_start_mode = 'auto' THEN
                -- Auto-advance to rating phase
                v_now := NOW();
                -- Round up to next minute boundary for cron alignment
                v_phase_ends_at := date_trunc('minute', v_now) +
                                   INTERVAL '1 minute' * CEIL(v_chat.rating_duration_seconds / 60.0);

                RAISE NOTICE '[EARLY ADVANCE] Thresholds met. Advancing round % to rating.',
                    NEW.round_id;

                UPDATE public.rounds
                SET phase = 'rating',
                    phase_started_at = v_now,
                    phase_ends_at = v_phase_ends_at
                WHERE id = NEW.round_id;
            ELSE
                -- Manual rating start mode: go to waiting phase
                RAISE NOTICE '[EARLY ADVANCE] Thresholds met. Round % waiting for manual rating start.',
                    NEW.round_id;

                UPDATE public.rounds
                SET phase = 'waiting',
                    phase_started_at = NULL,
                    phase_ends_at = NULL
                WHERE id = NEW.round_id;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- New trigger function for when someone skips
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
    v_participated_count INTEGER;
    v_unique_submitters INTEGER;
    v_required_count INTEGER;
    v_percent_required INTEGER;
    v_count_required INTEGER;
    v_max_possible INTEGER;
    v_effective_count_threshold INTEGER;
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

    -- Count NEW propositions only (exclude carried forward)
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL;

    -- Count unique submitters
    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL;

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

    v_required_count := GREATEST(v_percent_required, v_effective_count_threshold);
    v_required_count := GREATEST(v_required_count, LEAST(v_chat.proposing_minimum, v_max_possible));

    RAISE NOTICE '[EARLY ADVANCE ON SKIP] Round %: % submitters + % skips = % participated (vs % required). % propositions (vs % effective count). Max possible: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_participated_count, v_percent_required,
        v_proposition_count, v_effective_count_threshold, v_max_possible;

    -- Check thresholds
    IF v_participated_count >= v_percent_required AND v_proposition_count >= v_effective_count_threshold THEN
        IF v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible) THEN
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
    END IF;

    RETURN NEW;
END;
$$;

-- Create trigger for early advance on skip
CREATE TRIGGER check_early_advance_on_skip_trigger
    AFTER INSERT ON public.round_skips
    FOR EACH ROW
    EXECUTE FUNCTION check_early_advance_on_skip();

COMMENT ON FUNCTION check_early_advance_on_proposition IS
'Trigger function that checks if proposing threshold is met after each proposition insert.
Counts skippers toward participation for percent-based threshold.
Uses dynamic count adjustment: effective_threshold = MIN(host_setting, max_possible).
If rating_start_mode=auto: Advances to rating phase immediately.
If rating_start_mode=manual: Goes to waiting phase for host to manually start rating.';

COMMENT ON FUNCTION check_early_advance_on_skip IS
'Trigger function that checks if proposing threshold is met after each skip.
A skip might push participation over the threshold, triggering early advance.';
