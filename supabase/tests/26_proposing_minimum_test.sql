-- Test proposing_minimum constraint (minimum 3)
BEGIN;

SELECT plan(5);

-- =============================================================================
-- Test 1: Cannot set proposing_minimum below 3
-- =============================================================================

SELECT throws_ok(
    $$INSERT INTO chats (name, initial_message, proposing_minimum, access_method)
      VALUES ('Test Chat', 'Test', 2, 'code')$$,
    '23514',  -- check_violation
    NULL,
    'Cannot create chat with proposing_minimum = 2 (below minimum 3)'
);

SELECT throws_ok(
    $$INSERT INTO chats (name, initial_message, proposing_minimum, access_method)
      VALUES ('Test Chat', 'Test', 1, 'code')$$,
    '23514',
    NULL,
    'Cannot create chat with proposing_minimum = 1 (below minimum 3)'
);

-- =============================================================================
-- Test 2: Can set proposing_minimum to 3 or higher
-- =============================================================================

SELECT lives_ok(
    $$INSERT INTO chats (name, initial_message, proposing_minimum, access_method)
      VALUES ('Test Chat Min 3', 'Test', 3, 'code')$$,
    'Can create chat with proposing_minimum = 3'
);

SELECT lives_ok(
    $$INSERT INTO chats (name, initial_message, proposing_minimum, access_method)
      VALUES ('Test Chat Min 5', 'Test', 5, 'code')$$,
    'Can create chat with proposing_minimum = 5'
);

-- =============================================================================
-- Test 3: Default value is 3
-- =============================================================================

INSERT INTO chats (name, initial_message, access_method)
VALUES ('Test Chat Default', 'Test', 'code');

SELECT is(
    (SELECT proposing_minimum FROM chats WHERE name = 'Test Chat Default'),
    3,
    'Default proposing_minimum should be 3'
);

-- Cleanup
DELETE FROM chats WHERE name LIKE 'Test Chat%';

SELECT * FROM finish();

ROLLBACK;
