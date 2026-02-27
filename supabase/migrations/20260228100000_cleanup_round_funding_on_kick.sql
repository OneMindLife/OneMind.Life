-- When a participant is kicked, remove their round_funding records
-- for any incomplete rounds. This prevents the kicked participant from
-- inflating the funded count used in threshold calculations.
--
-- Also refunds the credit back to the chat since the participant
-- can no longer participate in those rounds.

CREATE OR REPLACE FUNCTION public.cleanup_round_funding_on_kick()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted_count INTEGER;
    v_chat_id       INTEGER;
BEGIN
    -- Only act when status changes TO 'kicked'
    IF NEW.status <> 'kicked' OR OLD.status = 'kicked' THEN
        RETURN NEW;
    END IF;

    v_chat_id := NEW.chat_id;

    -- Delete round_funding records for incomplete rounds only
    -- (completed rounds are historical and should keep their records)
    WITH deleted AS (
        DELETE FROM public.round_funding rf
        USING public.rounds r, public.cycles c
        WHERE rf.participant_id = NEW.id
          AND rf.round_id = r.id
          AND r.cycle_id = c.id
          AND c.chat_id = v_chat_id
          AND r.completed_at IS NULL
        RETURNING rf.id
    )
    SELECT COUNT(*) INTO v_deleted_count FROM deleted;

    -- Refund credits for the deleted funding records
    IF v_deleted_count > 0 THEN
        UPDATE public.chat_credits
        SET credit_balance = credit_balance + v_deleted_count,
            updated_at = NOW()
        WHERE chat_id = v_chat_id;

        -- Record the refund transaction
        INSERT INTO public.chat_credit_transactions
            (chat_id, transaction_type, amount, balance_after, participant_count)
        SELECT
            v_chat_id,
            'kick_refund',
            v_deleted_count,
            cc.credit_balance,
            v_deleted_count
        FROM public.chat_credits cc
        WHERE cc.chat_id = v_chat_id;

        RAISE LOG 'Cleaned up % round_funding record(s) for kicked participant % in chat %',
            v_deleted_count, NEW.id, v_chat_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_cleanup_round_funding_on_kick
AFTER UPDATE OF status ON public.participants
FOR EACH ROW
WHEN (NEW.status = 'kicked' AND OLD.status <> 'kicked')
EXECUTE FUNCTION public.cleanup_round_funding_on_kick();
