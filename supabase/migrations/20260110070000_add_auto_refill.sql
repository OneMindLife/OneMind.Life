-- Migration: Add auto-refill functionality
-- Allows users to automatically refill credits when balance drops below threshold

-- ============================================================================
-- STEP 1: Add Stripe customer tracking to user_credits
-- ============================================================================

ALTER TABLE public.user_credits
ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT;

ALTER TABLE public.user_credits
ADD COLUMN IF NOT EXISTS stripe_payment_method_id TEXT;

-- Index for looking up by Stripe customer
CREATE INDEX IF NOT EXISTS idx_user_credits_stripe_customer
    ON public.user_credits(stripe_customer_id)
    WHERE stripe_customer_id IS NOT NULL;

COMMENT ON COLUMN public.user_credits.stripe_customer_id IS 'Stripe customer ID for this user';
COMMENT ON COLUMN public.user_credits.stripe_payment_method_id IS 'Default payment method ID for auto-refill';

-- ============================================================================
-- STEP 2: Add auto-refill settings
-- ============================================================================

ALTER TABLE public.user_credits
ADD COLUMN IF NOT EXISTS auto_refill_enabled BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.user_credits
ADD COLUMN IF NOT EXISTS auto_refill_threshold INTEGER NOT NULL DEFAULT 50;

ALTER TABLE public.user_credits
ADD COLUMN IF NOT EXISTS auto_refill_amount INTEGER NOT NULL DEFAULT 500;

-- Constraint: threshold must be positive
ALTER TABLE public.user_credits
ADD CONSTRAINT user_credits_auto_refill_threshold_positive
CHECK (auto_refill_threshold >= 0);

-- Constraint: refill amount must be at least 1
ALTER TABLE public.user_credits
ADD CONSTRAINT user_credits_auto_refill_amount_positive
CHECK (auto_refill_amount >= 1);

-- Constraint: refill amount must be greater than threshold (otherwise infinite loop)
ALTER TABLE public.user_credits
ADD CONSTRAINT user_credits_auto_refill_amount_gt_threshold
CHECK (auto_refill_amount > auto_refill_threshold);

COMMENT ON COLUMN public.user_credits.auto_refill_enabled IS 'Whether auto-refill is enabled';
COMMENT ON COLUMN public.user_credits.auto_refill_threshold IS 'Trigger auto-refill when credit_balance falls below this';
COMMENT ON COLUMN public.user_credits.auto_refill_amount IS 'Number of credits to purchase when auto-refilling';

-- ============================================================================
-- STEP 3: Track auto-refill status
-- ============================================================================

ALTER TABLE public.user_credits
ADD COLUMN IF NOT EXISTS auto_refill_last_triggered_at TIMESTAMPTZ;

ALTER TABLE public.user_credits
ADD COLUMN IF NOT EXISTS auto_refill_last_error TEXT;

COMMENT ON COLUMN public.user_credits.auto_refill_last_triggered_at IS 'When auto-refill was last triggered';
COMMENT ON COLUMN public.user_credits.auto_refill_last_error IS 'Last auto-refill error message (null if successful)';

-- ============================================================================
-- STEP 4: Auto-refill queue table for async processing
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.auto_refill_queue (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    credits_to_add INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    error_message TEXT,
    stripe_payment_intent_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    UNIQUE(user_id, status) -- Only one pending/processing per user
);

CREATE INDEX IF NOT EXISTS idx_auto_refill_queue_status
    ON public.auto_refill_queue(status)
    WHERE status IN ('pending', 'processing');

CREATE INDEX IF NOT EXISTS idx_auto_refill_queue_user
    ON public.auto_refill_queue(user_id);

COMMENT ON TABLE public.auto_refill_queue IS 'Queue for processing auto-refill requests asynchronously';

-- ============================================================================
-- STEP 5: Function to check and queue auto-refill
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_and_queue_auto_refill(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits RECORD;
    v_existing_pending INT;
BEGIN
    -- Get user credits with auto-refill settings
    SELECT * INTO v_credits
    FROM public.user_credits
    WHERE user_id = p_user_id;

    -- No record or auto-refill not enabled
    IF v_credits.id IS NULL OR NOT v_credits.auto_refill_enabled THEN
        RETURN FALSE;
    END IF;

    -- No payment method saved
    IF v_credits.stripe_customer_id IS NULL OR v_credits.stripe_payment_method_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check if balance is below threshold
    IF v_credits.credit_balance >= v_credits.auto_refill_threshold THEN
        RETURN FALSE;
    END IF;

    -- Check if there's already a pending/processing request
    SELECT COUNT(*) INTO v_existing_pending
    FROM public.auto_refill_queue
    WHERE user_id = p_user_id
      AND status IN ('pending', 'processing');

    IF v_existing_pending > 0 THEN
        RETURN FALSE;
    END IF;

    -- Queue the auto-refill
    INSERT INTO public.auto_refill_queue (user_id, credits_to_add)
    VALUES (p_user_id, v_credits.auto_refill_amount)
    ON CONFLICT (user_id, status) DO NOTHING;

    -- Update last triggered time
    UPDATE public.user_credits
    SET auto_refill_last_triggered_at = NOW()
    WHERE user_id = p_user_id;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.check_and_queue_auto_refill IS 'Checks if auto-refill should be triggered and queues it';

-- ============================================================================
-- STEP 6: Function to update auto-refill settings
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_auto_refill_settings(
    p_user_id UUID,
    p_enabled BOOLEAN,
    p_threshold INTEGER DEFAULT NULL,
    p_amount INTEGER DEFAULT NULL
)
RETURNS public.user_credits
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits public.user_credits;
    v_threshold INTEGER;
    v_amount INTEGER;
BEGIN
    -- Get or create user credits
    v_credits := get_or_create_user_credits(p_user_id);

    -- Use provided values or keep existing
    v_threshold := COALESCE(p_threshold, v_credits.auto_refill_threshold);
    v_amount := COALESCE(p_amount, v_credits.auto_refill_amount);

    -- Validate: amount must be greater than threshold
    IF v_amount <= v_threshold THEN
        RAISE EXCEPTION 'Refill amount (%) must be greater than threshold (%)', v_amount, v_threshold;
    END IF;

    -- Update settings
    UPDATE public.user_credits
    SET auto_refill_enabled = p_enabled,
        auto_refill_threshold = v_threshold,
        auto_refill_amount = v_amount,
        auto_refill_last_error = NULL -- Clear any previous error
    WHERE user_id = p_user_id
    RETURNING * INTO v_credits;

    RETURN v_credits;
END;
$$;

COMMENT ON FUNCTION public.update_auto_refill_settings IS 'Updates auto-refill settings for a user';

-- ============================================================================
-- STEP 7: Function to save payment method
-- ============================================================================

CREATE OR REPLACE FUNCTION public.save_stripe_payment_method(
    p_user_id UUID,
    p_stripe_customer_id TEXT,
    p_stripe_payment_method_id TEXT
)
RETURNS public.user_credits
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits public.user_credits;
BEGIN
    -- Get or create user credits
    v_credits := get_or_create_user_credits(p_user_id);

    -- Update Stripe info
    UPDATE public.user_credits
    SET stripe_customer_id = p_stripe_customer_id,
        stripe_payment_method_id = p_stripe_payment_method_id
    WHERE user_id = p_user_id
    RETURNING * INTO v_credits;

    RETURN v_credits;
END;
$$;

COMMENT ON FUNCTION public.save_stripe_payment_method IS 'Saves Stripe customer and payment method IDs for a user';

-- ============================================================================
-- STEP 8: Update deduct_user_rounds to check auto-refill
-- ============================================================================

CREATE OR REPLACE FUNCTION public.deduct_user_rounds(
    p_user_id UUID,
    p_user_round_count INTEGER,
    p_chat_id INTEGER,
    p_round_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
$$;

-- ============================================================================
-- STEP 9: RLS Policies for auto_refill_queue
-- ============================================================================

ALTER TABLE public.auto_refill_queue ENABLE ROW LEVEL SECURITY;

-- Users can view their own queue entries
CREATE POLICY "Users can view own auto-refill queue"
    ON public.auto_refill_queue FOR SELECT
    USING (auth.uid() = user_id);

-- ============================================================================
-- STEP 10: Add transaction type for auto-refill
-- ============================================================================

-- Update the check constraint to include 'auto_refill'
ALTER TABLE public.credit_transactions
DROP CONSTRAINT IF EXISTS credit_transactions_transaction_type_check;

ALTER TABLE public.credit_transactions
ADD CONSTRAINT credit_transactions_transaction_type_check
CHECK (transaction_type IN ('purchase', 'usage', 'refund', 'adjustment', 'auto_refill'));

-- ============================================================================
-- STEP 11: Cron job for processing auto-refills
-- ============================================================================

-- Run every minute to process queued auto-refills
SELECT cron.schedule(
    'process-auto-refills',
    '* * * * *',  -- Every minute
    $$
    SELECT net.http_post(
        url := current_setting('app.settings.supabase_url') || '/functions/v1/process-auto-refill',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.cron_secret')
        ),
        body := '{}'::jsonb
    ) AS request_id;
    $$
);

