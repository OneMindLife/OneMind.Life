-- =============================================================================
-- MIGRATION: Add affirmations — first-class "support the previous winner" action
-- =============================================================================
-- Lets a participant in R2+ affirm the carried-forward winner instead of
-- submitting a new proposition. When ALL active participants affirm (zero
-- new submissions, ≥1 affirmation), an after-insert trigger auto-resolves
-- the round with the carried winner re-winning, skipping rating phase.
-- This unblocks the "everyone agrees, but proposing_minimum=3 forces new
-- submissions" deadlock.
--
-- Plan: docs/planning/AFFIRMATION_FEATURE.md
--
-- Layers:
--   1. Table + indexes + RLS (lockdown — INSERT goes through RPC).
--   2. affirm_round(p_round_id) RPC (SECURITY DEFINER, validates state).
--   3. resolve_carried_winner_for_round helper.
--   4. maybe_auto_resolve_affirm_round AFTER INSERT trigger.
--   5. Update existing early-advance triggers to count affirmers in
--      participation totals.
--
-- Rollback: see ROLLBACK section at the bottom of this file (commented).
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: affirmations table
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.affirmations (
    id BIGSERIAL PRIMARY KEY,
    round_id BIGINT NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
    participant_id BIGINT NOT NULL REFERENCES public.participants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT affirmations_unique_per_round UNIQUE (round_id, participant_id)
);

ALTER TABLE public.affirmations OWNER TO postgres;

CREATE INDEX IF NOT EXISTS idx_affirmations_round ON public.affirmations(round_id);
CREATE INDEX IF NOT EXISTS idx_affirmations_user  ON public.affirmations(user_id);

COMMENT ON TABLE public.affirmations IS
'Records when a participant affirms the carried-forward winner instead of
submitting a new proposition. Per (round, participant). When all active
participants in a round have affirmed AND there are zero new submissions,
the round auto-resolves with the carried winner re-winning (rating phase
is skipped). Counts toward participation thresholds same as round_skips.';

-- Realtime: allow clients to react to other users'' affirmations live.
ALTER PUBLICATION supabase_realtime ADD TABLE public.affirmations;
ALTER TABLE public.affirmations REPLICA IDENTITY FULL;

-- =============================================================================
-- STEP 2: RLS — SELECT to participants of the chat, no direct INSERT/UPDATE/DELETE
-- =============================================================================

ALTER TABLE public.affirmations ENABLE ROW LEVEL SECURITY;

-- INSERT must go through the RPC (which is SECURITY DEFINER).
CREATE POLICY affirmations_no_direct_insert ON public.affirmations
    FOR INSERT WITH CHECK (false);

-- SELECT: participants of the chat the round belongs to. Service role
-- short-circuit follows the project pattern (memory: RLS Policy Pattern).
CREATE POLICY affirmations_select_chat_participants ON public.affirmations
    FOR SELECT USING (
        (current_setting('role', true) = 'service_role') OR
        EXISTS (
            SELECT 1
            FROM public.rounds r
            JOIN public.cycles cy ON cy.id = r.cycle_id
            JOIN public.participants p ON p.chat_id = cy.chat_id
            WHERE r.id = affirmations.round_id
              AND p.user_id = auth.uid()
              AND p.status = 'active'
        )
    );

-- Lockdown: revoke all writes from public/anon/authenticated. Reads are
-- granted explicitly so the SELECT policy can take effect.
REVOKE INSERT, UPDATE, DELETE ON public.affirmations FROM anon, authenticated, public;
GRANT SELECT ON public.affirmations TO anon, authenticated;
GRANT ALL ON public.affirmations TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.affirmations_id_seq
    TO anon, authenticated, service_role;

-- =============================================================================
-- STEP 3: resolve_carried_winner_for_round — helper called by trigger
-- =============================================================================
-- Marks the carried-forward proposition as the round''s sole winner.
-- The existing BEFORE UPDATE OF winning_proposition_id trigger
-- (on_round_winner_set) handles convergence detection and next-round
-- creation, so this helper just sets the winner.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.resolve_carried_winner_for_round(
    p_round_id BIGINT,
    p_carried_proposition_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Idempotency: if this round already has a winner row, skip.
    IF EXISTS (SELECT 1 FROM public.round_winners WHERE round_id = p_round_id) THEN
        RAISE NOTICE '[AFFIRM RESOLVE] Round % already has a winner row, skipping.', p_round_id;
        RETURN;
    END IF;

    INSERT INTO public.round_winners (round_id, proposition_id, rank)
    VALUES (p_round_id, p_carried_proposition_id, 1);

    UPDATE public.rounds
    SET winning_proposition_id = p_carried_proposition_id,
        is_sole_winner = TRUE
    WHERE id = p_round_id
      AND winning_proposition_id IS NULL;

    RAISE NOTICE '[AFFIRM RESOLVE] Round % auto-resolved with carried prop %.',
        p_round_id, p_carried_proposition_id;
END;
$$;

ALTER FUNCTION public.resolve_carried_winner_for_round(BIGINT, BIGINT) OWNER TO postgres;

COMMENT ON FUNCTION public.resolve_carried_winner_for_round IS
'Marks the given carried-forward proposition as the sole winner of the
round. Idempotent — does nothing if the round already has a winner row.
Triggers on_round_winner_set, which advances the cycle (convergence or
next round). Used by the all-affirm auto-resolve path.';

-- =============================================================================
-- STEP 4: affirm_round RPC — public entry point, validates and inserts
-- =============================================================================

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
    v_allow_skip BOOLEAN;
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

    -- Resolve participant + chat + phase + chat-config flag in one shot.
    SELECT p.id, p.chat_id, c.allow_skip_proposing, r.phase
      INTO v_participant_id, v_chat_id, v_allow_skip, v_phase
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

    IF NOT v_allow_skip THEN
        RAISE EXCEPTION 'this chat does not allow affirmation'
            USING ERRCODE = 'P0003';
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

    -- Can''t affirm if the user already submitted a NEW proposition.
    SELECT COUNT(*) INTO v_my_submissions
    FROM public.propositions
    WHERE round_id = p_round_id
      AND participant_id = v_participant_id
      AND carried_from_id IS NULL;

    IF v_my_submissions > 0 THEN
        RAISE EXCEPTION 'already submitted a proposition, cannot affirm'
            USING ERRCODE = 'P0005';
    END IF;

    -- Can''t affirm if the user already skipped (one non-submission action per round).
    SELECT COUNT(*) INTO v_already_skipped
    FROM public.round_skips
    WHERE round_id = p_round_id
      AND participant_id = v_participant_id;

    IF v_already_skipped > 0 THEN
        RAISE EXCEPTION 'already skipped, cannot affirm'
            USING ERRCODE = 'P0006';
    END IF;

    -- Insert. UNIQUE constraint catches the double-affirm race.
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

ALTER FUNCTION public.affirm_round(BIGINT) OWNER TO postgres;

COMMENT ON FUNCTION public.affirm_round IS
'RPC for affirming the carried-forward winner. Validates: caller is an
active participant; round is in proposing phase; chat allows skip-style
non-submission; a carried-forward proposition exists; caller has not
submitted or skipped. Returns the new affirmations.id. Errors carry
sqlstate codes P0001-P0007 for client-side mapping.';

GRANT EXECUTE ON FUNCTION public.affirm_round(BIGINT) TO anon, authenticated, service_role;

-- =============================================================================
-- STEP 5: maybe_auto_resolve_affirm_round — AFTER INSERT trigger
-- =============================================================================
-- After every affirmation insert, check whether the round can auto-resolve:
-- - all active participants have either submitted, skipped, or affirmed
-- - zero NEW submissions (so we can declare carried as winner)
-- - a carried-forward proposition exists
-- If so, declare the carried as winner, skipping rating.
--
-- Concurrency: pg_advisory_xact_lock(round_id) — same pattern as
-- check_early_advance_on_proposition / on_skip (see memory: bug fix
-- 20260317300000). Without the lock, two concurrent final affirmations
-- can both observe v_affirmations < v_active and neither resolve.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.maybe_auto_resolve_affirm_round()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round_id BIGINT := NEW.round_id;
    v_chat_id BIGINT;
    v_phase TEXT;
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
    SELECT r.phase, cy.chat_id
      INTO v_phase, v_chat_id
    FROM public.rounds r
    JOIN public.cycles cy ON cy.id = r.cycle_id
    WHERE r.id = v_round_id;

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
    -- (carry-forward picks the previous round''s sole winner).
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
$$;

ALTER FUNCTION public.maybe_auto_resolve_affirm_round() OWNER TO postgres;

COMMENT ON FUNCTION public.maybe_auto_resolve_affirm_round IS
'AFTER INSERT trigger on affirmations. When the round''s active
participants have all submitted/skipped/affirmed AND zero new submissions
exist AND ≥1 affirmation was recorded AND a carried-forward exists,
declares the carried as sole winner. Rating phase is skipped — the
existing on_round_winner_set BEFORE UPDATE trigger on rounds advances the
cycle (convergence or next round).';

DROP TRIGGER IF EXISTS trg_maybe_auto_resolve_affirm_round ON public.affirmations;
CREATE TRIGGER trg_maybe_auto_resolve_affirm_round
AFTER INSERT ON public.affirmations
FOR EACH ROW
EXECUTE FUNCTION public.maybe_auto_resolve_affirm_round();

-- =============================================================================
-- STEP 6: Update early-advance triggers to count affirmers
-- =============================================================================
-- Existing triggers: check_early_advance_on_proposition (fires on new
-- proposition INSERT) and check_early_advance_on_skip (fires on new
-- round_skips INSERT). Both compute v_participated_count = unique
-- submitters + skippers. With affirmations as a new participation path,
-- that sum needs to include affirmers too — otherwise the participation %
-- bar lags and the round can stay open while everyone has acted.
--
-- The all-affirm auto-resolve path is handled by the new trigger above
-- (which short-circuits this code path because the round's phase is no
-- longer 'proposing' by the time the early-advance triggers run again).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_early_advance_on_proposition()
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
    v_count_met := v_unique_submitters >= v_effective_count_threshold;
    v_minimum_met := v_proposition_count >= LEAST(v_chat.proposing_minimum, v_max_possible);

    RAISE NOTICE '[EARLY ADVANCE] Round %: % submitters + % skips + % affirms = % participated (need %). Count: % (need %). Min: % (need %). Funded: %.',
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


CREATE OR REPLACE FUNCTION public.check_early_advance_on_skip()
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

-- =============================================================================
-- ROLLBACK (reference) — apply in a follow-up migration if reverting:
--
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_maybe_auto_resolve_affirm_round ON public.affirmations;
-- DROP FUNCTION IF EXISTS public.maybe_auto_resolve_affirm_round();
-- DROP FUNCTION IF EXISTS public.affirm_round(BIGINT);
-- DROP FUNCTION IF EXISTS public.resolve_carried_winner_for_round(BIGINT, BIGINT);
-- ALTER PUBLICATION supabase_realtime DROP TABLE public.affirmations;
-- DROP TABLE IF EXISTS public.affirmations;
-- -- Restore the pre-affirmation versions of check_early_advance_on_proposition
-- -- and check_early_advance_on_skip from migration
-- -- 20260317300000_fix_proposing_early_advance_race_condition.sql.
-- COMMIT;
-- =============================================================================
