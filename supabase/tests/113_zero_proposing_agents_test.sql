-- =============================================================================
-- Tests for the zero-proposing-agents constraint relaxation.
-- Migration: 20260602130000_allow_zero_proposing_agents.sql
-- =============================================================================
-- A humans-only group chat is created with proposing_agent_count = 0. Guard
-- that 0 is allowed (regression — the old constraint required >= 1 and broke
-- group-fork chat creation) while the 0..5 bounds still hold.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

-- 0 proposing agents must be allowed (the humans-only case)
SELECT lives_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token,
       proposing_agent_count, rating_agent_count, enable_agents)
     VALUES ('zero proposing agents', 'q', gen_random_uuid(), 0, 0, false)$$,
  'proposing_agent_count = 0 is allowed (humans-only chat)'
);

-- upper bound still enforced
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_agent_count)
     VALUES ('too many agents', 'q', gen_random_uuid(), 6)$$,
  NULL,
  'proposing_agent_count = 6 still rejected (max 5)'
);

-- negative still rejected
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_agent_count)
     VALUES ('negative agents', 'q', gen_random_uuid(), -1)$$,
  NULL,
  'proposing_agent_count = -1 still rejected'
);

SELECT * FROM finish();
ROLLBACK;
