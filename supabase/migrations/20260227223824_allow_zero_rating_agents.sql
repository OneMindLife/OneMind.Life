-- =============================================================================
-- MIGRATION: Allow zero rating agents
-- =============================================================================
-- Relaxes the CHECK constraint on rating_agent_count to allow 0.
-- When agents are enabled but "agents also rate" is off, rating_agent_count = 0
-- means no agents participate in the rating phase.
-- =============================================================================

-- Drop the inline CHECK constraint (auto-named by PostgreSQL)
-- and replace with one that allows 0.
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
    AND att.attname = 'rating_agent_count';

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE chats DROP CONSTRAINT %I', v_constraint_name);
  END IF;
END;
$$;

ALTER TABLE chats ADD CONSTRAINT chats_rating_agent_count_check
  CHECK (rating_agent_count >= 0 AND rating_agent_count <= 5);

-- Update default to 0 (agents don't rate unless explicitly enabled)
ALTER TABLE chats ALTER COLUMN rating_agent_count SET DEFAULT 0;

COMMENT ON COLUMN chats.rating_agent_count IS
  'Number of agents that participate in the rating phase (0-5). '
  '0 means agents only propose, they do not rate.';
