-- Fix billing functions to use BIGINT for chat_id and round_id
-- These columns are BIGINT in the tables but the functions were defined with INTEGER

-- Drop and recreate deduct_user_rounds with correct types
DROP FUNCTION IF EXISTS deduct_user_rounds(uuid, integer, integer, integer);

CREATE OR REPLACE FUNCTION public.deduct_user_rounds(
    p_user_id uuid,
    p_user_round_count integer,
    p_chat_id bigint,
    p_round_id bigint
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_credits public.user_credits;
    v_free_limit INTEGER;
    v_free_remaining INTEGER;
    v_from_free INTEGER;
    v_from_paid INTEGER;
    v_month_start DATE;
BEGIN
    -- Check if can afford
    IF NOT can_afford_user_rounds(p_user_id, p_user_round_count) THEN
        RETURN FALSE;
    END IF;

    -- Get user credits
    v_credits := get_or_create_user_credits(p_user_id);

    -- Get free tier limit
    SELECT value::INTEGER INTO v_free_limit
    FROM public.billing_config
    WHERE key = 'free_tier_monthly_limit';

    -- Calculate split between free and paid
    v_free_remaining := GREATEST(0, v_free_limit - v_credits.free_tier_used);
    v_from_free := LEAST(p_user_round_count, v_free_remaining);
    v_from_paid := p_user_round_count - v_from_free;

    -- Update user credits
    UPDATE public.user_credits
    SET free_tier_used = free_tier_used + v_from_free,
        credit_balance = credit_balance - v_from_paid
    WHERE id = v_credits.id
    RETURNING * INTO v_credits;

    -- Record transaction if paid credits used
    IF v_from_paid > 0 THEN
        INSERT INTO public.credit_transactions (
            user_id, transaction_type, amount, balance_after,
            description, chat_id, round_id, user_round_count
        ) VALUES (
            p_user_id, 'usage', -v_from_paid, v_credits.credit_balance,
            format('Used %s paid credits for %s user-rounds', v_from_paid, p_user_round_count),
            p_chat_id, p_round_id, p_user_round_count
        );
    END IF;

    -- Update monthly usage
    v_month_start := date_trunc('month', NOW())::DATE;

    INSERT INTO public.monthly_usage (
        user_id, month_start, total_user_rounds, free_tier_user_rounds,
        paid_user_rounds, total_rounds
    ) VALUES (
        p_user_id, v_month_start, p_user_round_count, v_from_free,
        v_from_paid, 1
    )
    ON CONFLICT (user_id, month_start) DO UPDATE SET
        total_user_rounds = monthly_usage.total_user_rounds + p_user_round_count,
        free_tier_user_rounds = monthly_usage.free_tier_user_rounds + v_from_free,
        paid_user_rounds = monthly_usage.paid_user_rounds + v_from_paid,
        total_rounds = monthly_usage.total_rounds + 1;

    -- Check if auto-refill should be triggered
    PERFORM check_and_queue_auto_refill(p_user_id);

    RETURN TRUE;
END;
$function$;
