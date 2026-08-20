-- =============================================================================
-- Quick chats: a SUBSEQUENT round auto-enters proposing (no "waiting/Start" step)
-- =============================================================================
-- Rough edge found 2026-06-05 verifying convergence on a quick chat: when a
-- quick chat (max_cycles = 1) runs a round 2 (e.g. convergence with
-- confirmation_rounds_required >= 2), the carry-forward creates the new round via
-- create_round_for_cycle, which — for manual-start chats (all quick chats) — lands
-- it in 'waiting'. The host then has to tap a "Start" button before the round-2
-- "Current Leader → can you beat it?" proposing UI appears.
--
-- That Start step makes sense for ROUND 1 (the host is still gathering the group),
-- but not for a SUBSEQUENT round: by then the group is already present from round 1.
--
-- Fix: in create_round_for_cycle, when the chat is a quick chat (max_cycles = 1)
-- AND this is a subsequent round (p_custom_id > 1), open 'proposing' directly
-- (no timer — quick chats are host-controlled). Round 1 and all non-quick chats
-- are untouched. SECURITY DEFINER preserved (it does cross-table DML / funding).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_round_for_cycle(p_cycle_id bigint, p_chat_id bigint, p_custom_id integer DEFAULT 1)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
        c.proposing_duration_seconds,
        c.max_cycles
    INTO v_chat
    FROM chats c
    WHERE c.id = p_chat_id;

    -- Quick chats (max_cycles = 1): a SUBSEQUENT round (custom_id > 1) means the
    -- group already gathered in round 1, so skip the "waiting/Start" gather step
    -- and open proposing directly. Host-controlled, so no timer (phase_ends_at
    -- stays null). Round 1 keeps its normal behavior (options fork seeds straight
    -- to rating; group fork waits for the host's Start).
    IF v_chat.max_cycles = 1 AND p_custom_id > 1 THEN
        INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
        VALUES (p_cycle_id, p_custom_id, 'proposing', NOW())
        RETURNING id INTO v_new_round_id;

        RAISE NOTICE '[CREATE ROUND] Quick-chat subsequent round % (custom_id %) auto-entered proposing (group already present)',
            v_new_round_id, p_custom_id;

        RETURN v_new_round_id;
    END IF;

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
$function$;
