-- Official / arena rooms bypass the per-participant credit funding gate when
-- auto-starting a round.
--
-- The bug (observed live on GLOBAL / chat 1269, 2026-08-04): create_round_for_cycle
-- only opens a new 'auto' round when chat_credits.credit_balance >= the count of
-- active participants; otherwise it leaves the round in 'waiting' forever (a
-- "credit-paused" round). GLOBAL is a free public room whose "active
-- participant" count is inflated by thousands of accumulated drive-by joiners
-- (2530 rows, ~1 actually active), so the balance can never cover it and every
-- new round stalls in 'waiting' -- the UI shows "a new take opens shortly" and
-- nothing happens.
--
-- Official/arena rooms are free public rooms: they already bypass the SUBMISSION
-- funding gate (submit-proposition: `isFunded === false && !isOfficialChat`), so
-- gating ROUND CREATION on credits is the missing half of that exemption. The
-- fix opens proposing directly, unfunded, for is_official OR is_arena chats.
-- Billed private chats keep the credit gate unchanged.
--
-- Verified 2026-08-04: exactly one chat is official/arena (1269), so the blast
-- radius is that room alone. Submissions work unfunded there (official bypass);
-- votes insert directly (no funding gate). Only the auto-start branch changed;
-- quick-chat and non-auto paths are identical to the prior version.

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
    SELECT
        c.start_mode,
        c.auto_start_participant_count,
        c.proposing_duration_seconds,
        c.max_cycles,
        c.is_official,
        c.is_arena
    INTO v_chat
    FROM chats c
    WHERE c.id = p_chat_id;

    -- Quick chats (max_cycles = 1): a SUBSEQUENT round (custom_id > 1) means the
    -- group already gathered in round 1, so skip the "waiting/Start" gather step
    -- and open proposing directly. Host-controlled, so no timer. Round 1 and all
    -- non-quick chats keep their normal behavior.
    IF v_chat.max_cycles = 1 AND p_custom_id > 1 THEN
        INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
        VALUES (p_cycle_id, p_custom_id, 'proposing', NOW())
        RETURNING id INTO v_new_round_id;

        RAISE NOTICE '[CREATE ROUND] Quick-chat subsequent round % (custom_id %) auto-entered proposing (group already present)',
            v_new_round_id, p_custom_id;

        RETURN v_new_round_id;
    END IF;

    IF v_chat.start_mode = 'auto' THEN
        SELECT COUNT(*) INTO v_participant_count
        FROM participants
        WHERE chat_id = p_chat_id
        AND status = 'active';

        IF v_participant_count >= v_chat.auto_start_participant_count THEN
            -- Free public rooms (official / arena) open proposing directly,
            -- unfunded. Their "participant count" is inflated by accumulated
            -- drive-by joiners, so a credit >= participants gate stalls every
            -- round in 'waiting' forever. They already bypass the submission
            -- funding gate, so no per-round funding is required here.
            IF COALESCE(v_chat.is_official, false) OR COALESCE(v_chat.is_arena, false) THEN
                v_phase_ends_at := calculate_round_minute_end(v_chat.proposing_duration_seconds);

                INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
                VALUES (p_cycle_id, p_custom_id, 'proposing', NOW(), v_phase_ends_at)
                RETURNING id INTO v_new_round_id;

                RAISE NOTICE '[CREATE ROUND] Official/arena round % opened proposing unfunded (free public room, credit gate bypassed)',
                    v_new_round_id;

                RETURN v_new_round_id;
            END IF;

            SELECT credit_balance INTO v_balance
            FROM public.chat_credits
            WHERE chat_id = p_chat_id
            FOR UPDATE;

            IF v_balance IS NOT NULL AND v_balance >= v_participant_count THEN
                INSERT INTO rounds (cycle_id, custom_id, phase)
                VALUES (p_cycle_id, p_custom_id, 'waiting')
                RETURNING id INTO v_new_round_id;

                v_funded_count := public.fund_round_participants(v_new_round_id, p_chat_id);

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
                RAISE NOTICE '[CREATE ROUND] Insufficient credits for chat % (balance=%, need=%), creating credit-paused round',
                    p_chat_id, COALESCE(v_balance, 0), v_participant_count;
            END IF;
        END IF;
    END IF;

    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (p_cycle_id, p_custom_id, 'waiting')
    RETURNING id INTO v_new_round_id;

    RETURN v_new_round_id;
END;
$function$;
