-- =============================================================================
-- Quick rooms have NO "all participants done" concept — never auto-resolve.
-- =============================================================================
-- Quick chats (max_cycles = 1) are OPEN rooms: anyone with the link can arrive
-- at any time, so there is no fixed membership set. That makes "everyone has
-- responded" (affirmation_count + skip_count >= active_count) meaningless —
-- the denominator (the room's "members") does not exist; the upper bound is
-- undefined. Only the HOST knows when a quick room is done.
--
-- The affirmation feature's AFTER-INSERT trigger (maybe_auto_resolve_affirm_round)
-- auto-resolves a round once "everyone" has affirmed/skipped — exactly the
-- bounded-membership logic that doesn't apply to open rooms. So in the wedge,
-- recording a no-challenge as an affirmation (a counted "response", so the host
-- can tell "they're keeping it" from "nobody's here") must NOT trigger that
-- auto-resolve.
--
-- Fix: maybe_auto_resolve_affirm_round bails immediately for quick chats
-- (max_cycles = 1). Affirmations are still recorded (they count as responses);
-- the round only advances when the host acts. Continuous chats (wizard-created,
-- max_cycles IS NULL) are UNTOUCHED — they keep the all-affirm auto-resolve.
--
-- Note: current Flutter quick chats are confirmation_rounds_required = 1, so
-- they seal at round 1 and never reach a round-2 proposing/affirm phase — this
-- guard is a no-op for them today. It matters for the wedge's convergence
-- on-ramp (confirmation_rounds_required = 2), where round 2 IS a proposing
-- (challenge) phase that accepts affirmations.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.maybe_auto_resolve_affirm_round()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round_id BIGINT := NEW.round_id;
    v_chat_id BIGINT;
    v_phase TEXT;
    v_max_cycles INT;
    v_active_count INT;
    v_new_submissions INT;
    v_skip_count INT;
    v_affirmation_count INT;
    v_carried_id BIGINT;
BEGIN
    -- Serialize per-round.
    PERFORM pg_advisory_xact_lock(v_round_id);

    -- Re-check phase under lock. If a sibling transaction already advanced
    -- the round (or set a winner), bail.
    SELECT r.phase, cy.chat_id, c.max_cycles
      INTO v_phase, v_chat_id, v_max_cycles
    FROM public.rounds r
    JOIN public.cycles cy ON cy.id = r.cycle_id
    JOIN public.chats c ON c.id = cy.chat_id
    WHERE r.id = v_round_id;

    -- Open quick room: no membership upper bound, so "everyone responded" is
    -- undefined. Host decides when it ends — never auto-resolve. The affirmation
    -- row stays (it counts as a response).
    IF v_max_cycles = 1 THEN
        RETURN NEW;
    END IF;

    IF v_phase != 'proposing' THEN
        RETURN NEW;
    END IF;

    IF EXISTS (SELECT 1 FROM public.round_winners WHERE round_id = v_round_id) THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(*) INTO v_active_count
    FROM public.participants
    WHERE chat_id = v_chat_id AND status = 'active';

    SELECT COUNT(*) INTO v_new_submissions
    FROM public.propositions
    WHERE round_id = v_round_id
      AND carried_from_id IS NULL
      AND participant_id IS NOT NULL;

    SELECT COUNT(*) INTO v_skip_count
    FROM public.round_skips
    WHERE round_id = v_round_id;

    SELECT COUNT(*) INTO v_affirmation_count
    FROM public.affirmations
    WHERE round_id = v_round_id;

    -- Only resolve when EVERYONE acted via affirm/skip and no one submitted.
    -- Mixing in a single submission means a normal advance is appropriate
    -- (the existing early-advance trigger will handle it once thresholds
    -- are met). But even one submission means we can't claim the carried
    -- winner won unchallenged — let the rating phase decide.
    IF v_new_submissions != 0 THEN
        RETURN NEW;
    END IF;

    IF v_affirmation_count + v_skip_count < v_active_count THEN
        RETURN NEW;
    END IF;

    -- An affirmation was just inserted, so we need at least one (otherwise
    -- the user-without-affirms-or-submissions path could resolve too).
    IF v_affirmation_count = 0 THEN
        RETURN NEW;
    END IF;

    -- Find the carried-forward proposition. There should be exactly one
    -- (carry-forward picks the previous round's sole winner).
    SELECT id INTO v_carried_id
    FROM public.propositions
    WHERE round_id = v_round_id
      AND carried_from_id IS NOT NULL
    ORDER BY created_at ASC
    LIMIT 1;

    IF v_carried_id IS NULL THEN
        -- No carried-forward exists — should not happen in R2+, but bail safely.
        RETURN NEW;
    END IF;

    PERFORM public.resolve_carried_winner_for_round(v_round_id, v_carried_id);

    RETURN NEW;
END;
$function$;
