-- =============================================================================
-- Auto-start must require at least one HUMAN participant.
-- =============================================================================
-- Bug (2026-07-08): a public chat created with enable_agents=true gets a persona
-- agent auto-joined at creation by trg_auto_join_agents. That agent's INSERT
-- fired check_auto_start_on_participant_join, whose participant count did NOT
-- exclude agents. With a low auto_start_participant_count (e.g. 1) the lone agent
-- satisfied the threshold and the chat auto-started with ZERO humans, then
-- cascaded empty agent-only rounds until the auto-pause safety net caught it.
--
-- Fix: keep counting ALL active participants toward the threshold (so solo-game
-- AI seat-fill still starts a lone human's game), but additionally require that
-- at least one active HUMAN is present. This blocks only the zero-human case.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_auto_start_on_participant_join()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_human_count INTEGER;
    v_existing_cycle_id INTEGER;
    v_new_cycle_id BIGINT;
    v_new_round_id BIGINT;
    v_funded BOOLEAN;
BEGIN
    -- Only proceed for active participants (not pending approval)
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    SELECT
        c.id,
        c.start_mode,
        c.host_paused,
        c.auto_start_participant_count
    INTO v_chat
    FROM chats c
    WHERE c.id = NEW.chat_id;

    -- Only proceed if chat is in auto mode
    IF v_chat.start_mode != 'auto' THEN
        RETURN NEW;
    END IF;

    -- Skip auto-start while host has paused the chat.
    -- host_resume_chat will retry this logic when the host unpauses.
    -- Important: we do NOT attempt to fund mid-round joiners while paused
    -- because there is no active round to fund them into yet.
    IF v_chat.host_paused THEN
        RAISE NOTICE '[AUTO-START] Chat % is host_paused, skipping auto-start', NEW.chat_id;
        RETURN NEW;
    END IF;

    -- Check if there's already an existing cycle (chat already started)
    SELECT id INTO v_existing_cycle_id
    FROM cycles
    WHERE chat_id = NEW.chat_id
    LIMIT 1;

    IF v_existing_cycle_id IS NOT NULL THEN
        -- Chat already started: fund this mid-round joiner if possible.
        v_funded := public.fund_mid_round_join(NEW.id, NEW.chat_id);
        RAISE NOTICE '[AUTO-START] Mid-round join for participant %, funded: %',
            NEW.id, v_funded;
        RETURN NEW;
    END IF;

    -- Count active participants (all seats, incl. agents) toward the threshold,
    -- and separately count active HUMANS. Auto-start requires BOTH:
    --   * total active >= auto_start_participant_count  (existing semantics)
    --   * at least one active human                     (never start agent-only)
    -- The human requirement preserves solo-game AI seat-fill (1 human + AI seats
    -- reaching the threshold) while blocking a chat from starting on agents alone.
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE is_agent IS NOT TRUE)
    INTO v_participant_count, v_human_count
    FROM participants
    WHERE chat_id = NEW.chat_id
    AND status = 'active';

    RAISE NOTICE '[AUTO-START] Chat % has % active participants (% human), threshold is %',
        NEW.chat_id, v_participant_count, v_human_count, v_chat.auto_start_participant_count;

    IF v_human_count >= 1 AND v_participant_count >= v_chat.auto_start_participant_count THEN
        RAISE NOTICE '[AUTO-START] Threshold reached! Creating cycle and round for chat %', NEW.chat_id;

        -- Create first cycle
        INSERT INTO cycles (chat_id)
        VALUES (NEW.chat_id)
        RETURNING id INTO v_new_cycle_id;

        -- Create first round via the shared helper. create_round_for_cycle
        -- atomically acquires FOR UPDATE on chat_credits, funds participants
        -- if balance is sufficient, and uses calculate_round_minute_end() so
        -- the timer aligns with the cron job (no "0:00 ticking forever" bug).
        v_new_round_id := create_round_for_cycle(v_new_cycle_id, NEW.chat_id, 1);

        UPDATE chats
        SET last_activity_at = NOW()
        WHERE id = NEW.chat_id;

        RAISE NOTICE '[AUTO-START] Created cycle % and round % for chat %',
            v_new_cycle_id, v_new_round_id, NEW.chat_id;
    END IF;

    RETURN NEW;
END;
$function$;
