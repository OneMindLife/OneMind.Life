-- =============================================================================
-- MIGRATION: Decouple affirm_round from allow_skip_proposing
-- =============================================================================
-- The original affirm_round RPC (20260430180000) reused the
-- allow_skip_proposing chat-config flag to gate affirmation, on the
-- premise that affirm is "skip-style non-submission." With the affirm
-- feature shipped end-to-end (own RPC, own RLS, own auto-resolve trigger)
-- that justification no longer holds: affirm is a positive deliberative
-- signal, distinct from skip ("I'm disengaging").
--
-- Practical impact: chats configured with allow_skip_proposing=false were
-- showing the in-panel textfield instead of the gate, so users had no
-- way to express agreement with the carry-forward winner. Hosts who
-- disable skip-proposing are saying "everyone must engage" — affirm IS
-- engagement, so it should remain available.
--
-- Change: drop the v_allow_skip check from affirm_round. Skip itself
-- continues to honour allow_skip_proposing via the round_skips RLS.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.affirm_round(p_round_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_participant_id BIGINT;
    v_chat_id BIGINT;
    v_phase TEXT;
    v_has_carried BOOLEAN;
    v_my_submissions INT;
    v_already_skipped INT;
    v_affirmation_id BIGINT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- Resolve participant + chat + phase. allow_skip_proposing no longer
    -- gates affirmation (see migration comment above).
    SELECT p.id, p.chat_id, r.phase
      INTO v_participant_id, v_chat_id, v_phase
    FROM public.rounds r
    JOIN public.cycles cy ON cy.id = r.cycle_id
    JOIN public.chats c   ON c.id  = cy.chat_id
    JOIN public.participants p ON p.chat_id = c.id AND p.user_id = v_user_id
    WHERE r.id = p_round_id AND p.status = 'active';

    IF v_participant_id IS NULL THEN
        RAISE EXCEPTION 'not an active participant in this chat'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_phase != 'proposing' THEN
        RAISE EXCEPTION 'can only affirm during proposing phase'
            USING ERRCODE = 'P0002';
    END IF;

    -- Must have a carried-forward proposition (R2+).
    SELECT EXISTS(
        SELECT 1 FROM public.propositions
         WHERE round_id = p_round_id AND carried_from_id IS NOT NULL
    ) INTO v_has_carried;

    IF NOT v_has_carried THEN
        RAISE EXCEPTION 'no previous winner to affirm'
            USING ERRCODE = 'P0004';
    END IF;

    -- Can't affirm if the user already submitted a NEW proposition.
    SELECT COUNT(*) INTO v_my_submissions
    FROM public.propositions
    WHERE round_id = p_round_id
      AND participant_id = v_participant_id
      AND carried_from_id IS NULL;

    IF v_my_submissions > 0 THEN
        RAISE EXCEPTION 'already submitted a proposition, cannot affirm'
            USING ERRCODE = 'P0005';
    END IF;

    -- Can't affirm if the user already skipped (one non-submission action per round).
    SELECT COUNT(*) INTO v_already_skipped
    FROM public.round_skips
    WHERE round_id = p_round_id
      AND participant_id = v_participant_id;

    IF v_already_skipped > 0 THEN
        RAISE EXCEPTION 'already skipped, cannot affirm'
            USING ERRCODE = 'P0006';
    END IF;

    INSERT INTO public.affirmations (round_id, participant_id, user_id)
    VALUES (p_round_id, v_participant_id, v_user_id)
    RETURNING id INTO v_affirmation_id;

    RETURN v_affirmation_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'already affirmed this round'
            USING ERRCODE = 'P0007';
END;
$$;

COMMENT ON FUNCTION public.affirm_round IS
'RPC for affirming the carried-forward winner. As of
20260501070000_decouple_affirm_from_skip_config, no longer requires the
chat to have allow_skip_proposing=true — affirm is a first-class action.
Validates: caller is an active participant; round is in proposing phase;
a carried-forward proposition exists; caller has not submitted or
skipped. Returns the new affirmations.id. Errors carry sqlstate codes
P0001/P0002/P0004-P0007 for client-side mapping (P0003 is no longer
emitted but kept reserved for backwards compatibility).';

COMMIT;

-- =============================================================================
-- Also: guard check_early_advance_on_affirmation against the all-affirm
-- (zero new submissions) path so it yields to maybe_auto_resolve_affirm_round.
--
-- Without the guard the trigger order (alphabetical: 'check_early...' fires
-- before 'maybe_auto_resolve...') would let the early-advance trigger push
-- the round to rating phase with 0 fresh propositions, and the auto-resolve
-- trigger would then short-circuit out because the phase already changed.
-- The guard returns NEW immediately when there are no new submissions but
-- a carried-forward exists — the only path that should auto-resolve.
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
    v_carried_count INTEGER;
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

COMMIT;
