-- Migration: Fix Stripe webhook idempotency race condition
--
-- Problem: Two webhook calls could both pass the idempotency check before either writes
-- Solution: Add UNIQUE constraint to enforce at database level
--
-- Also adds:
-- - stripe_event_id for webhook event tracking
-- - Improved add_purchased_credits function with proper conflict handling

-- ============================================================================
-- STEP 1: Add stripe_event_id column for tracking webhook events
-- ============================================================================

ALTER TABLE public.credit_transactions
ADD COLUMN IF NOT EXISTS stripe_event_id TEXT;

COMMENT ON COLUMN public.credit_transactions.stripe_event_id IS 'Stripe webhook event ID for tracking';

-- Index for looking up by event ID
CREATE INDEX IF NOT EXISTS idx_credit_transactions_stripe_event
    ON public.credit_transactions(stripe_event_id)
    WHERE stripe_event_id IS NOT NULL;

-- ============================================================================
-- STEP 2: Add UNIQUE constraint on stripe_checkout_session_id
-- This enforces idempotency at the database level - only one transaction
-- per checkout session can ever be created.
-- ============================================================================

-- First, check for any existing duplicates (shouldn't exist, but safety first)
DO $$
DECLARE
    dup_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO dup_count
    FROM (
        SELECT stripe_checkout_session_id
        FROM public.credit_transactions
        WHERE stripe_checkout_session_id IS NOT NULL
        GROUP BY stripe_checkout_session_id
        HAVING COUNT(*) > 1
    ) duplicates;

    IF dup_count > 0 THEN
        RAISE WARNING 'Found % duplicate checkout sessions - manual cleanup required', dup_count;
    END IF;
END $$;

-- Add the UNIQUE constraint (only for non-null values)
CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_transactions_unique_checkout_session
    ON public.credit_transactions(stripe_checkout_session_id)
    WHERE stripe_checkout_session_id IS NOT NULL;

-- ============================================================================
-- STEP 3: Update add_purchased_credits to use INSERT...ON CONFLICT
-- This handles the race condition atomically - the first insert wins,
-- subsequent attempts are safely ignored.
-- ============================================================================

-- Drop the old function first (different signature)
DROP FUNCTION IF EXISTS public.add_purchased_credits(UUID, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.add_purchased_credits(
    p_user_id UUID,
    p_credit_amount INTEGER,
    p_stripe_checkout_session_id TEXT,
    p_stripe_payment_intent_id TEXT DEFAULT NULL,
    p_stripe_event_id TEXT DEFAULT NULL
)
RETURNS public.user_credits
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits public.user_credits;
    v_new_balance INTEGER;
    v_tx_id INTEGER;
BEGIN
    -- Validate inputs
    IF p_credit_amount <= 0 THEN
        RAISE EXCEPTION 'Credit amount must be positive';
    END IF;

    -- Get or create user credits
    v_credits := get_or_create_user_credits(p_user_id);

    -- Calculate new balance
    v_new_balance := v_credits.credit_balance + p_credit_amount;

    -- Attempt to insert transaction - will fail if checkout session already processed
    -- This is the idempotency mechanism - unique constraint prevents duplicates
    BEGIN
        INSERT INTO public.credit_transactions (
            user_id, transaction_type, amount, balance_after,
            description, stripe_checkout_session_id, stripe_payment_intent_id, stripe_event_id
        ) VALUES (
            p_user_id, 'purchase', p_credit_amount, v_new_balance,
            format('Purchased %s credits', p_credit_amount),
            p_stripe_checkout_session_id, p_stripe_payment_intent_id, p_stripe_event_id
        )
        RETURNING id INTO v_tx_id;
    EXCEPTION
        WHEN unique_violation THEN
            -- Checkout session already processed - return current credits
            -- This handles the race condition safely
            RAISE NOTICE 'Checkout session % already processed (idempotency)', p_stripe_checkout_session_id;
            RETURN v_credits;
    END;

    -- Transaction inserted successfully - now add credits
    UPDATE public.user_credits
    SET credit_balance = v_new_balance
    WHERE id = v_credits.id
    RETURNING * INTO v_credits;

    RETURN v_credits;
END;
$$;

COMMENT ON FUNCTION public.add_purchased_credits(UUID, INTEGER, TEXT, TEXT, TEXT) IS
    'Adds purchased credits to user balance. Race-condition safe - uses UNIQUE constraint for idempotency.';

-- ============================================================================
-- STEP 4: Create function to check if a checkout session is already processed
-- This allows the webhook to quickly check without attempting the full operation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_checkout_session_processed(p_session_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.credit_transactions
        WHERE stripe_checkout_session_id = p_session_id
    );
END;
$$;

COMMENT ON FUNCTION public.is_checkout_session_processed IS
    'Quick check if a Stripe checkout session has already been processed';

-- ============================================================================
-- STEP 5: Create webhook event log table for comprehensive tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.stripe_webhook_events (
    id SERIAL PRIMARY KEY,
    event_id TEXT NOT NULL UNIQUE,
    event_type TEXT NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL CHECK (status IN ('success', 'error', 'duplicate')),
    error_message TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_type
    ON public.stripe_webhook_events(event_type);
CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_status
    ON public.stripe_webhook_events(status);
CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_created
    ON public.stripe_webhook_events(created_at);

COMMENT ON TABLE public.stripe_webhook_events IS
    'Log of all Stripe webhook events for monitoring and debugging';

-- RLS for webhook events (admin only, but we'll allow Edge Functions via service role)
ALTER TABLE public.stripe_webhook_events ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 6: Function to log webhook events
-- ============================================================================

CREATE OR REPLACE FUNCTION public.log_stripe_webhook_event(
    p_event_id TEXT,
    p_event_type TEXT,
    p_status TEXT,
    p_error_message TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.stripe_webhook_events (
        event_id, event_type, status, error_message, metadata
    ) VALUES (
        p_event_id, p_event_type, p_status, p_error_message, p_metadata
    )
    ON CONFLICT (event_id) DO UPDATE SET
        -- Allow updating status if we get the same event again
        status = EXCLUDED.status,
        error_message = COALESCE(EXCLUDED.error_message, stripe_webhook_events.error_message),
        processed_at = NOW();

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    -- Don't let logging failures break webhook processing
    RAISE WARNING 'Failed to log webhook event: %', SQLERRM;
    RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION public.log_stripe_webhook_event IS
    'Logs a Stripe webhook event for monitoring. Safe to call multiple times.';
