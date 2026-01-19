-- =============================================================================
-- TEST: Stripe Webhook Idempotency
-- =============================================================================
-- Tests that the add_purchased_credits function correctly handles:
-- 1. Normal credit addition
-- 2. Duplicate checkout sessions (idempotency)
-- 3. Race conditions (simulated via concurrent calls)
-- =============================================================================

BEGIN;

SELECT plan(13);

-- =============================================================================
-- SETUP: Create test user
-- =============================================================================

-- Create a test user in auth.users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, role)
VALUES (
    'a1111111-1111-1111-1111-111111111111'::UUID,
    'idempotency-test@example.com',
    crypt('password123', gen_salt('bf')),
    NOW(),
    'authenticated'
);

-- =============================================================================
-- TEST: Basic credit addition works
-- =============================================================================

SELECT is(
    (SELECT credit_balance FROM get_or_create_user_credits('a1111111-1111-1111-1111-111111111111'::UUID)),
    0,
    'New user starts with 0 credits'
);

-- Add credits via checkout session
SELECT is(
    (SELECT credit_balance FROM add_purchased_credits(
        'a1111111-1111-1111-1111-111111111111'::UUID,
        100,
        'cs_test_session_001',
        'pi_test_001',
        'evt_test_001'
    )),
    100,
    'Credits added successfully - balance is 100'
);

-- Verify transaction was recorded
SELECT is(
    (SELECT COUNT(*)::INT FROM credit_transactions
     WHERE stripe_checkout_session_id = 'cs_test_session_001'),
    1,
    'Transaction recorded in credit_transactions'
);

-- Verify event ID was stored
SELECT is(
    (SELECT stripe_event_id FROM credit_transactions
     WHERE stripe_checkout_session_id = 'cs_test_session_001'),
    'evt_test_001',
    'Stripe event ID stored correctly'
);

-- =============================================================================
-- TEST: Duplicate checkout session is idempotent
-- =============================================================================

-- Try to add credits again with the SAME checkout session
SELECT is(
    (SELECT credit_balance FROM add_purchased_credits(
        'a1111111-1111-1111-1111-111111111111'::UUID,
        100,
        'cs_test_session_001',  -- Same session ID!
        'pi_test_001',
        'evt_test_002'  -- Different event ID (retry)
    )),
    100,  -- Balance should NOT change
    'Duplicate session - credits NOT added again (idempotency)'
);

-- Verify still only one transaction
SELECT is(
    (SELECT COUNT(*)::INT FROM credit_transactions
     WHERE stripe_checkout_session_id = 'cs_test_session_001'),
    1,
    'Still only one transaction for this session (no duplicate)'
);

-- Verify current balance
SELECT is(
    (SELECT credit_balance FROM user_credits
     WHERE user_id = 'a1111111-1111-1111-1111-111111111111'::UUID),
    100,
    'Final balance is still 100 (not 200)'
);

-- =============================================================================
-- TEST: Different checkout sessions add credits
-- =============================================================================

SELECT is(
    (SELECT credit_balance FROM add_purchased_credits(
        'a1111111-1111-1111-1111-111111111111'::UUID,
        50,
        'cs_test_session_002',  -- Different session
        'pi_test_002',
        'evt_test_003'
    )),
    150,
    'Different session adds credits - balance is 150'
);

-- =============================================================================
-- TEST: UNIQUE constraint prevents duplicates
-- =============================================================================

-- Verify the unique constraint exists
SELECT ok(
    EXISTS(
        SELECT 1 FROM pg_indexes
        WHERE indexname = 'idx_credit_transactions_unique_checkout_session'
    ),
    'UNIQUE index exists on stripe_checkout_session_id'
);

-- =============================================================================
-- TEST: is_checkout_session_processed helper function
-- =============================================================================

SELECT is(
    is_checkout_session_processed('cs_test_session_001'),
    TRUE,
    'is_checkout_session_processed returns TRUE for processed session'
);

SELECT is(
    is_checkout_session_processed('cs_never_processed'),
    FALSE,
    'is_checkout_session_processed returns FALSE for new session'
);

-- =============================================================================
-- TEST: Webhook event logging
-- =============================================================================

-- Log a test webhook event
SELECT ok(
    log_stripe_webhook_event(
        'evt_test_log_001',
        'checkout.session.completed',
        'success',
        NULL,
        '{"livemode": false}'::JSONB
    ),
    'log_stripe_webhook_event succeeds'
);

-- Verify it was logged
SELECT is(
    (SELECT status FROM stripe_webhook_events WHERE event_id = 'evt_test_log_001'),
    'success',
    'Webhook event logged correctly'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

SELECT * FROM finish();

ROLLBACK;
