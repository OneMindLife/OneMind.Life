-- Add rating_start_mode to allow decoupling proposing from rating
-- Similar to start_mode (which controls how proposing starts),
-- rating_start_mode controls how rating starts after proposing ends.
--
-- Values:
--   'auto' (default): Rating starts immediately when proposing ends (current behavior)
--   'manual': Host must manually start rating phase

-- =============================================================================
-- STEP 1: Add rating_start_mode column
-- =============================================================================

ALTER TABLE public.chats
ADD COLUMN rating_start_mode TEXT NOT NULL DEFAULT 'auto';

-- Add CHECK constraint
ALTER TABLE public.chats
ADD CONSTRAINT chats_rating_start_mode_check
CHECK (rating_start_mode IN ('manual', 'auto'));

COMMENT ON COLUMN public.chats.rating_start_mode IS
'Controls how rating phase starts after proposing ends.
manual = Host must click to start rating (allows reviewing propositions first)
auto = Rating starts immediately when proposing ends or threshold met';

-- =============================================================================
-- STEP 2: Update check_early_advance_on_proposition trigger
-- When proposing threshold is met, only auto-advance to rating if rating_start_mode = ''auto''
-- =============================================================================

CREATE OR REPLACE FUNCTION check_early_advance_on_proposition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_participant_count INTEGER;
    v_proposition_count INTEGER;
    v_threshold_count INTEGER;
    v_threshold_percent INTEGER;
    v_required_count INTEGER;
    v_now TIMESTAMPTZ;
    v_phase_ends_at TIMESTAMPTZ;
BEGIN
    -- Get round details
    SELECT r.*, c.id as cycle_id
    INTO v_round
    FROM public.rounds r
    JOIN public.cycles c ON r.cycle_id = c.id
    WHERE r.id = NEW.round_id;

    -- Only process if round is in proposing phase
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

    -- Count propositions in this round
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = NEW.round_id;

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

            RAISE NOTICE '[EARLY ADVANCE] Proposing threshold met (% of % submitted, required %). Advancing round % to rating.',
                v_proposition_count, v_participant_count, v_required_count, NEW.round_id;

            UPDATE public.rounds
            SET phase = 'rating',
                phase_started_at = v_now,
                phase_ends_at = v_phase_ends_at
            WHERE id = NEW.round_id;
        ELSE
            -- Manual rating start mode: go to waiting phase
            -- Host will need to manually start rating
            RAISE NOTICE '[EARLY ADVANCE] Proposing threshold met (% of % submitted, required %). Round % waiting for manual rating start.',
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
$function$;

COMMENT ON FUNCTION check_early_advance_on_proposition IS
'Trigger function that checks if proposing threshold is met after each proposition insert.
If rating_start_mode=auto: Advances to rating phase immediately.
If rating_start_mode=manual: Goes to waiting phase for host to manually start rating.';

-- =============================================================================
-- STEP 3: Create function to advance from proposing to waiting-for-rating
-- This is called by edge functions when proposing timer expires
-- =============================================================================

CREATE OR REPLACE FUNCTION advance_proposing_to_waiting(p_round_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_chat RECORD;
    v_cycle_id INTEGER;
BEGIN
    -- Get cycle_id for the round
    SELECT cycle_id INTO v_cycle_id
    FROM public.rounds
    WHERE id = p_round_id;

    -- Get chat settings
    SELECT c.* INTO v_chat
    FROM public.chats c
    JOIN public.cycles cy ON cy.chat_id = c.id
    WHERE cy.id = v_cycle_id;

    -- Only proceed if rating_start_mode is manual
    IF v_chat.rating_start_mode != 'manual' THEN
        RAISE EXCEPTION 'advance_proposing_to_waiting called but rating_start_mode is not manual';
    END IF;

    -- Transition to waiting phase (waiting for rating to start)
    UPDATE public.rounds
    SET phase = 'waiting',
        phase_started_at = NULL,
        phase_ends_at = NULL
    WHERE id = p_round_id
      AND phase = 'proposing';

    RAISE NOTICE '[PHASE] Round % transitioned from proposing to waiting (pending rating start)', p_round_id;
END;
$function$;

COMMENT ON FUNCTION advance_proposing_to_waiting IS
'Transitions a round from proposing to waiting phase when rating_start_mode=manual.
The round will have propositions but be in waiting phase, indicating host needs to start rating.';

-- =============================================================================
-- STEP 4: Create helper function to check if round is waiting for rating
-- =============================================================================

CREATE OR REPLACE FUNCTION is_round_waiting_for_rating(p_round_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_round RECORD;
    v_proposition_count INTEGER;
BEGIN
    -- Get round details
    SELECT * INTO v_round
    FROM public.rounds
    WHERE id = p_round_id;

    -- Must be in waiting phase
    IF v_round.phase != 'waiting' THEN
        RETURN FALSE;
    END IF;

    -- Check if there are propositions in this round
    SELECT COUNT(*) INTO v_proposition_count
    FROM public.propositions
    WHERE round_id = p_round_id;

    -- If propositions exist, we're waiting for rating
    -- If no propositions, we're waiting for proposing
    RETURN v_proposition_count > 0;
END;
$function$;

COMMENT ON FUNCTION is_round_waiting_for_rating IS
'Returns TRUE if the round is in waiting phase with propositions (waiting for rating to start).
Returns FALSE if waiting phase with no propositions (waiting for proposing to start).';

-- =============================================================================
-- STEP 5: Update process_scheduled_chats to handle rating_start_mode
-- When resuming from pause, check if we should auto-advance to rating
-- =============================================================================

-- Note: The existing process_scheduled_chats handles pause/resume.
-- When a chat is resumed and proposing timer has expired:
-- - If rating_start_mode='auto': advance to rating
-- - If rating_start_mode='manual': go to waiting (for rating)
-- This is already handled by the edge function that processes timer expiry.

-- =============================================================================
-- INDEXES
-- =============================================================================

-- No index needed since rating_start_mode is queried per-chat, not for filtering
