-- Extended billing tests: auto-refill, free tier reset, monthly usage, idempotency
BEGIN;
SELECT plan(43);

-- ============================================================================
-- TEST DATA SETUP
-- ============================================================================

-- Create test users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
    ('b1b2c3d4-e5f6-7890-abcd-ef1234567001'::UUID, 'user1@example.com', 'pass', NOW(), NOW(), NOW()),
    ('b1b2c3d4-e5f6-7890-abcd-ef1234567002'::UUID, 'user2@example.com', 'pass', NOW(), NOW(), NOW()),
    ('b1b2c3d4-e5f6-7890-abcd-ef1234567003'::UUID, 'user3@example.com', 'pass', NOW(), NOW(), NOW());

DO $$
BEGIN
    PERFORM set_config('test.user1_id', 'b1b2c3d4-e5f6-7890-abcd-ef1234567001', TRUE);
    PERFORM set_config('test.user2_id', 'b1b2c3d4-e5f6-7890-abcd-ef1234567002', TRUE);
    PERFORM set_config('test.user3_id', 'b1b2c3d4-e5f6-7890-abcd-ef1234567003', TRUE);
END $$;

-- ============================================================================
-- AUTO-REFILL SCHEMA TESTS
-- ============================================================================

SELECT has_column('user_credits', 'stripe_customer_id', 'user_credits should have stripe_customer_id');
SELECT has_column('user_credits', 'stripe_payment_method_id', 'user_credits should have stripe_payment_method_id');
SELECT has_column('user_credits', 'auto_refill_enabled', 'user_credits should have auto_refill_enabled');
SELECT has_column('user_credits', 'auto_refill_threshold', 'user_credits should have auto_refill_threshold');
SELECT has_column('user_credits', 'auto_refill_amount', 'user_credits should have auto_refill_amount');
SELECT has_column('user_credits', 'auto_refill_last_triggered_at', 'user_credits should have auto_refill_last_triggered_at');
SELECT has_column('user_credits', 'auto_refill_last_error', 'user_credits should have auto_refill_last_error');

SELECT has_table('auto_refill_queue', 'auto_refill_queue table should exist');
SELECT has_column('auto_refill_queue', 'user_id', 'auto_refill_queue should have user_id');
SELECT has_column('auto_refill_queue', 'credits_to_add', 'auto_refill_queue should have credits_to_add');
SELECT has_column('auto_refill_queue', 'status', 'auto_refill_queue should have status');

-- ============================================================================
-- AUTO-REFILL FUNCTION TESTS
-- ============================================================================

SELECT has_function('check_and_queue_auto_refill', 'check_and_queue_auto_refill function should exist');
SELECT has_function('update_auto_refill_settings', 'update_auto_refill_settings function should exist');
SELECT has_function('save_stripe_payment_method', 'save_stripe_payment_method function should exist');

-- Setup user1 with payment method and auto-refill enabled
DO $$
DECLARE
    v_credits public.user_credits;
BEGIN
    -- Create user credits
    v_credits := get_or_create_user_credits(current_setting('test.user1_id')::UUID);

    -- Save payment method
    PERFORM save_stripe_payment_method(
        current_setting('test.user1_id')::UUID,
        'cus_test123',
        'pm_test456'
    );

    -- Enable auto-refill with threshold 50, amount 500
    PERFORM update_auto_refill_settings(
        current_setting('test.user1_id')::UUID,
        TRUE,  -- enabled
        50,    -- threshold
        500    -- amount
    );
END $$;

-- Verify auto-refill settings
SELECT is(
    (SELECT auto_refill_enabled FROM public.user_credits WHERE user_id = current_setting('test.user1_id')::UUID),
    TRUE,
    'Auto-refill should be enabled'
);

SELECT is(
    (SELECT auto_refill_threshold FROM public.user_credits WHERE user_id = current_setting('test.user1_id')::UUID),
    50,
    'Auto-refill threshold should be 50'
);

SELECT is(
    (SELECT auto_refill_amount FROM public.user_credits WHERE user_id = current_setting('test.user1_id')::UUID),
    500,
    'Auto-refill amount should be 500'
);

SELECT is(
    (SELECT stripe_customer_id FROM public.user_credits WHERE user_id = current_setting('test.user1_id')::UUID),
    'cus_test123',
    'Stripe customer ID should be saved'
);

-- Give user credits above threshold first
UPDATE public.user_credits
SET credit_balance = 100
WHERE user_id = current_setting('test.user1_id')::UUID;

SELECT is(
    check_and_queue_auto_refill(current_setting('test.user1_id')::UUID),
    FALSE,
    'Auto-refill should NOT trigger when balance (100) >= threshold (50)'
);

-- Drop balance below threshold
UPDATE public.user_credits
SET credit_balance = 30
WHERE user_id = current_setting('test.user1_id')::UUID;

SELECT is(
    check_and_queue_auto_refill(current_setting('test.user1_id')::UUID),
    TRUE,
    'Auto-refill SHOULD trigger when balance (30) < threshold (50)'
);

-- Verify queue entry created
SELECT is(
    (SELECT COUNT(*)::INT FROM public.auto_refill_queue
     WHERE user_id = current_setting('test.user1_id')::UUID AND status = 'pending'),
    1,
    'Pending queue entry should be created'
);

SELECT is(
    (SELECT credits_to_add FROM public.auto_refill_queue
     WHERE user_id = current_setting('test.user1_id')::UUID AND status = 'pending'),
    500,
    'Queue entry should have correct credits_to_add'
);

-- Test duplicate prevention
SELECT is(
    check_and_queue_auto_refill(current_setting('test.user1_id')::UUID),
    FALSE,
    'Auto-refill should NOT trigger again while pending'
);

-- ============================================================================
-- AUTO-REFILL VALIDATION TESTS
-- ============================================================================

-- Test amount must be > threshold constraint
DO $$
BEGIN
    PERFORM update_auto_refill_settings(
        current_setting('test.user2_id')::UUID,
        TRUE,
        100,  -- threshold
        50    -- amount (less than threshold - should fail)
    );
    RAISE EXCEPTION 'Should have thrown an error';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%must be greater than%' THEN
            NULL; -- Expected
        ELSE
            RAISE;
        END IF;
END $$;

SELECT pass('Amount must be greater than threshold validation works');

-- ============================================================================
-- FREE TIER RESET TESTS
-- ============================================================================

-- Setup user2 with free tier usage in the past
DO $$
DECLARE
    v_credits public.user_credits;
BEGIN
    v_credits := get_or_create_user_credits(current_setting('test.user2_id')::UUID);

    -- Simulate past usage with reset date in the past
    UPDATE public.user_credits
    SET free_tier_used = 300,
        free_tier_reset_at = NOW() - interval '1 day'
    WHERE user_id = current_setting('test.user2_id')::UUID;
END $$;

-- Calling get_or_create should reset free tier
SELECT is(
    (SELECT free_tier_used FROM get_or_create_user_credits(current_setting('test.user2_id')::UUID)),
    0,
    'Free tier should reset when reset_at is in the past'
);

SELECT is(
    (SELECT free_tier_reset_at > NOW() FROM public.user_credits WHERE user_id = current_setting('test.user2_id')::UUID),
    TRUE,
    'Free tier reset_at should be updated to future date'
);

-- ============================================================================
-- MONTHLY USAGE TRACKING TESTS
-- ============================================================================

-- Setup user3 with credits
DO $$
DECLARE
    v_credits public.user_credits;
BEGIN
    v_credits := get_or_create_user_credits(current_setting('test.user3_id')::UUID);

    -- Add some paid credits
    PERFORM add_purchased_credits(
        current_setting('test.user3_id')::UUID,
        1000,
        'cs_test_monthly_usage'
    );
END $$;

-- Deduct some user-rounds to trigger usage tracking
SELECT is(
    deduct_user_rounds(current_setting('test.user3_id')::UUID, 50, NULL, NULL),
    TRUE,
    'Deducting 50 user-rounds should succeed'
);

-- Verify monthly usage record created
SELECT is(
    (SELECT COUNT(*)::INT FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    1,
    'Monthly usage record should be created'
);

SELECT is(
    (SELECT total_user_rounds FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    50,
    'Total user rounds should be 50'
);

SELECT is(
    (SELECT free_tier_user_rounds FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    50,
    'Free tier user rounds should be 50 (used free tier first)'
);

SELECT is(
    (SELECT paid_user_rounds FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    0,
    'Paid user rounds should be 0'
);

-- Deduct more to use some paid credits
SELECT is(
    deduct_user_rounds(current_setting('test.user3_id')::UUID, 500, NULL, NULL),
    TRUE,
    'Deducting 500 more user-rounds should succeed'
);

-- Verify aggregated usage
SELECT is(
    (SELECT total_user_rounds FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    550,
    'Total user rounds should now be 550'
);

SELECT is(
    (SELECT free_tier_user_rounds FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    500,
    'Free tier user rounds should be 500 (maxed out)'
);

SELECT is(
    (SELECT paid_user_rounds FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    50,
    'Paid user rounds should be 50'
);

SELECT is(
    (SELECT total_rounds FROM public.monthly_usage WHERE user_id = current_setting('test.user3_id')::UUID),
    2,
    'Total rounds (transactions) should be 2'
);

-- ============================================================================
-- PURCHASE IDEMPOTENCY TESTS
-- ============================================================================

-- First purchase
SELECT is(
    (SELECT credit_balance FROM add_purchased_credits(
        current_setting('test.user2_id')::UUID,
        500,
        'cs_test_idempotent_123'
    )),
    500,
    'First purchase should add 500 credits'
);

-- Duplicate purchase with same session ID
SELECT is(
    (SELECT credit_balance FROM add_purchased_credits(
        current_setting('test.user2_id')::UUID,
        500,
        'cs_test_idempotent_123'
    )),
    500,
    'Duplicate purchase should NOT add more credits (idempotent)'
);

-- Verify only one transaction
SELECT is(
    (SELECT COUNT(*)::INT FROM public.credit_transactions
     WHERE stripe_checkout_session_id = 'cs_test_idempotent_123'),
    1,
    'Only one transaction should exist for idempotent session'
);

-- Different session should work
SELECT is(
    (SELECT credit_balance FROM add_purchased_credits(
        current_setting('test.user2_id')::UUID,
        200,
        'cs_test_different_456'
    )),
    700,
    'Different session should add credits normally'
);

-- ============================================================================
-- EDGE CASE TESTS
-- ============================================================================

-- Cannot afford more than available
SELECT is(
    can_afford_user_rounds(current_setting('test.user2_id')::UUID, 2000),
    FALSE,
    'User should NOT afford more than available credits'
);

-- Deduction fails when not enough credits
SELECT is(
    deduct_user_rounds(current_setting('test.user2_id')::UUID, 5000, NULL, NULL),
    FALSE,
    'Deduction should fail when insufficient credits'
);

-- Balance unchanged after failed deduction
SELECT is(
    (SELECT credit_balance FROM public.user_credits WHERE user_id = current_setting('test.user2_id')::UUID),
    700,
    'Balance should be unchanged after failed deduction'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.auto_refill_queue WHERE user_id IN (
    current_setting('test.user1_id')::UUID,
    current_setting('test.user2_id')::UUID,
    current_setting('test.user3_id')::UUID
);
DELETE FROM public.credit_transactions WHERE user_id IN (
    current_setting('test.user1_id')::UUID,
    current_setting('test.user2_id')::UUID,
    current_setting('test.user3_id')::UUID
);
DELETE FROM public.monthly_usage WHERE user_id IN (
    current_setting('test.user1_id')::UUID,
    current_setting('test.user2_id')::UUID,
    current_setting('test.user3_id')::UUID
);
DELETE FROM public.user_credits WHERE user_id IN (
    current_setting('test.user1_id')::UUID,
    current_setting('test.user2_id')::UUID,
    current_setting('test.user3_id')::UUID
);
DELETE FROM auth.users WHERE id IN (
    current_setting('test.user1_id')::UUID,
    current_setting('test.user2_id')::UUID,
    current_setting('test.user3_id')::UUID
);

SELECT * FROM finish();
ROLLBACK;
