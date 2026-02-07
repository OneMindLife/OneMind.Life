-- =============================================================================
-- MIGRATION: Exclude AI Propositions from Auto-Advance Count
-- =============================================================================
-- ISSUE: AI propositions (participant_id IS NULL) were counting toward the
--        proposing threshold, reducing effective human participation requirement.
--
-- FIX: Only count human propositions (participant_id IS NOT NULL) toward the
--      auto-advance threshold. AI propositions are bonus ideas, not substitutes
--      for human participation.
--
-- Example with 3 participants, threshold=3:
--   OLD: 1 AI + 2 humans = 3 → advance (only 67% human participation)
--   NEW: 2 humans = 2 < 3 → don't advance (need 3 humans)
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
    v_threshold_count INTEGER;
    v_threshold_percent INTEGER;
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

    -- Count NEW HUMAN propositions only (exclude carried forward AND AI)
    -- AI propositions (participant_id IS NULL) don't count because:
    -- 1. They're not human participation
    -- 2. "100% participation" should mean 100% of humans
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL      -- Only NEW propositions
      AND participant_id IS NOT NULL;  -- Only HUMAN propositions (exclude AI)

    -- Calculate required count based on thresholds
    v_threshold_count := v_chat.proposing_threshold_count;
    v_threshold_percent := v_chat.proposing_threshold_percent;

    IF v_threshold_percent IS NOT NULL THEN
        v_required_count := CEIL(v_participant_count * v_threshold_percent / 100.0);
    END IF;

    IF v_threshold_count IS NOT NULL THEN
        IF v_required_count IS NULL THEN
            v_required_count := v_threshold_count;
        ELSE
            v_required_count := LEAST(v_required_count, v_threshold_count);
        END IF;
    END IF;

    -- Ensure minimum of proposing_minimum
    v_required_count := GREATEST(v_required_count, v_chat.proposing_minimum);

    -- Check if threshold met
    IF v_proposition_count >= v_required_count THEN
        -- Check rating_start_mode to determine what to do
        IF v_chat.rating_start_mode = 'auto' THEN
            -- Auto-advance to rating phase
            v_now := NOW();
            -- Round up to next minute boundary for cron alignment
            v_phase_ends_at := date_trunc('minute', v_now) +
                               INTERVAL '1 minute' * CEIL(v_chat.rating_duration_seconds / 60.0);

            RAISE NOTICE '[EARLY ADVANCE] Proposing threshold met (% human props of % participants, required %). Advancing round % to rating.',
                v_proposition_count, v_participant_count, v_required_count, NEW.round_id;

            UPDATE public.rounds
            SET phase = 'rating',
                phase_started_at = v_now,
                phase_ends_at = v_phase_ends_at
            WHERE id = NEW.round_id;
        ELSE
            -- Manual rating start mode: go to waiting phase
            -- Host will need to manually start rating
            RAISE NOTICE '[EARLY ADVANCE] Proposing threshold met (% human props of % participants, required %). Round % waiting for manual rating start.',
                v_proposition_count, v_participant_count, v_required_count, NEW.round_id;

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
Only counts NEW HUMAN propositions (excludes carried forward AND AI) to ensure
"100% participation" means 100% of human participants.
If rating_start_mode=auto: Advances to rating phase immediately.
If rating_start_mode=manual: Goes to waiting phase for host to manually start rating.';
