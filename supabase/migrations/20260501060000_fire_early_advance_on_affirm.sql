-- =============================================================================
-- MIGRATION: Fire the proposing early-advance check on affirmation insert
-- =============================================================================
-- The earlier affirmations migration (20260430180000) updated the existing
-- check_early_advance_on_proposition / check_early_advance_on_skip trigger
-- functions to count affirmers in participation totals, but did not attach
-- a trigger to the affirmations table itself. As a result, when the LAST
-- action in a proposing round is an affirmation (e.g. 1 sub + 2 affirms,
-- with affirms inserted after the sub), the threshold check never runs
-- and the round is stuck in proposing despite all participants having
-- acted.
--
-- Fix: add a thin shim function that delegates to the same advance logic
-- used by the proposition / skip triggers, and attach it AFTER INSERT on
-- affirmations. Logic is identical — copying the body keeps the advisory
-- lock + threshold math in one place we already trust.
--
-- The pre-existing maybe_auto_resolve_affirm_round trigger keeps handling
-- the all-affirm + zero-submissions auto-resolve path. This new trigger
-- handles the "mixed but enough" path (≥1 submission, all participants
-- accounted for) so the round advances to rating phase.
--
-- Concrete failure (chat 304 round 2392): 3 participants, 1 submitted, 2
-- affirmed (after the submission). Round stuck in proposing with no
-- further action available to users.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.check_early_advance_on_affirmation()
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

    -- Re-check phase under lock; another concurrent transaction may have
    -- already advanced or auto-resolved the round.
    SELECT phase INTO v_round.phase FROM public.rounds WHERE id = NEW.round_id;
    IF v_round.phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    -- maybe_auto_resolve_affirm_round runs first (also AFTER INSERT on
    -- affirmations) and may have set a winner already. If a winner is in
    -- place, do not also advance to rating — the round is finished.
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
    v_count_met := v_unique_submitters >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    RAISE NOTICE '[EARLY ADVANCE ON AFFIRM] Round %: % subs + % skips + % affirms = % participated (need %). Count: % (need %). Min: % (need %). Funded: %.',
        NEW.round_id, v_unique_submitters, v_skip_count, v_affirm_count, v_participated_count, v_percent_required,
        v_unique_submitters, v_effective_count_threshold,
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
$$;

ALTER FUNCTION public.check_early_advance_on_affirmation() OWNER TO postgres;

COMMENT ON FUNCTION public.check_early_advance_on_affirmation IS
'AFTER INSERT trigger on affirmations. Mirrors check_early_advance_on_proposition
and check_early_advance_on_skip — runs the same threshold math after an
affirmation is recorded so a round advances to rating phase as soon as
all participants have acted (mix of submit + skip + affirm). The
maybe_auto_resolve_affirm_round trigger handles the all-affirm-zero-sub
case separately and is checked here via round_winners existence.';

DROP TRIGGER IF EXISTS trg_check_early_advance_on_affirmation ON public.affirmations;
CREATE TRIGGER trg_check_early_advance_on_affirmation
AFTER INSERT ON public.affirmations
FOR EACH ROW
EXECUTE FUNCTION public.check_early_advance_on_affirmation();

COMMIT;

-- =============================================================================
-- ROLLBACK (reference):
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_check_early_advance_on_affirmation ON public.affirmations;
-- DROP FUNCTION IF EXISTS public.check_early_advance_on_affirmation();
-- COMMIT;
-- =============================================================================
