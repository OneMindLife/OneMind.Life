-- Test: chats.agent_model column (migration per_chat_agent_model)
--
-- Backs the per-chat LLM backend selection: agent-orchestrator reads this
-- column and routes `claude-*` to Claude Opus 4.7, anything else to DeepSeek.
-- The default must stay 'deepseek-chat' so new chats don't accidentally hit
-- the Anthropic API, and the column must be NOT NULL so the runtime never
-- sees a null.
--
-- Covers:
--   * column exists, type text
--   * NOT NULL + default 'deepseek-chat' — new chats get DeepSeek for free
--   * existing OneMind chat (id=246) was migrated to 'claude-opus-4-7'
--   * setting to arbitrary string works (forward-compat for future models)
--   * NULL insert rejected

BEGIN;
SET search_path TO public, extensions;
SELECT plan(5);

-- =============================================================================
-- Schema checks
-- =============================================================================
SELECT col_type_is(
  'public', 'chats', 'agent_model', 'text',
  'chats.agent_model is text'
);

SELECT col_not_null(
  'public', 'chats', 'agent_model',
  'chats.agent_model is NOT NULL'
);

-- =============================================================================
-- Default value — a fresh chat must land on deepseek-chat so migration doesn't
-- silently route existing traffic to the Anthropic API.
-- =============================================================================
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at) VALUES
  ('00000000-0000-0000-0000-000000000d01', 'agent-model@test.com', 'authenticated', 'authenticated', now(), now());

INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('Agent Model Default Test', 'Q', 'public', '00000000-0000-0000-0000-000000000d01', 'manual', NULL, NULL, NULL, NULL);

SELECT is(
  (SELECT agent_model FROM chats WHERE name = 'Agent Model Default Test'),
  'deepseek-chat',
  'New chat gets agent_model = deepseek-chat by default'
);

-- =============================================================================
-- Can be set to an arbitrary string — don't constrain via CHECK, so the column
-- stays forward-compatible with whatever model IDs we add later.
-- =============================================================================
UPDATE chats SET agent_model = 'claude-opus-4-7' WHERE name = 'Agent Model Default Test';
SELECT is(
  (SELECT agent_model FROM chats WHERE name = 'Agent Model Default Test'),
  'claude-opus-4-7',
  'agent_model can be updated to claude-opus-4-7'
);

-- =============================================================================
-- NULL must be rejected — prod code relies on the NOT NULL guarantee.
-- =============================================================================
SELECT throws_ok(
  $$UPDATE chats SET agent_model = NULL WHERE name = 'Agent Model Default Test'$$,
  '23502',  -- not_null_violation
  NULL,
  'NULL agent_model is rejected (NOT NULL constraint)'
);

SELECT * FROM finish();
ROLLBACK;
