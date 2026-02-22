-- =============================================================================
-- MIGRATION: Fix Credit Deduction TOCTOU Race Condition
-- =============================================================================
-- Bug: Round 367 was created in 'proposing' phase with 0 round_funding records.
--
-- Root cause: Classic TOCTOU race in create_round_for_cycle():
--   1. can_round_start() reads balance (STABLE, no lock) → TRUE
--   2. INSERT round phase='proposing'  ← committed to proposing
--   3. fund_round_participants() acquires FOR UPDATE lock, reads ACTUAL balance
--      → balance already depleted → funds 0 participants
--   4. RETURN (round stuck in 'proposing' with 0 funded)
--
-- Same bug exists in check_credit_resume(): checks can_round_start(), advances
-- to proposing, then funds — if balance changed between check and fund, round
-- advances without proper funding.
--
-- Fix: "Fund First, Advance Later" — always create round in 'waiting', attempt
-- funding atomically under FOR UPDATE lock, only advance to 'proposing' if ALL
-- participants were funded.
-- =============================================================================


-- =============================================================================
-- 1. Fix create_round_for_cycle: fund first, advance later
-- =============================================================================

CREATE OR REPLACE FUNCTION create_round_for_cycle(
    p_cycle_id BIGINT,
    p_chat_id BIGINT,
    p_custom_id INTEGER DEFAULT 1
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_new_round_id BIGINT;
    v_phase_ends_at TIMESTAMPTZ;
    v_funded_count INTEGER;
    v_balance INTEGER;
BEGIN
    -- Get chat settings
    SELECT
        c.start_mode,
        c.auto_start_participant_count,
        c.proposing_duration_seconds
    INTO v_chat
    FROM chats c
    WHERE c.id = p_chat_id;

    -- Check if auto-start conditions are met (participant count, mode)
    IF v_chat.start_mode = 'auto' THEN
        SELECT COUNT(*) INTO v_participant_count
        FROM participants
        WHERE chat_id = p_chat_id
        AND status = 'active';

        IF v_participant_count >= v_chat.auto_start_participant_count THEN
            -- Acquire FOR UPDATE lock and check balance ATOMICALLY
            -- This eliminates the TOCTOU race: the lock prevents concurrent
            -- deductions between our check and the subsequent funding call.
            SELECT credit_balance INTO v_balance
            FROM public.chat_credits
            WHERE chat_id = p_chat_id
            FOR UPDATE;

            IF v_balance IS NOT NULL AND v_balance >= v_participant_count THEN
                -- Sufficient credits: create round in WAITING, fund, then advance
                INSERT INTO rounds (cycle_id, custom_id, phase)
                VALUES (p_cycle_id, p_custom_id, 'waiting')
                RETURNING id INTO v_new_round_id;

                -- Fund participants (lock already held, fund_round_participants
                -- will re-acquire but that's fine — same transaction)
                v_funded_count := public.fund_round_participants(v_new_round_id, p_chat_id);

                -- Advance to proposing (we verified balance under lock)
                v_phase_ends_at := calculate_round_minute_end(v_chat.proposing_duration_seconds);

                UPDATE rounds
                SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = v_phase_ends_at
                WHERE id = v_new_round_id;

                RAISE NOTICE '[CREATE ROUND] Created proposing round % with % funded participants',
                    v_new_round_id, v_funded_count;

                RETURN v_new_round_id;
            ELSE
                -- Insufficient credits: create in waiting (credit-paused), no funding
                RAISE NOTICE '[CREATE ROUND] Insufficient credits for chat % (balance=%, need=%), creating credit-paused round',
                    p_chat_id, COALESCE(v_balance, 0), v_participant_count;
            END IF;
        END IF;
    END IF;

    -- Manual mode, conditions not met, or insufficient credits: create in waiting phase
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (p_cycle_id, p_custom_id, 'waiting')
    RETURNING id INTO v_new_round_id;

    RETURN v_new_round_id;
END;
$$;

COMMENT ON FUNCTION create_round_for_cycle IS
'Creates a round for a cycle. For auto-mode chats with sufficient participants, creates in
waiting phase first, attempts funding atomically (under FOR UPDATE lock), and only advances
to proposing if ALL participants are funded. This eliminates the TOCTOU race where
can_round_start() could return stale data.';


-- =============================================================================
-- 2. Fix check_credit_resume: fund first, advance later
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_credit_resume(p_chat_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat  RECORD;
    v_participant_count INTEGER;
    v_funded_count INTEGER;
    v_balance INTEGER;
    v_phase_ends_at TIMESTAMPTZ;
BEGIN
    -- Find a waiting round with NO new propositions (credit-paused, not waiting-for-rating)
    SELECT r.id, r.cycle_id INTO v_round
    FROM public.rounds r
    JOIN public.cycles c ON c.id = r.cycle_id
    WHERE c.chat_id = p_chat_id
      AND r.phase = 'waiting'
      AND NOT EXISTS (
          SELECT 1 FROM public.propositions p
          WHERE p.round_id = r.id AND p.carried_from_id IS NULL
      )
    ORDER BY r.id DESC
    LIMIT 1;

    IF v_round IS NULL THEN
        RETURN;  -- No credit-paused round
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM public.chats
    WHERE id = p_chat_id;

    -- Only resume auto-mode chats
    IF v_chat.start_mode != 'auto' THEN
        RETURN;
    END IF;

    -- Check participant threshold
    SELECT COUNT(*) INTO v_participant_count
    FROM public.participants
    WHERE chat_id = p_chat_id AND status = 'active';

    IF v_participant_count < v_chat.auto_start_participant_count THEN
        RETURN;  -- Not enough participants yet
    END IF;

    -- Check balance under FOR UPDATE lock (atomic check-then-fund)
    SELECT credit_balance INTO v_balance
    FROM public.chat_credits
    WHERE chat_id = p_chat_id
    FOR UPDATE;

    IF v_balance IS NULL OR v_balance < v_participant_count THEN
        RETURN;  -- Still not enough credits
    END IF;

    -- Fund participants (lock already held, same transaction)
    v_funded_count := public.fund_round_participants(v_round.id, p_chat_id);

    -- Advance to proposing
    v_phase_ends_at := calculate_round_minute_end(v_chat.proposing_duration_seconds);

    UPDATE public.rounds
    SET phase = 'proposing',
        phase_started_at = NOW(),
        phase_ends_at = v_phase_ends_at
    WHERE id = v_round.id;

    RAISE NOTICE '[CREDIT RESUME] Resumed round % with % funded participants',
        v_round.id, v_funded_count;
END;
$$;

COMMENT ON FUNCTION public.check_credit_resume IS
'Resumes a credit-paused waiting round after credits are added. Checks balance under
FOR UPDATE lock before funding, then advances to proposing only when ALL participants
can be funded. This eliminates the TOCTOU race where can_round_start() could see
stale balance data.';


-- =============================================================================
-- 3. Change can_round_start() from STABLE to VOLATILE
-- =============================================================================
-- Even though the two functions above no longer use it, can_round_start() is
-- still callable by other code. STABLE allows PostgreSQL to cache results
-- within a statement, which can return stale data within trigger chains.
-- VOLATILE ensures it always re-reads current state.

CREATE OR REPLACE FUNCTION public.can_round_start(p_chat_id BIGINT)
RETURNS BOOLEAN
LANGUAGE SQL
VOLATILE
SECURITY DEFINER
AS $$
    SELECT COALESCE(
        (SELECT cc.credit_balance >= (
            SELECT COUNT(*) FROM public.participants
            WHERE chat_id = p_chat_id AND status = 'active'
        )
        FROM public.chat_credits cc
        WHERE cc.chat_id = p_chat_id),
        FALSE  -- No chat_credits row = cannot start
    );
$$;

COMMENT ON FUNCTION public.can_round_start IS
'Returns true if the chat has enough credits to fund all active participants for a round.
Marked VOLATILE to prevent stale cached results within trigger chains.';


-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
