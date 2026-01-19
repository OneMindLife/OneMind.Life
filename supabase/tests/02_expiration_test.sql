-- Expiration and rate limiting tests
BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- =============================================================================
-- EXPIRATION FOR ANONYMOUS CHATS
-- =============================================================================

-- Test 1: Anonymous chat gets expiration
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Anon Chat', 'Anonymous topic', gen_random_uuid());

SELECT ok(
  (SELECT expires_at FROM chats WHERE name = 'Anon Chat') IS NOT NULL,
  'Anonymous chat has expiration date set'
);

-- Test 2: Expiration is in the future
SELECT ok(
  (SELECT expires_at FROM chats WHERE name = 'Anon Chat') > NOW(),
  'Anonymous chat expires in the future'
);

-- Test 3: last_activity_at is set on creation
SELECT ok(
  (SELECT last_activity_at FROM chats WHERE name = 'Anon Chat') IS NOT NULL,
  'last_activity_at is set on chat creation'
);

-- =============================================================================
-- CHAT DEFAULTS
-- =============================================================================

-- Test 4: is_active defaults to true
SELECT is(
  (SELECT is_active FROM chats WHERE name = 'Anon Chat'),
  TRUE,
  'is_active defaults to true'
);

-- Test 5: access_method defaults to public
SELECT is(
  (SELECT access_method FROM chats WHERE name = 'Anon Chat'),
  'public',
  'access_method defaults to public'
);

-- Test 6: require_auth defaults to false
SELECT is(
  (SELECT require_auth FROM chats WHERE name = 'Anon Chat'),
  FALSE,
  'require_auth defaults to false'
);

-- Test 7: require_approval defaults to false
SELECT is(
  (SELECT require_approval FROM chats WHERE name = 'Anon Chat'),
  FALSE,
  'require_approval defaults to false'
);

-- Test 8: is_official defaults to false
SELECT is(
  (SELECT is_official FROM chats WHERE name = 'Anon Chat'),
  FALSE,
  'is_official defaults to false'
);

SELECT * FROM finish();
ROLLBACK;
