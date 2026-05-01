-- =============================================================================
-- MIGRATION: Auto-skip rating for participants who can't satisfy rating_minimum
-- =============================================================================
-- The existing `maxSkips = participants - proposing_minimum` cap protected an
-- invariant: each rater always has ≥ rating_minimum NON-OWN propositions to
-- rank. Affirmation broke that invariant by allowing more participants to
-- bypass proposing without submitting.
--
-- Concrete failure (chat 303): 3 participants, proposing_minimum=3. One
-- affirms, two submit (one of whom is the carry-forward's original author).
-- The round has 3 propositions but the carry author owns 2 of them — only 1
-- proposition is rateable for them, below rating_minimum=2. The rating screen
-- throws "Not enough propositions to rank (need at least 2)".
--
-- Fix: when a round transitions to the rating phase, scan active participants
-- and insert a `rating_skips` row for anyone whose rateable count is below
-- rating_minimum. Their participation is recorded as a rating-skip — counted
-- toward "everyone is done with rating" — so the round can advance normally.
-- The client side requires no changes: the existing rating-screen
-- auto-navigation already gates on `!state.hasSkippedRating`, and the inline
-- rating-action UI already renders the skipped indicator for these users.
--
-- Plan: docs/planning/AFFIRMATION_FEATURE.md (extends the affirmation
-- structural-guard analysis).
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.maybe_mark_stranded_raters()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round_id BIGINT;
    v_chat_id BIGINT;
    v_rating_minimum INT;
    v_participant_id BIGINT;
    v_rateable_count INT;
BEGIN
    v_round_id := NEW.id;

    SELECT cy.chat_id, c.rating_minimum
      INTO v_chat_id, v_rating_minimum
    FROM public.cycles cy
    JOIN public.chats c ON c.id = cy.chat_id
    WHERE cy.id = NEW.cycle_id;

    -- For each active participant, count propositions they could rate
    -- (everything except their own NEW or carried-forward submissions).
    -- This mirrors the WHERE clause in get_least_rated_propositions.
    FOR v_participant_id IN
        SELECT id FROM public.participants
        WHERE chat_id = v_chat_id AND status = 'active'
    LOOP
        SELECT COUNT(*) INTO v_rateable_count
        FROM public.propositions
        WHERE round_id = v_round_id
          AND (participant_id IS NULL OR participant_id != v_participant_id);

        IF v_rateable_count < v_rating_minimum THEN
            -- Stranded: structurally cannot rate this round. Record as
            -- a rating-skip so they're counted "done" by rating-advance
            -- triggers and the round can progress.
            INSERT INTO public.rating_skips (round_id, participant_id)
            VALUES (v_round_id, v_participant_id)
            ON CONFLICT DO NOTHING;

            RAISE NOTICE '[STRANDED RATER] Round % participant % has only % rateable props (rating_minimum=%); auto-skipping.',
                v_round_id, v_participant_id, v_rateable_count, v_rating_minimum;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

ALTER FUNCTION public.maybe_mark_stranded_raters() OWNER TO postgres;

COMMENT ON FUNCTION public.maybe_mark_stranded_raters IS
'Fires when a round transitions to the rating phase. For each active
participant whose count of rateable propositions (= propositions in the
round NOT authored by them, including carried-forward) is below the
chat''s rating_minimum, inserts a rating_skips row so the round can
progress without that participant rating. The existing rating-advance
triggers count the inserted skips toward the "everyone done" threshold.

This fixes the structural failure introduced by the affirmation feature:
when affirms substitute for submissions, fresh-prop count can drop below
proposing_minimum and the carry author ends up with too few rateable
propositions to rank validly.';

DROP TRIGGER IF EXISTS trg_mark_stranded_raters ON public.rounds;
CREATE TRIGGER trg_mark_stranded_raters
AFTER UPDATE OF phase ON public.rounds
FOR EACH ROW
WHEN (NEW.phase = 'rating' AND (OLD.phase IS DISTINCT FROM 'rating'))
EXECUTE FUNCTION public.maybe_mark_stranded_raters();

COMMIT;

-- =============================================================================
-- ROLLBACK (reference):
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_mark_stranded_raters ON public.rounds;
-- DROP FUNCTION IF EXISTS public.maybe_mark_stranded_raters();
-- COMMIT;
-- =============================================================================
