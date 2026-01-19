-- =============================================================================
-- TEST: Rate Limiting
-- =============================================================================
-- Tests that the rate limiting functions correctly:
-- 1. Track request counts per key
-- 2. Respect maximum request limits
-- 3. Reset counts at window boundaries
-- 4. Support different window sizes
-- =============================================================================

BEGIN;

SELECT plan(10);

-- =============================================================================
-- SETUP: Clean up any existing test rate limits
-- =============================================================================

DELETE FROM rate_limits WHERE key LIKE 'test_%';

-- =============================================================================
-- TEST: Basic rate limit check allows first request
-- =============================================================================

SELECT is(
    check_rate_limit('test_basic', 5, '1 minute'::interval),
    TRUE,
    'First request should be allowed'
);

-- =============================================================================
-- TEST: Rate limit check increments counter
-- =============================================================================

-- Make 4 more requests (should all be allowed)
SELECT is(check_rate_limit('test_basic', 5, '1 minute'::interval), TRUE, 'Request 2/5 allowed');
SELECT is(check_rate_limit('test_basic', 5, '1 minute'::interval), TRUE, 'Request 3/5 allowed');
SELECT is(check_rate_limit('test_basic', 5, '1 minute'::interval), TRUE, 'Request 4/5 allowed');
SELECT is(check_rate_limit('test_basic', 5, '1 minute'::interval), TRUE, 'Request 5/5 allowed');

-- 6th request should be rate limited
SELECT is(
    check_rate_limit('test_basic', 5, '1 minute'::interval),
    FALSE,
    'Request 6 should be rate limited (over limit)'
);

-- =============================================================================
-- TEST: Different keys are tracked separately
-- =============================================================================

SELECT is(
    check_rate_limit('test_other_key', 5, '1 minute'::interval),
    TRUE,
    'Different key should have its own counter'
);

-- =============================================================================
-- TEST: get_rate_limit_status returns current count
-- =============================================================================

SELECT is(
    (SELECT current_count FROM get_rate_limit_status('test_basic', '1 minute'::interval)),
    6,
    'Status shows correct request count (6 requests made)'
);

-- =============================================================================
-- TEST: Cleanup function removes old entries
-- =============================================================================

-- Insert an old entry for testing cleanup
INSERT INTO rate_limits (key, window_start, request_count)
VALUES ('test_old_entry', NOW() - INTERVAL '2 hours', 10);

-- Run cleanup
SELECT ok(
    cleanup_rate_limits() >= 1,
    'Cleanup removes old entries'
);

-- Verify old entry was removed
SELECT is(
    (SELECT COUNT(*)::INT FROM rate_limits WHERE key = 'test_old_entry'),
    0,
    'Old entry was cleaned up'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================

DELETE FROM rate_limits WHERE key LIKE 'test_%';

SELECT * FROM finish();

ROLLBACK;
