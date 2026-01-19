-- Test that Discover filters out chats the user has already joined
-- Updated to use auth.uid() instead of session tokens.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- =============================================================================
-- CLEANUP: Remove any existing public chats that might interfere
-- =============================================================================
DELETE FROM chats WHERE access_method = 'public';

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

-- Create test auth users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'user1@test.com', 'pass', NOW(), NOW(), NOW()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'user2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID, 'newuser@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
  v_user1_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_user2_id UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_chat1_id BIGINT;
  v_chat2_id BIGINT;
  v_chat3_id BIGINT;
BEGIN
  -- Create public chats (using creator_session_token for compatibility with existing schema)
  INSERT INTO chats (name, initial_message, access_method, creator_session_token)
  VALUES ('Public Chat 1', 'Topic 1', 'public', v_user1_id)
  RETURNING id INTO v_chat1_id;

  INSERT INTO chats (name, initial_message, access_method, creator_session_token)
  VALUES ('Public Chat 2', 'Topic 2', 'public', v_user1_id)
  RETURNING id INTO v_chat2_id;

  INSERT INTO chats (name, initial_message, access_method, creator_session_token)
  VALUES ('Public Chat 3', 'Topic 3', 'public', v_user2_id)
  RETURNING id INTO v_chat3_id;

  -- User1 joins Chat 1 as host (with user_id)
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat1_id, v_user1_id, 'User1', TRUE, 'active');

  -- User1 also joins Chat 2
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat2_id, v_user1_id, 'User1', FALSE, 'active');

  -- User2 joins Chat 3
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat3_id, v_user2_id, 'User2', TRUE, 'active');

  PERFORM set_config('test.user1_id', v_user1_id::TEXT, TRUE);
  PERFORM set_config('test.user2_id', v_user2_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST: get_public_chats filtering
-- =============================================================================

-- Test 1: Without user_id, all public chats are returned
SELECT is(
  (SELECT COUNT(*) FROM get_public_chats(20, 0, NULL)),
  3::bigint,
  'Without session token, all 3 public chats are returned'
);

-- Test 2: User1 should only see Chat 3 (not their own chats)
SELECT is(
  (SELECT COUNT(*) FROM get_public_chats(20, 0, current_setting('test.user1_id')::UUID)),
  1::bigint,
  'User1 sees only 1 chat (not their joined chats)'
);

-- Test 3: User1 should see Chat 3 specifically
SELECT is(
  (SELECT name FROM get_public_chats(20, 0, current_setting('test.user1_id')::UUID)),
  'Public Chat 3',
  'User1 sees Public Chat 3 (the one they have not joined)'
);

-- Test 4: User2 should see Chats 1 and 2 (not Chat 3)
SELECT is(
  (SELECT COUNT(*) FROM get_public_chats(20, 0, current_setting('test.user2_id')::UUID)),
  2::bigint,
  'User2 sees 2 chats (not their joined chat)'
);

-- Test 5: New user (no chats) should see all 3
SELECT is(
  (SELECT COUNT(*) FROM get_public_chats(20, 0, 'cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID)),
  3::bigint,
  'New user with no chats sees all 3 public chats'
);

-- =============================================================================
-- TEST: search_public_chats filtering
-- =============================================================================

-- Test 6: Search without user_id returns matching chats
SELECT is(
  (SELECT COUNT(*) FROM search_public_chats('Topic', 20, NULL)),
  3::bigint,
  'Search without session token returns all 3 matching chats'
);

-- Test 7: User1 search should filter out their chats
SELECT is(
  (SELECT COUNT(*) FROM search_public_chats('Topic', 20, current_setting('test.user1_id')::UUID)),
  1::bigint,
  'User1 search returns only 1 matching chat (filtered)'
);

-- Test 8: User1 search for specific term finds correct chat
SELECT is(
  (SELECT name FROM search_public_chats('Topic 3', 20, current_setting('test.user1_id')::UUID)),
  'Public Chat 3',
  'User1 search for Topic 3 finds Public Chat 3'
);

SELECT * FROM finish();
ROLLBACK;
