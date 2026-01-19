-- Tests for billing/credits schema
BEGIN;
SELECT plan(37);

-- ============================================================================
-- TEST DATA SETUP
-- ============================================================================

-- Create a test user in auth.users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID,
    'testuser@example.com',
    'encrypted_password_here',
    NOW(),
    NOW(),
    NOW()
);

-- Store test user ID for later use
DO $$
BEGIN
    PERFORM set_config('test.user_id', 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', TRUE);
END $$;

-- ============================================================================
-- SCHEMA TESTS
-- ============================================================================

SELECT has_table('user_credits', 'user_credits table should exist');
SELECT has_table('credit_transactions', 'credit_transactions table should exist');
SELECT has_table('monthly_usage', 'monthly_usage table should exist');
SELECT has_table('billing_config', 'billing_config table should exist');

-- user_credits columns
SELECT has_column('user_credits', 'user_id', 'user_credits should have user_id column');
SELECT has_column('user_credits', 'credit_balance', 'user_credits should have credit_balance column');
SELECT has_column('user_credits', 'free_tier_used', 'user_credits should have free_tier_used column');
SELECT has_column('user_credits', 'free_tier_reset_at', 'user_credits should have free_tier_reset_at column');

-- credit_transactions columns
SELECT has_column('credit_transactions', 'transaction_type', 'credit_transactions should have transaction_type column');
SELECT has_column('credit_transactions', 'amount', 'credit_transactions should have amount column');
SELECT has_column('credit_transactions', 'stripe_checkout_session_id', 'credit_transactions should have stripe_checkout_session_id column');

-- chats anonymous host column
SELECT has_column('chats', 'host_was_anonymous', 'chats should have host_was_anonymous column');

-- ============================================================================
-- BILLING CONFIG TESTS
-- ============================================================================

SELECT is(
    (SELECT value FROM public.billing_config WHERE key = 'free_tier_monthly_limit'),
    '500',
    'Free tier monthly limit should be 500'
);

SELECT is(
    (SELECT value FROM public.billing_config WHERE key = 'credit_price_cents'),
    '1',
    'Credit price should be 1 cent'
);

SELECT is(
    (SELECT value FROM public.billing_config WHERE key = 'anonymous_chat_max_minutes'),
    '60',
    'Anonymous chat max minutes should be 60'
);

-- ============================================================================
-- FUNCTION TESTS: get_or_create_user_credits
-- ============================================================================

SELECT has_function('get_or_create_user_credits', 'get_or_create_user_credits function should exist');

-- Test creating new user credits record
SELECT is(
    (SELECT credit_balance FROM get_or_create_user_credits(current_setting('test.user_id')::UUID)),
    0,
    'New user should start with 0 credit balance'
);

SELECT is(
    (SELECT free_tier_used FROM get_or_create_user_credits(current_setting('test.user_id')::UUID)),
    0,
    'New user should start with 0 free tier used'
);

-- Verify record was created
SELECT is(
    (SELECT COUNT(*)::INT FROM public.user_credits WHERE user_id = current_setting('test.user_id')::UUID),
    1,
    'User credits record should be created'
);

-- ============================================================================
-- FUNCTION TESTS: can_afford_user_rounds
-- ============================================================================

SELECT has_function('can_afford_user_rounds', 'can_afford_user_rounds function should exist');

-- User with 0 credits and 0 free tier used can afford within free tier
SELECT is(
    can_afford_user_rounds(current_setting('test.user_id')::UUID, 100),
    TRUE,
    'User should afford 100 user-rounds within free tier (500 limit)'
);

SELECT is(
    can_afford_user_rounds(current_setting('test.user_id')::UUID, 500),
    TRUE,
    'User should afford exactly 500 user-rounds (full free tier)'
);

SELECT is(
    can_afford_user_rounds(current_setting('test.user_id')::UUID, 501),
    FALSE,
    'User should NOT afford 501 user-rounds without paid credits'
);

-- ============================================================================
-- FUNCTION TESTS: add_purchased_credits
-- ============================================================================

SELECT has_function('add_purchased_credits', 'add_purchased_credits function should exist');

-- Add credits
SELECT is(
    (SELECT credit_balance FROM add_purchased_credits(
        current_setting('test.user_id')::UUID,
        1000,
        'cs_test_session_123'
    )),
    1000,
    'After purchasing 1000 credits, balance should be 1000'
);

-- Verify transaction recorded
SELECT is(
    (SELECT COUNT(*)::INT FROM public.credit_transactions
     WHERE user_id = current_setting('test.user_id')::UUID
       AND transaction_type = 'purchase'),
    1,
    'Purchase transaction should be recorded'
);

-- Now user can afford more
SELECT is(
    can_afford_user_rounds(current_setting('test.user_id')::UUID, 1500),
    TRUE,
    'User with 1000 paid + 500 free should afford 1500 user-rounds'
);

-- ============================================================================
-- FUNCTION TESTS: deduct_user_rounds
-- ============================================================================

SELECT has_function('deduct_user_rounds', 'deduct_user_rounds function should exist');

-- Deduct from free tier first
SELECT is(
    deduct_user_rounds(current_setting('test.user_id')::UUID, 100, NULL, NULL),
    TRUE,
    'Deducting 100 user-rounds should succeed'
);

-- Verify free tier was used
SELECT is(
    (SELECT free_tier_used FROM public.user_credits WHERE user_id = current_setting('test.user_id')::UUID),
    100,
    'Free tier used should be 100 after deduction'
);

-- Verify paid credits unchanged (should use free tier first)
SELECT is(
    (SELECT credit_balance FROM public.user_credits WHERE user_id = current_setting('test.user_id')::UUID),
    1000,
    'Paid credit balance should still be 1000'
);

-- Deduct more than remaining free tier
SELECT is(
    deduct_user_rounds(current_setting('test.user_id')::UUID, 500, NULL, NULL),
    TRUE,
    'Deducting 500 more user-rounds should succeed (400 free + 100 paid)'
);

-- Verify paid credits now used
SELECT is(
    (SELECT credit_balance FROM public.user_credits WHERE user_id = current_setting('test.user_id')::UUID),
    900,
    'Paid credit balance should be 900 after using 100 paid'
);

-- Test that function accepts BIGINT types (regression test for type mismatch)
-- Using NULL::BIGINT to verify type signature without requiring existing records
SELECT is(
    deduct_user_rounds(current_setting('test.user_id')::UUID, 10, NULL::BIGINT, NULL::BIGINT),
    TRUE,
    'Deducting with BIGINT-typed parameters should succeed'
);

-- ============================================================================
-- ANONYMOUS HOST EXPIRY TESTS
-- ============================================================================

DO $$
DECLARE
    v_chat_id INT;
    v_expires_at TIMESTAMPTZ;
    v_host_was_anonymous BOOLEAN;
BEGIN
    INSERT INTO public.chats (name, initial_message, creator_session_token, start_mode)
    VALUES ('Anon Chat', 'Test', gen_random_uuid(), 'manual')
    RETURNING id, expires_at, host_was_anonymous
    INTO v_chat_id, v_expires_at, v_host_was_anonymous;

    PERFORM set_config('test.anon_chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.anon_chat_expires', v_expires_at::TEXT, TRUE);
    PERFORM set_config('test.anon_chat_host_anon', v_host_was_anonymous::TEXT, TRUE);
END $$;

SELECT is(
    current_setting('test.anon_chat_host_anon')::BOOLEAN,
    TRUE,
    'Chat without creator_id should have host_was_anonymous = TRUE'
);

SELECT is(
    current_setting('test.anon_chat_expires')::TIMESTAMPTZ <= NOW() + interval '65 minutes',
    TRUE,
    'Anonymous host chat should expire within ~1 hour (with margin)'
);

SELECT is(
    current_setting('test.anon_chat_expires')::TIMESTAMPTZ >= NOW() + interval '55 minutes',
    TRUE,
    'Anonymous host chat should expire in at least 55 minutes'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM public.chats WHERE id = current_setting('test.anon_chat_id')::INT;
DELETE FROM public.credit_transactions WHERE user_id = current_setting('test.user_id')::UUID;
DELETE FROM public.monthly_usage WHERE user_id = current_setting('test.user_id')::UUID;
DELETE FROM public.user_credits WHERE user_id = current_setting('test.user_id')::UUID;
DELETE FROM auth.users WHERE id = current_setting('test.user_id')::UUID;

SELECT * FROM finish();
ROLLBACK;
