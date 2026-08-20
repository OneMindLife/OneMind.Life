-- Quick-Create flow, part 1: stop-after-N-cycles + ended state + preview flag.
--
-- Today every chat is CONTINUOUS: when a cycle reaches consensus, on_cycle_winner_set
-- immediately starts the next cycle. The landing-CTA "quick create" flow needs a chat
-- that produces ONE sealed result and then stops (a ranking, or one converged winner).
--
-- We add:
--   chats.max_cycles  INT NULL          -- NULL = continuous (today's behavior); 1 = stop after first result
--   chats.ended_at    TIMESTAMPTZ NULL  -- NULL = live; set = chat is finished, no further rounds
--   chats.is_preview  BOOLEAN           -- true = ephemeral solo preview (hide share); false = normal/real chat
--
-- and guard on_cycle_winner_set so a capped chat ends instead of looping.
-- All columns default to current behavior, so existing chats are untouched.

ALTER TABLE public.chats
    ADD COLUMN IF NOT EXISTS max_cycles  INTEGER,
    ADD COLUMN IF NOT EXISTS ended_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS is_preview  BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.chats.max_cycles IS
    'Cap on completed cycles. NULL = continuous (run forever). N = end the chat after N completed cycles (sealed result). Quick-create chats use 1.';
COMMENT ON COLUMN public.chats.ended_at IS
    'When set, the chat is finished: no further cycles/rounds are created and process-timers ignores it. Set by on_cycle_winner_set when max_cycles is reached.';
COMMENT ON COLUMN public.chats.is_preview IS
    'True for the ephemeral solo preview chat in the quick-create flow. Share/invite UI is hidden; the chat is replaced by a fresh real chat when the creator taps "Invite others".';

-- Replace on_cycle_winner_set with a max_cycles-aware version. Body is identical to
-- the prod definition (pulled live 2026-05-29) except the stop-after-N branch.
-- Trigger timing (AFTER UPDATE ON cycles) is unchanged — CREATE OR REPLACE keeps it.
CREATE OR REPLACE FUNCTION public.on_cycle_winner_set()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_chat_id BIGINT;
    v_max_cycles INTEGER;
    v_completed_count INTEGER;
    new_cycle_id BIGINT;
    new_round_id BIGINT;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    -- Get chat_id + cap from this cycle's chat
    SELECT c.chat_id, ch.max_cycles
    INTO v_chat_id, v_max_cycles
    FROM cycles c
    JOIN chats ch ON ch.id = c.chat_id
    WHERE c.id = NEW.id;

    -- Stop-after-N: if this chat caps cycles, check whether we've hit the cap.
    -- on_round_winner_set has already set THIS cycle's completed_at (that UPDATE is
    -- what fired this trigger), so the just-finished cycle is counted below.
    IF v_max_cycles IS NOT NULL THEN
        SELECT COUNT(*) INTO v_completed_count
        FROM cycles
        WHERE chat_id = v_chat_id AND completed_at IS NOT NULL;

        IF v_completed_count >= v_max_cycles THEN
            -- Cap reached: seal the chat. No new cycle.
            UPDATE chats SET ended_at = NOW() WHERE id = v_chat_id AND ended_at IS NULL;
            RETURN NEW;
        END IF;
    END IF;

    -- Continuous (default): create new cycle for the chat
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO new_cycle_id;

    -- Create first round of new cycle using shared helper
    new_round_id := create_round_for_cycle(new_cycle_id, v_chat_id, 1);

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.on_cycle_winner_set() IS
    'On cycle consensus: if chats.max_cycles is reached, end the chat (set ended_at, no new cycle). Otherwise start the next cycle (continuous default).';
