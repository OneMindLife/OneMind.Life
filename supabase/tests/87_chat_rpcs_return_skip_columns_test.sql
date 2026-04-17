-- =============================================================================
-- TEST: Chat RPCs return allow_skip_proposing and allow_skip_rating columns
-- =============================================================================
-- Verifies that all chat-returning RPCs include the skip settings columns
-- so that Chat.fromJson receives the correct values instead of defaulting.
-- =============================================================================

BEGIN;
SELECT plan(10);

-- Test 1-2: chats table has the columns
SELECT has_column('public', 'chats', 'allow_skip_proposing',
  'chats table has allow_skip_proposing column');
SELECT has_column('public', 'chats', 'allow_skip_rating',
  'chats table has allow_skip_rating column');

-- Test 3-4: get_chat_translated includes skip columns in body
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_chat_translated' AND pronamespace = 'public'::regnamespace),
  'allow_skip_proposing',
  'get_chat_translated selects allow_skip_proposing'
);
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_chat_translated' AND pronamespace = 'public'::regnamespace),
  'allow_skip_rating',
  'get_chat_translated selects allow_skip_rating'
);

-- Test 5-6: get_chat_by_code_translated includes skip columns
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_chat_by_code_translated' AND pronamespace = 'public'::regnamespace),
  'allow_skip_proposing',
  'get_chat_by_code_translated selects allow_skip_proposing'
);
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_chat_by_code_translated' AND pronamespace = 'public'::regnamespace),
  'allow_skip_rating',
  'get_chat_by_code_translated selects allow_skip_rating'
);

-- Test 7-8: get_my_chats_translated includes skip columns
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_my_chats_translated' AND pronamespace = 'public'::regnamespace),
  'allow_skip_proposing',
  'get_my_chats_translated selects allow_skip_proposing'
);
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_my_chats_translated' AND pronamespace = 'public'::regnamespace),
  'allow_skip_rating',
  'get_my_chats_translated selects allow_skip_rating'
);

-- Test 9-10: get_my_chats_dashboard includes skip columns
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_my_chats_dashboard' AND pronamespace = 'public'::regnamespace),
  'allow_skip_proposing',
  'get_my_chats_dashboard selects allow_skip_proposing'
);
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'get_my_chats_dashboard' AND pronamespace = 'public'::regnamespace),
  'allow_skip_rating',
  'get_my_chats_dashboard selects allow_skip_rating'
);

SELECT * FROM finish();
ROLLBACK;
