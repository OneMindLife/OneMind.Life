-- pgTAP tests for proposition categories state machine
BEGIN;
SELECT plan(27);

-- ============================================================================
-- Schema tests
-- ============================================================================

-- 1. category column exists on propositions
SELECT has_column('public', 'propositions', 'category',
  'propositions should have a category column');

-- 2. category column exists on cycles
SELECT has_column('public', 'cycles', 'category',
  'cycles should have a category column');

-- 3. propositions.category should be nullable
SELECT col_is_null('public', 'propositions', 'category',
  'propositions.category should be nullable');

-- 4. cycles.category should be nullable
SELECT col_is_null('public', 'cycles', 'category',
  'cycles.category should be nullable');

-- ============================================================================
-- State machine function tests
-- ============================================================================

-- 5. get_allowed_categories function exists
SELECT has_function('public', 'get_allowed_categories', ARRAY['text'],
  'get_allowed_categories(text) function should exist');

-- 6. NULL → all initiating categories
SELECT is(
  get_allowed_categories(NULL),
  ARRAY['question','thought','human_task','research_task'],
  'NULL previous category should allow question, thought, human_task, research_task'
);

-- 7. question → all initiating categories
SELECT is(
  get_allowed_categories('question'),
  ARRAY['question','thought','human_task','research_task'],
  'question should allow question, thought, human_task, research_task'
);

-- 8. thought → question only
SELECT is(
  get_allowed_categories('thought'),
  ARRAY['question'],
  'thought should only allow question'
);

-- 9. human_task → human_task_result only
SELECT is(
  get_allowed_categories('human_task'),
  ARRAY['human_task_result'],
  'human_task should only allow human_task_result'
);

-- 10. human_task_result → question only
SELECT is(
  get_allowed_categories('human_task_result'),
  ARRAY['question'],
  'human_task_result should only allow question'
);

-- 11. research_task → all initiating categories (research results are stored, not forced as consensus)
SELECT is(
  get_allowed_categories('research_task'),
  ARRAY['question','thought','human_task','research_task'],
  'research_task should allow question, thought, human_task, research_task'
);

-- 12. research_task_result → question only
SELECT is(
  get_allowed_categories('research_task_result'),
  ARRAY['question'],
  'research_task_result should only allow question'
);

-- ============================================================================
-- RPC tests
-- ============================================================================

-- 13. get_chat_allowed_categories function exists
SELECT has_function('public', 'get_chat_allowed_categories', ARRAY['bigint'],
  'get_chat_allowed_categories(bigint) function should exist');

-- 14. get_chat_allowed_categories is SECURITY DEFINER
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'get_chat_allowed_categories' LIMIT 1),
  true,
  'get_chat_allowed_categories should be SECURITY DEFINER'
);

-- 15. Correct REVOKE/GRANT on get_chat_allowed_categories
-- Verify anon does NOT have execute
SELECT is(
  (SELECT COUNT(*) FROM information_schema.routine_privileges
   WHERE routine_name = 'get_chat_allowed_categories'
     AND grantee = 'anon'
     AND privilege_type = 'EXECUTE')::integer,
  0,
  'anon should NOT have EXECUTE on get_chat_allowed_categories'
);

-- ============================================================================
-- host_force_consensus tests
-- ============================================================================

-- 16. host_force_consensus function exists with 3 params (BIGINT, TEXT, TEXT)
SELECT has_function('public', 'host_force_consensus', ARRAY['bigint','text','text'],
  'host_force_consensus(bigint, text, text) function should exist');

-- 17. host_force_consensus source contains p_category
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'p_category',
  'host_force_consensus source should reference p_category'
);

-- 18. host_force_consensus source contains category validation
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'get_chat_allowed_categories',
  'host_force_consensus should validate category against state machine'
);

-- ============================================================================
-- Trigger update tests (introspection)
-- ============================================================================

-- 19. on_round_winner_set source contains category in SELECT
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'on_round_winner_set' LIMIT 1),
  'category',
  'on_round_winner_set should reference category column'
);

-- 20. on_round_winner_set source contains v_winner_category
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'on_round_winner_set' LIMIT 1),
  'v_winner_category',
  'on_round_winner_set should have v_winner_category variable for cycle denormalization'
);

-- ============================================================================
-- Updated delete_consensus tests
-- ============================================================================

-- 21. delete_consensus source clears category
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus' LIMIT 1),
  'category = NULL',
  'delete_consensus should clear category when resetting a cycle'
);

-- ============================================================================
-- service_role support in host_force_consensus
-- ============================================================================

-- 22. host_force_consensus source supports service_role
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'v_is_service_role',
  'host_force_consensus should detect and handle service_role calls'
);

-- ============================================================================
-- Auto-detect category in host_force_consensus
-- ============================================================================

-- 23. host_force_consensus source contains v_effective_category (auto-detect variable)
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'v_effective_category',
  'host_force_consensus should have v_effective_category for auto-detection'
);

-- 24. host_force_consensus source contains array_length auto-detect logic
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'array_length',
  'host_force_consensus should use array_length for single-category auto-detect'
);

-- 25. host_force_consensus source contains v_allowed[1] (picks the single allowed category)
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'v_allowed\[1\]',
  'host_force_consensus should pick v_allowed[1] when only one category is allowed'
);

-- 26. host_force_consensus returns v_effective_category (not raw p_category)
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'category.*v_effective_category',
  'host_force_consensus should use v_effective_category in cycle UPDATE and return'
);

-- ============================================================================
-- State machine uniqueness property
-- ============================================================================

-- 27. Only 'question' and 'research_task' appear in their own allowed lists
SELECT ok(
  'question' = ANY(get_allowed_categories('question'))
  AND NOT ('thought' = ANY(get_allowed_categories('thought')))
  AND NOT ('human_task' = ANY(get_allowed_categories('human_task')))
  AND 'research_task' = ANY(get_allowed_categories('research_task'))
  AND NOT ('human_task_result' = ANY(get_allowed_categories('human_task_result')))
  AND NOT ('research_task_result' = ANY(get_allowed_categories('research_task_result'))),
  'Only question and research_task should appear in their own allowed categories lists'
);

SELECT * FROM finish();
ROLLBACK;
