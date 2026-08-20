-- =============================================================================
-- MIGRATION: Allow zero proposing agents (humans-only chat)
-- =============================================================================
-- The real group-fork quick chat ("Let's get them from the group" → "Create a
-- chat to share") creates a humans-only chat with proposing_agent_count = 0
-- (enable_agents = false). But the original constraint from
-- 20260219000000_add_agent_ui_config.sql required proposing_agent_count >= 1,
-- so creating that chat failed with:
--   new row for relation "chats" violates check constraint
--   "chats_proposing_agent_count_check"
--
-- Relax it to allow 0 — mirroring the rating side, which was already relaxed in
-- 20260227223824_allow_zero_rating_agents.sql. 0 = no proposing agents (real
-- people propose). Agents only ever spawn when enable_agents = true, so a 0
-- count on a humans-only chat is correct, not a degenerate state.
-- =============================================================================

-- Drop the inline CHECK constraint (auto-named by PostgreSQL) and replace it.
DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  SELECT con.conname INTO v_constraint_name
  FROM pg_constraint con
  JOIN pg_attribute att ON att.attnum = ANY(con.conkey)
    AND att.attrelid = con.conrelid
  WHERE con.conrelid = 'chats'::regclass
    AND con.contype = 'c'
    AND att.attname = 'proposing_agent_count';

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE chats DROP CONSTRAINT %I', v_constraint_name);
  END IF;
END;
$$;

ALTER TABLE chats ADD CONSTRAINT chats_proposing_agent_count_check
  CHECK (proposing_agent_count >= 0 AND proposing_agent_count <= 5);

COMMENT ON COLUMN chats.proposing_agent_count IS
  'Number of agents that propose (0-5). 0 = humans-only chat (no proposing agents).';
