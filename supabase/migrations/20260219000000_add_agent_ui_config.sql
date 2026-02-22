-- =============================================================================
-- MIGRATION: Add UI-configurable agent system
-- =============================================================================
-- This migration:
-- 1. Adds agent configuration columns to chats table
-- 2. Adds is_agent flag to participants table
-- 3. Updates join_personas_to_chat() to accept max_count parameter
-- 4. Creates auto-join trigger for chat creation
-- 5. Retires the old AI proposer trigger
-- 6. Backfills existing agent chats
-- =============================================================================

-- =============================================================================
-- STEP 1: Add agent configuration columns to chats
-- =============================================================================

ALTER TABLE chats ADD COLUMN enable_agents BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE chats ADD COLUMN proposing_agent_count INTEGER NOT NULL DEFAULT 3
  CHECK (proposing_agent_count >= 1 AND proposing_agent_count <= 5);
ALTER TABLE chats ADD COLUMN rating_agent_count INTEGER NOT NULL DEFAULT 3
  CHECK (rating_agent_count >= 1 AND rating_agent_count <= 5);
ALTER TABLE chats ADD COLUMN agent_instructions TEXT;
ALTER TABLE chats ADD COLUMN agent_configs JSONB;

COMMENT ON COLUMN chats.enable_agents IS
  'Whether AI agents participate in this chat. When true, agents auto-join on creation.';
COMMENT ON COLUMN chats.proposing_agent_count IS
  'Number of agents that participate in the proposing phase (1-5).';
COMMENT ON COLUMN chats.rating_agent_count IS
  'Number of agents that participate in the rating phase (1-5).';
COMMENT ON COLUMN chats.agent_instructions IS
  'Shared instructions appended to all agent system prompts.';
COMMENT ON COLUMN chats.agent_configs IS
  'Per-agent overrides as JSON array: [{"name": "Agent 1", "personality": "..."}, ...]. '
  'Null means use default archetype templates.';

-- =============================================================================
-- STEP 2: Add is_agent flag to participants
-- =============================================================================

ALTER TABLE participants ADD COLUMN is_agent BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN participants.is_agent IS
  'Whether this participant is an AI agent (joined via join_personas_to_chat).';

-- =============================================================================
-- STEP 3: Update join_personas_to_chat() to accept max_count
-- =============================================================================

-- Drop old function signature
DROP FUNCTION IF EXISTS join_personas_to_chat(INTEGER);

CREATE OR REPLACE FUNCTION join_personas_to_chat(
  target_chat_id INTEGER,
  max_count INTEGER DEFAULT NULL
)
RETURNS TABLE (persona_name TEXT, participant_id BIGINT, status TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_persona RECORD;
  v_participant_id BIGINT;
  v_joined INTEGER := 0;
BEGIN
  FOR v_persona IN
    SELECT ap.name, ap.display_name, ap.user_id
    FROM agent_personas ap
    WHERE ap.is_active = true
    ORDER BY ap.id ASC
  LOOP
    -- Respect max_count limit
    IF max_count IS NOT NULL AND v_joined >= max_count THEN
      EXIT;
    END IF;

    -- Check if already joined
    IF EXISTS (
      SELECT 1 FROM participants p
      WHERE p.chat_id = target_chat_id
        AND p.user_id = v_persona.user_id
        AND p.status = 'active'
    ) THEN
      -- Already joined, return existing participant_id
      SELECT p.id INTO v_participant_id
      FROM participants p
      WHERE p.chat_id = target_chat_id
        AND p.user_id = v_persona.user_id
        AND p.status = 'active';

      persona_name := v_persona.name;
      participant_id := v_participant_id;
      status := 'already_joined';
      RETURN NEXT;
    ELSE
      -- Insert new participant with is_agent = true
      INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status, is_agent)
      VALUES (target_chat_id, v_persona.user_id, v_persona.display_name, false, true, 'active', true)
      RETURNING id INTO v_participant_id;

      persona_name := v_persona.name;
      participant_id := v_participant_id;
      status := 'joined';
      RETURN NEXT;
    END IF;

    v_joined := v_joined + 1;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION join_personas_to_chat(INTEGER, INTEGER) IS
  'Joins active agent personas to a target chat as participants. '
  'When max_count is provided, joins at most that many. '
  'Idempotent — skips personas already joined. Returns status per persona.';

-- Restrict access
REVOKE EXECUTE ON FUNCTION join_personas_to_chat(INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- STEP 4: Auto-join trigger on chat creation
-- =============================================================================

CREATE OR REPLACE FUNCTION auto_join_agents_on_chat_create()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.enable_agents THEN
    PERFORM join_personas_to_chat(
      NEW.id,
      GREATEST(NEW.proposing_agent_count, NEW.rating_agent_count)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_join_agents ON chats;

CREATE TRIGGER trg_auto_join_agents
  AFTER INSERT ON chats
  FOR EACH ROW
  EXECUTE FUNCTION auto_join_agents_on_chat_create();

COMMENT ON FUNCTION auto_join_agents_on_chat_create() IS
  'Auto-joins agent personas when a chat is created with enable_agents = true.';

-- =============================================================================
-- STEP 5: Retire the old AI proposer trigger
-- =============================================================================

-- Drop the AI proposer trigger (agents handle proposing now)
DROP TRIGGER IF EXISTS ai_proposer_on_proposing_phase ON rounds;

-- Set default to false for new chats
ALTER TABLE chats ALTER COLUMN enable_ai_participant SET DEFAULT false;

-- Disable AI proposer on all existing chats
UPDATE chats SET enable_ai_participant = false WHERE enable_ai_participant = true;

COMMENT ON COLUMN chats.enable_ai_participant IS
  'DEPRECATED: Use enable_agents instead. AI proposer trigger has been retired.';

-- =============================================================================
-- STEP 6: Backfill existing agent chats
-- =============================================================================

-- Mark existing chats that have agent participants as enable_agents = true
-- Clamp counts to 1-5 in the same statement to satisfy CHECK constraints
UPDATE chats SET
  enable_agents = true,
  proposing_agent_count = LEAST((
    SELECT COUNT(*)::INTEGER FROM participants p
    JOIN agent_personas ap ON ap.user_id = p.user_id
    WHERE p.chat_id = chats.id AND ap.is_active = true AND p.status = 'active'
  ), 5),
  rating_agent_count = LEAST((
    SELECT COUNT(*)::INTEGER FROM participants p
    JOIN agent_personas ap ON ap.user_id = p.user_id
    WHERE p.chat_id = chats.id AND ap.is_active = true AND p.status = 'active'
  ), 5)
WHERE id IN (
  SELECT DISTINCT p.chat_id FROM participants p
  JOIN agent_personas ap ON ap.user_id = p.user_id
  WHERE ap.is_active = true AND p.status = 'active'
);

-- Mark existing agent participants
UPDATE participants SET is_agent = true
WHERE user_id IN (SELECT user_id FROM agent_personas WHERE is_active = true);

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
