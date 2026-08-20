-- Proposing early-advance: count "acted" (submitted OR skipped OR affirmed) toward the
-- COUNT threshold, not just submitters.
--
-- Before: the proposing phase advanced only when `unique_submitters >= proposing_threshold_count`,
-- so a participant who SKIPPED (or affirmed) didn't count toward that threshold — the phase kept
-- waiting on someone who'd already explicitly acted, falling through to the timer. The PERCENT
-- threshold already counted skips+affirms (v_participated_count); this aligns the COUNT threshold
-- with the same "has acted" set, so the phase advances as soon as everyone has acted.
--
-- v_minimum_met is unchanged and still independently requires `proposing_minimum` real new
-- propositions, so this cannot advance to rating with fewer ideas than before (the all-skip
-- degenerate case behaves exactly as the percent-threshold path already does today).
--
-- Bodies are the live prod definitions (pulled 2026-05-30); only the v_count_met line changes.

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
    v_min_end TIMESTAMPTZ;
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
            v_now := NOW();
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
    v_min_end TIMESTAMPTZ;
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
            v_now := NOW();
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
$function$;

COMMENT ON FUNCTION public.check_early_advance_on_proposition() IS
    'Proposing early-advance on new proposition. Count threshold now counts acted (submitted/skipped/affirmed), aligned with the percent threshold; minimum still gates on real propositions.';
COMMENT ON FUNCTION public.check_early_advance_on_skip() IS
    'Proposing early-advance on skip. Count threshold now counts acted (submitted/skipped/affirmed), aligned with the percent threshold; minimum still gates on real propositions.';
