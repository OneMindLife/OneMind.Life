-- =============================================================================
-- Fix: maybe_mark_stranded_raters must use conditional-self-inclusion
-- votability (the third stranded-author site — the 20260704160000 CSI
-- migration updated matches_preview_maybe_finalize and the selection RPCs but
-- missed this trigger).
--
-- OBSERVED BUG (chat 1179 "Test", round 3594, 2026-07-05): 1 human + 1 rating
-- agent, one proposition each. On the proposing→rating flip this trigger
-- counted each participant's NON-OWN props (1 < rating_minimum 2), declared
-- BOTH "stranded", auto-inserted rating_skips for both — which drove
-- active_raters to 0 and the rating-advance trigger's everyone-skipped branch
-- called complete_round_with_winner in the same transaction. Zero votes were
-- cast, so the earliest proposition (the agent's) won by the MOVDA-empty
-- fallback. The human never saw a rating phase.
--
-- Under CSI a participant can rate whenever the round has >= 2 propositions
-- (their own is served when excluding it would leave them under 2), so
-- "stranded" collapses to: the ROUND has fewer than 2 props at all — a
-- per-round condition, not per-participant. rating_minimum no longer belongs
-- in this check: it is a quorum for ADVANCING, not a votability bound (using
-- it here is what made 2-prop rounds instantly self-destruct).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.maybe_mark_stranded_raters()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_round_id BIGINT;
    v_chat_id BIGINT;
    v_prop_count INT;
    v_participant_id BIGINT;
    v_non_own INT;
    v_votable INT;
BEGIN
    v_round_id := NEW.id;

    SELECT cy.chat_id INTO v_chat_id
    FROM public.cycles cy
    WHERE cy.id = NEW.cycle_id;

    SELECT COUNT(*) INTO v_prop_count
    FROM public.propositions
    WHERE round_id = v_round_id;

    -- With >= 2 props on the board, EVERYONE can rate under conditional
    -- self-inclusion — nobody is stranded. Skip the loop entirely.
    IF v_prop_count >= 2 THEN
        RETURN NEW;
    END IF;

    -- Degenerate rounds (< 2 props): mirror the CSI votability rule per
    -- participant. votable = non-own, or ALL props when non-own < 2. The
    -- rating UIs need 2, so anyone with votable < 2 structurally cannot rate
    -- and is auto-skipped so the round can progress.
    FOR v_participant_id IN
        SELECT id FROM public.participants
        WHERE chat_id = v_chat_id AND status = 'active'
    LOOP
        SELECT COUNT(*) INTO v_non_own
        FROM public.propositions
        WHERE round_id = v_round_id
          AND (participant_id IS NULL OR participant_id != v_participant_id);

        v_votable := CASE WHEN v_non_own >= 2 THEN v_non_own ELSE v_prop_count END;

        IF v_votable < 2 THEN
            INSERT INTO public.rating_skips (round_id, participant_id)
            VALUES (v_round_id, v_participant_id)
            ON CONFLICT DO NOTHING;

            RAISE NOTICE '[STRANDED RATER] Round % participant % has only % votable props (CSI); auto-skipping.',
                v_round_id, v_participant_id, v_votable;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.maybe_mark_stranded_raters IS
'Fires when a round transitions to the rating phase. Under conditional
self-inclusion (20260704160000) any participant can rate a round with >= 2
propositions (their own is served when excluding it would leave them under
2), so stranding only exists in degenerate rounds with < 2 props total —
those participants get an auto rating_skip so the round can progress.
Pre-CSI this compared non-own props against rating_minimum, which made
2-prop / 2-author rounds auto-skip EVERYONE and complete with zero votes
(the round self-destructed the instant rating opened).';
