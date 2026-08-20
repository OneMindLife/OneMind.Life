-- Align phase_ends_at to the NEAREST minute boundary, not always the next one.
--
-- PROBLEM
-- Phases can only end on a cron tick (process-timers runs every minute at :00),
-- so phase_ends_at is snapped to a :00 boundary. It was always snapped UP.
-- The cron invocation itself starts a second or two after :00, so a 60s phase
-- computed `now + 60s` = HH:MM:01, which rounded up to HH:MM+1:00 — a 119-second
-- phase for a 60-second config. Observed on chat 1269 (GLOBAL): rating phases
-- alternating between 59s and 119s depending on sub-second cron jitter.
--
-- The three early-advance triggers had it worse: they computed v_min_end from an
-- UN-truncated NOW(), so `EXTRACT(SECOND FROM v_min_end) = 0` was essentially
-- never true (it carries fractional seconds). The "already aligned" branch was
-- unreachable and EVERY early-advanced rating phase ran a full extra minute.
--
-- FIX
-- Snap to the nearer boundary when the overshoot is within
-- PHASE_END_ALIGN_TOLERANCE (15s), otherwise keep rounding up. In practice the
-- overshoot is the cron's own start jitter (0-3s), so phases now run ~59s
-- instead of ~119s. Real cron lag past 15s still rounds up, so a phase is never
-- truncated to a sliver (the bug 79_early_advance_timer_bug_test.sql guards).
-- Never returns a boundary that is already in the past.
--
-- Keep in sync with calculateRoundMinuteEnd() in
-- supabase/functions/process-timers/index.ts.

CREATE OR REPLACE FUNCTION public.calculate_round_minute_end(duration_seconds integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    -- Max seconds we'll shave off a phase to land on the earlier boundary.
    c_tolerance_seconds CONSTANT INTEGER := 15;
    v_now_truncated TIMESTAMPTZ;
    v_min_end TIMESTAMPTZ;
    v_floor TIMESTAMPTZ;
    v_overshoot NUMERIC;
BEGIN
    -- Truncate NOW() to seconds to avoid milliseconds causing extra rounding
    v_now_truncated := date_trunc('second', NOW());
    v_min_end := v_now_truncated + (duration_seconds * INTERVAL '1 second');
    v_overshoot := EXTRACT(SECOND FROM v_min_end);

    -- Already on a :00 boundary — nothing to do.
    IF v_overshoot = 0 THEN
        RETURN v_min_end;
    END IF;

    v_floor := date_trunc('minute', v_min_end);

    -- Within tolerance: snap back to the earlier boundary. Guard against
    -- flooring into the past (possible when duration_seconds <= tolerance).
    IF v_overshoot <= c_tolerance_seconds AND v_floor > NOW() THEN
        RETURN v_floor;
    END IF;

    -- Otherwise round up to the next minute.
    RETURN v_floor + INTERVAL '1 minute';
END;
$function$;

-- =============================================================================
-- Early-advance triggers: delegate to the shared helper.
-- Bodies are the current production definitions with only the inline
-- minute-rounding block replaced (and the now-unused v_min_end declaration
-- dropped).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_early_advance_on_affirmation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_funded_count INTEGER;
    v_proposition_count INTEGER;
    v_skip_count INTEGER;
    v_affirm_count INTEGER;
    v_unique_submitters INTEGER;
    v_participated_count INTEGER;
    v_max_possible INTEGER;
    v_percent_required INTEGER;
    v_effective_count_threshold INTEGER;
    v_percent_met BOOLEAN;
    v_count_met BOOLEAN;
    v_minimum_met BOOLEAN;
    v_carried_count INTEGER;
    v_now TIMESTAMPTZ;
    v_phase_ends_at TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_round FROM public.rounds WHERE id = NEW.round_id;
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_chat FROM public.chats
     WHERE id = (SELECT chat_id FROM public.cycles WHERE id = v_round.cycle_id);

    IF v_chat.proposing_threshold_count IS NULL AND v_chat.proposing_threshold_percent IS NULL THEN
        RETURN NEW;
    END IF;

    -- Yield to maybe_auto_resolve_affirm_round when zero new submissions
    -- exist but a carried-forward does. The other trigger will declare
    -- the carry as the round winner and skip rating phase entirely.
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;
    SELECT COUNT(*) INTO v_carried_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NOT NULL;
    IF v_proposition_count = 0 AND v_carried_count > 0 THEN
        RAISE NOTICE '[EARLY ADVANCE ON AFFIRM] yielding to auto-resolve (0 new subs, carry exists).';
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(NEW.round_id);

    SELECT phase INTO v_round.phase FROM public.rounds WHERE id = NEW.round_id;
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    IF EXISTS (SELECT 1 FROM public.round_winners WHERE round_id = NEW.round_id) THEN
        RETURN NEW;
    END IF;

    v_funded_count := public.get_funded_participant_count(NEW.round_id);
    IF v_funded_count = 0 THEN
        SELECT COUNT(*) INTO v_funded_count
        FROM public.participants
        WHERE chat_id = v_chat.id AND status = 'active';
    END IF;

    SELECT COUNT(*) INTO v_skip_count
    FROM public.round_skips WHERE round_id = NEW.round_id;

    SELECT COUNT(*) INTO v_affirm_count
    FROM public.affirmations WHERE round_id = NEW.round_id;

    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    v_participated_count := v_unique_submitters + v_skip_count + v_affirm_count;
    v_max_possible := v_funded_count - v_skip_count - v_affirm_count;

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

    IF v_percent_met AND v_count_met AND v_minimum_met THEN
        IF v_chat.rating_start_mode = 'auto' THEN
            -- Minute alignment lives in one place now (was inlined here with an
            -- UN-truncated NOW(), so the "= 0" branch was unreachable and every
            -- early-advanced rating phase ran a full extra minute).
            v_now := date_trunc('second', NOW());
            v_phase_ends_at := public.calculate_round_minute_end(v_chat.rating_duration_seconds);

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
$function$;


CREATE OR REPLACE FUNCTION public.check_early_advance_on_proposition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_funded_count INTEGER;
    v_proposition_count INTEGER;
    v_skip_count INTEGER;
    v_affirm_count INTEGER;
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
    SELECT * INTO v_round FROM public.rounds WHERE id = NEW.round_id;
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_chat FROM public.chats
     WHERE id = (SELECT chat_id FROM public.cycles WHERE id = v_round.cycle_id);

    IF v_chat.proposing_threshold_count IS NULL AND v_chat.proposing_threshold_percent IS NULL THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(NEW.round_id);

    SELECT phase INTO v_round.phase FROM public.rounds WHERE id = NEW.round_id;
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    v_funded_count := public.get_funded_participant_count(NEW.round_id);
    IF v_funded_count = 0 THEN
        SELECT COUNT(*) INTO v_funded_count
        FROM public.participants
        WHERE chat_id = v_chat.id AND status = 'active';
    END IF;

    SELECT COUNT(*) INTO v_skip_count
    FROM public.round_skips WHERE round_id = NEW.round_id;

    SELECT COUNT(*) INTO v_affirm_count
    FROM public.affirmations WHERE round_id = NEW.round_id;

    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    -- Affirmers count toward participation alongside submitters and skippers.
    v_participated_count := v_unique_submitters + v_skip_count + v_affirm_count;
    v_max_possible := v_funded_count - v_skip_count - v_affirm_count;

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
    -- Count "acted" (submitted OR skipped OR affirmed), matching v_participated_count, so a
    -- skipper/affirmer doesn't keep the count threshold from being met.
    v_count_met := (v_unique_submitters + v_skip_count + v_affirm_count) >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    RAISE NOTICE '[EARLY ADVANCE] Round %: % submitters + % skips + % affirms = % participated (need %). Count acted: % (need %). Min: % (need %). Funded: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_affirm_count, v_participated_count, v_percent_required,
        v_participated_count, v_effective_count_threshold,
        v_proposition_count, LEAST(v_chat.proposing_minimum, v_max_possible),
        v_funded_count;

    IF v_percent_met AND v_count_met AND v_minimum_met THEN
        IF v_chat.rating_start_mode = 'auto' THEN
            -- Minute alignment lives in one place now (was inlined here with an
            -- UN-truncated NOW(), so the "= 0" branch was unreachable and every
            -- early-advanced rating phase ran a full extra minute).
            v_now := date_trunc('second', NOW());
            v_phase_ends_at := public.calculate_round_minute_end(v_chat.rating_duration_seconds);

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
$function$;


CREATE OR REPLACE FUNCTION public.check_early_advance_on_skip()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_funded_count INTEGER;
    v_proposition_count INTEGER;
    v_skip_count INTEGER;
    v_affirm_count INTEGER;
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
    SELECT * INTO v_round FROM public.rounds WHERE id = NEW.round_id;
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_chat FROM public.chats
     WHERE id = (SELECT chat_id FROM public.cycles WHERE id = v_round.cycle_id);

    IF v_chat.proposing_threshold_count IS NULL AND v_chat.proposing_threshold_percent IS NULL THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(NEW.round_id);

    SELECT phase INTO v_round.phase FROM public.rounds WHERE id = NEW.round_id;
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    v_funded_count := public.get_funded_participant_count(NEW.round_id);
    IF v_funded_count = 0 THEN
        SELECT COUNT(*) INTO v_funded_count
        FROM public.participants
        WHERE chat_id = v_chat.id AND status = 'active';
    END IF;

    SELECT COUNT(*) INTO v_skip_count
    FROM public.round_skips WHERE round_id = NEW.round_id;

    SELECT COUNT(*) INTO v_affirm_count
    FROM public.affirmations WHERE round_id = NEW.round_id;

    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    SELECT COUNT(DISTINCT participant_id) INTO v_unique_submitters
    FROM public.propositions
    WHERE round_id = NEW.round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    v_participated_count := v_unique_submitters + v_skip_count + v_affirm_count;
    v_max_possible := v_funded_count - v_skip_count - v_affirm_count;

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
    -- Count "acted" (submitted OR skipped OR affirmed), matching v_participated_count.
    v_count_met := (v_unique_submitters + v_skip_count + v_affirm_count) >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    IF v_percent_met AND v_count_met AND v_minimum_met THEN
        IF v_chat.rating_start_mode = 'auto' THEN
            -- Minute alignment lives in one place now (was inlined here with an
            -- UN-truncated NOW(), so the "= 0" branch was unreachable and every
            -- early-advanced rating phase ran a full extra minute).
            v_now := date_trunc('second', NOW());
            v_phase_ends_at := public.calculate_round_minute_end(v_chat.rating_duration_seconds);

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
$function$;
