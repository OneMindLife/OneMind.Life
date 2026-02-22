BEGIN;
SELECT plan(16);

-- =============================================================================
-- Test 1-5: New columns exist on chats table
-- =============================================================================

SELECT has_column('public', 'chats', 'enable_agents',
  'chats should have enable_agents column');

SELECT has_column('public', 'chats', 'proposing_agent_count',
  'chats should have proposing_agent_count column');

SELECT has_column('public', 'chats', 'rating_agent_count',
  'chats should have rating_agent_count column');

SELECT has_column('public', 'chats', 'agent_instructions',
  'chats should have agent_instructions column');

SELECT has_column('public', 'chats', 'agent_configs',
  'chats should have agent_configs column');

-- =============================================================================
-- Test 6: is_agent column exists on participants
-- =============================================================================

SELECT has_column('public', 'participants', 'is_agent',
  'participants should have is_agent column');

-- =============================================================================
-- Test 7-8: Default values are correct
-- =============================================================================

SELECT col_default_is('public', 'chats', 'enable_agents', 'false',
  'enable_agents should default to false');

SELECT col_default_is('public', 'chats', 'proposing_agent_count', '3',
  'proposing_agent_count should default to 3');

-- =============================================================================
-- Test 9-10: CHECK constraints on agent counts
-- =============================================================================

SELECT col_has_check('public', 'chats', 'proposing_agent_count',
  'proposing_agent_count should have CHECK constraint');

SELECT col_has_check('public', 'chats', 'rating_agent_count',
  'rating_agent_count should have CHECK constraint');

-- =============================================================================
-- Test 11: join_personas_to_chat function exists with updated signature
-- =============================================================================

SELECT has_function('public', 'join_personas_to_chat', ARRAY['bigint', 'integer'],
  'join_personas_to_chat(bigint, integer) should exist');

-- =============================================================================
-- Test 12: auto_join_agents_on_chat_create function exists
-- =============================================================================

SELECT has_function('public', 'auto_join_agents_on_chat_create', '{}',
  'auto_join_agents_on_chat_create() trigger function should exist');

-- =============================================================================
-- Test 13: Auto-join trigger exists on chats
-- =============================================================================

SELECT has_trigger('public', 'chats', 'trg_auto_join_agents',
  'trg_auto_join_agents trigger should exist on chats');

-- =============================================================================
-- Test 14: AI proposer trigger is dropped
-- =============================================================================

SELECT hasnt_trigger('public', 'rounds', 'ai_proposer_on_proposing_phase',
  'ai_proposer_on_proposing_phase trigger should be dropped');

-- =============================================================================
-- Test 15: AI proposer default is now false
-- =============================================================================

SELECT col_default_is('public', 'chats', 'enable_ai_participant', 'false',
  'enable_ai_participant should default to false (retired)');

-- =============================================================================
-- Test 16: is_agent default is false
-- =============================================================================

SELECT col_default_is('public', 'participants', 'is_agent', 'false',
  'is_agent should default to false');

SELECT * FROM finish();
ROLLBACK;
