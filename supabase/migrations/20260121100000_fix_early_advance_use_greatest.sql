-- =============================================================================
-- MIGRATION: Fix Early Advance to Use GREATEST (not LEAST) for Thresholds
-- =============================================================================
-- BUG: The trigger was using LEAST(percent_required, count_required)
--      This meant the SMALLER threshold was used, making it too easy to advance.
--
-- FIX: Use GREATEST(percent_required, count_required)
--      The count threshold is a MINIMUM FLOOR, and if the percentage-based
--      calculation is higher, use that instead.
--
-- Example with threshold_count=4, threshold_percent=80%, 3 participants:
--   OLD: LEAST(CEIL(3*80/100)=3, 4) = 3 → advanced with only 3 props!
--   NEW: GREATEST(CEIL(3*80/100)=3, 4) = 4 → need 4 props to advance
--
-- The count threshold ensures a minimum number of propositions regardless
-- of how few participants there are.
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
    v_required_count INTEGER;
    v_percent_required INTEGER;
    v_count_required INTEGER;
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

    -- Count NEW propositions only (exclude carried forward)
    -- Carried forward props don't count because:
    -- 1. They weren't submitted this round
    -- 2. Original author can't rate them, reducing their ratable pool
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL;  -- Only NEW propositions

    -- Calculate required count based on thresholds using GREATEST (MAX)
    -- The count threshold is a MINIMUM FLOOR
    -- If percentage requires more, use the percentage

    -- Calculate percent-based requirement (rounded up)
    IF v_chat.proposing_threshold_percent IS NOT NULL THEN
        v_percent_required := CEIL(v_participant_count * v_chat.proposing_threshold_percent / 100.0);
    ELSE
        v_percent_required := 0;
    END IF;

    -- Count-based requirement (the minimum floor)
    v_count_required := COALESCE(v_chat.proposing_threshold_count, 0);

    -- Use GREATEST (the MORE restrictive of the two)
    v_required_count := GREATEST(v_percent_required, v_count_required);

    -- Also ensure we meet the absolute minimum (proposing_minimum)
    v_required_count := GREATEST(v_required_count, v_chat.proposing_minimum);

    RAISE NOTICE '[EARLY ADVANCE CHECK] Round %: % new props, % participants. Percent requires %, count requires %, using GREATEST = %. Minimum = %.',
        NEW.round_id, v_proposition_count, v_participant_count,
        v_percent_required, v_count_required, GREATEST(v_percent_required, v_count_required),
        v_chat.proposing_minimum;

    -- Check if threshold met
    IF v_proposition_count >= v_required_count THEN
        -- Check rating_start_mode to determine what to do
        IF v_chat.rating_start_mode = 'auto' THEN
            -- Auto-advance to rating phase
            v_now := NOW();
            -- Round up to next minute boundary for cron alignment
            v_phase_ends_at := date_trunc('minute', v_now) +
                               INTERVAL '1 minute' * CEIL(v_chat.rating_duration_seconds / 60.0);

            RAISE NOTICE '[EARLY ADVANCE] Threshold met (% >= %). Advancing round % to rating.',
                v_proposition_count, v_required_count, NEW.round_id;

            UPDATE public.rounds
            SET phase = 'rating',
                phase_started_at = v_now,
                phase_ends_at = v_phase_ends_at
            WHERE id = NEW.round_id;
        ELSE
            -- Manual rating start mode: go to waiting phase
            -- Host will need to manually start rating
            RAISE NOTICE '[EARLY ADVANCE] Threshold met (% >= %). Round % waiting for manual rating start.',
                v_proposition_count, v_required_count, NEW.round_id;

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
Only counts NEW propositions (excludes carried forward).
Uses GREATEST of percent-based and count-based thresholds (the count is a minimum floor).
If rating_start_mode=auto: Advances to rating phase immediately.
If rating_start_mode=manual: Goes to waiting phase for host to manually start rating.';
