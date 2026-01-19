-- Migration: Add additional CHECK constraints for data integrity
--
-- Adds constraints to ensure:
-- - Credit transactions have valid amounts for their type
-- - Monthly usage counters are non-negative
-- - Stripe webhook events have valid status

-- ============================================================================
-- STEP 1: Credit transactions - amount sign based on type
-- ============================================================================

-- Add constraint: amount must be non-zero (positive for credits in, could be signed for adjustments)
-- Note: using a DO block to handle if constraint already exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'credit_transactions_amount_non_zero'
    ) THEN
        ALTER TABLE public.credit_transactions
        ADD CONSTRAINT credit_transactions_amount_non_zero
        CHECK (amount <> 0);
    END IF;
END $$;

-- ============================================================================
-- STEP 2: Monthly usage - non-negative counters
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'monthly_usage_counters_non_negative'
    ) THEN
        ALTER TABLE public.monthly_usage
        ADD CONSTRAINT monthly_usage_counters_non_negative
        CHECK (
            total_user_rounds >= 0 AND
            free_tier_user_rounds >= 0 AND
            paid_user_rounds >= 0 AND
            total_chats >= 0 AND
            total_rounds >= 0
        );
    END IF;
END $$;

-- ============================================================================
-- STEP 3: Stripe webhook events - valid status
-- ============================================================================

-- Add constraint: status must be one of the allowed values
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'stripe_webhook_events_status_valid'
    ) THEN
        ALTER TABLE public.stripe_webhook_events
        ADD CONSTRAINT stripe_webhook_events_status_valid
        CHECK (
            status IN ('success', 'error', 'duplicate')
        );
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- Table might not exist yet or already has the constraint
    RAISE NOTICE 'Skipping stripe_webhook_events constraint: %', SQLERRM;
END $$;

-- ============================================================================
-- STEP 4: Billing config - key must be non-empty
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'billing_config_key_non_empty'
    ) THEN
        ALTER TABLE public.billing_config
        ADD CONSTRAINT billing_config_key_non_empty
        CHECK (length(key) > 0);
    END IF;
END $$;

-- ============================================================================
-- STEP 5: Auto refill queue - credits_to_add positive
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'auto_refill_queue_credits_positive'
    ) THEN
        ALTER TABLE public.auto_refill_queue
        ADD CONSTRAINT auto_refill_queue_credits_positive
        CHECK (credits_to_add > 0);
    END IF;
END $$;

-- ============================================================================
-- STEP 6: Invites - email must be valid format
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'invites_email_format'
    ) THEN
        ALTER TABLE public.invites
        ADD CONSTRAINT invites_email_format
        CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
    END IF;
END $$;
