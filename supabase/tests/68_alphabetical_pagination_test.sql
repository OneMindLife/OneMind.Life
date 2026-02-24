-- Test that public chat RPC functions return alphabetical order and support pagination.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

-- =============================================================================
-- CLEANUP: Remove any existing public chats that might interfere
-- =============================================================================
DELETE FROM chats WHERE access_method = 'public';

-- =============================================================================
-- SETUP: Create test data
-- =============================================================================
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('d1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1'::UUID, 'pagtest@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
  v_user_id UUID := 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1';
BEGIN
  -- Create public chats with names that sort alphabetically
  INSERT INTO chats (name, initial_message, access_method, creator_session_token)
  VALUES
    ('Delta Chat', 'Message D', 'public', v_user_id),
    ('Alpha Chat', 'Message A', 'public', v_user_id),
    ('Charlie Chat', 'Message C', 'public', v_user_id),
    ('Echo Chat', 'Message E', 'public', v_user_id),
    ('Bravo Chat', 'Message B', 'public', v_user_id);

  PERFORM set_config('test.user_id', v_user_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST: get_public_chats alphabetical order
-- =============================================================================

-- Test 1: First result is alphabetically first
SELECT is(
  (SELECT name FROM get_public_chats(5, 0, NULL) LIMIT 1),
  'Alpha Chat',
  'get_public_chats returns Alpha Chat first (alphabetical)'
);

-- Test 2: All results in alphabetical order
SELECT is(
  (SELECT array_agg(name ORDER BY ordinality)
   FROM get_public_chats(5, 0, NULL) WITH ORDINALITY),
  ARRAY['Alpha Chat', 'Bravo Chat', 'Charlie Chat', 'Delta Chat', 'Echo Chat'],
  'get_public_chats returns all chats in alphabetical order'
);

-- =============================================================================
-- TEST: Offset/limit pagination
-- =============================================================================

-- Test 3: Limit 2 returns only 2 results
SELECT is(
  (SELECT COUNT(*) FROM get_public_chats(2, 0, NULL)),
  2::bigint,
  'get_public_chats with limit=2 returns 2 results'
);

-- Test 4: Offset 2 with limit 2 returns next page
SELECT is(
  (SELECT array_agg(name ORDER BY ordinality)
   FROM get_public_chats(2, 2, NULL) WITH ORDINALITY),
  ARRAY['Charlie Chat', 'Delta Chat'],
  'get_public_chats offset=2 limit=2 returns Charlie and Delta'
);

-- Test 5: Offset beyond total returns empty
SELECT is(
  (SELECT COUNT(*) FROM get_public_chats(20, 100, NULL)),
  0::bigint,
  'get_public_chats with offset beyond total returns empty'
);

-- =============================================================================
-- TEST: search_public_chats with offset, alphabetical
-- =============================================================================

-- Test 6: Search returns matching results alphabetically
SELECT is(
  (SELECT array_agg(name ORDER BY ordinality)
   FROM search_public_chats('Chat', 20, 0, NULL) WITH ORDINALITY),
  ARRAY['Alpha Chat', 'Bravo Chat', 'Charlie Chat', 'Delta Chat', 'Echo Chat'],
  'search_public_chats returns matching results in alphabetical order'
);

-- Test 7: Search with offset paginates correctly
SELECT is(
  (SELECT array_agg(name ORDER BY ordinality)
   FROM search_public_chats('Chat', 2, 2, NULL) WITH ORDINALITY),
  ARRAY['Charlie Chat', 'Delta Chat'],
  'search_public_chats offset=2 limit=2 returns Charlie and Delta'
);

-- =============================================================================
-- TEST: Translated variants alphabetical + offset
-- =============================================================================

-- Test 8: get_public_chats_translated returns alphabetical order
SELECT is(
  (SELECT name FROM get_public_chats_translated(5, 0, NULL, 'en') LIMIT 1),
  'Alpha Chat',
  'get_public_chats_translated returns Alpha Chat first (alphabetical)'
);

-- Test 9: get_public_chats_translated pagination works
SELECT is(
  (SELECT COUNT(*) FROM get_public_chats_translated(2, 2, NULL, 'en')),
  2::bigint,
  'get_public_chats_translated offset=2 limit=2 returns 2 results'
);

-- Test 10: search_public_chats_translated returns alphabetical order
SELECT is(
  (SELECT name FROM search_public_chats_translated('Chat', 20, 0, NULL, 'en') LIMIT 1),
  'Alpha Chat',
  'search_public_chats_translated returns Alpha Chat first (alphabetical)'
);

SELECT * FROM finish();
ROLLBACK;
