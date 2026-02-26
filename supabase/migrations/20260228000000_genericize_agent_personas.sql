-- =============================================================================
-- MIGRATION: Genericize agent personas for dynamic persona generation
-- =============================================================================
-- This migration:
-- 1. Updates display_name to generic placeholders ("Agent 1" through "Agent 6")
-- 2. Clears system_prompt (forces fallback to DEFAULT_ARCHETYPES or dynamic gen)
-- 3. Replaces auto_join_agents_on_chat_create() to read agent_configs names
-- =============================================================================
-- Background:
-- Agent personas were hardcoded with startup-evaluation-specific names/prompts
-- ("The Executor", "The Demand Detector", etc.). When users created chats about
-- ANY topic, these startup personas were joined with wrong display names and
-- wrong fallback prompts. The orchestrator already has generateDynamicPersonas()
-- that generates topic-specific personas via Gemini when agent_configs IS NULL.
-- This migration genericizes the DB rows so the dynamic generation path works
-- correctly from the start.
-- =============================================================================

-- =============================================================================
-- STEP 1: Update display names to generic placeholders
-- =============================================================================

UPDATE agent_personas SET display_name = 'Agent 1' WHERE name = 'the_executor';
UPDATE agent_personas SET display_name = 'Agent 2' WHERE name = 'the_demand_detector';
UPDATE agent_personas SET display_name = 'Agent 3' WHERE name = 'the_clock';
UPDATE agent_personas SET display_name = 'Agent 4' WHERE name = 'the_compounder';
UPDATE agent_personas SET display_name = 'Agent 5' WHERE name = 'the_breaker';
UPDATE agent_personas SET display_name = 'Agent 6' WHERE name = 'the_advocate';

-- =============================================================================
-- STEP 2: Clear system prompts
-- =============================================================================
-- Empty string is falsy in JS, so resolvePersonality() will skip priority 2
-- (persona.system_prompt) and fall through to priority 3 (DEFAULT_ARCHETYPES).

UPDATE agent_personas SET system_prompt = '' WHERE is_active = true;

-- =============================================================================
-- STEP 3: Replace auto_join_agents_on_chat_create() trigger function
-- =============================================================================
-- The old trigger simply called join_personas_to_chat() which always used the
-- DB display_name. The new version inlines the join logic and reads
-- NEW.agent_configs for display names when available.

CREATE OR REPLACE FUNCTION auto_join_agents_on_chat_create()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_max_count INTEGER;
  v_persona RECORD;
  v_idx INTEGER := 0;
  v_display_name TEXT;
BEGIN
  IF NEW.enable_agents THEN
    v_max_count := GREATEST(NEW.proposing_agent_count, NEW.rating_agent_count);

    FOR v_persona IN
      SELECT ap.name, ap.display_name, ap.user_id
      FROM agent_personas ap
      WHERE ap.is_active = true
      ORDER BY ap.id ASC
    LOOP
      EXIT WHEN v_idx >= v_max_count;

      -- Use name from agent_configs if available, else generic placeholder
      IF NEW.agent_configs IS NOT NULL
         AND v_idx < jsonb_array_length(NEW.agent_configs) THEN
        v_display_name := COALESCE(
          NEW.agent_configs -> v_idx ->> 'name',
          v_persona.display_name
        );
      ELSE
        v_display_name := v_persona.display_name;
      END IF;

      INSERT INTO participants (
        chat_id, user_id, display_name, is_host, is_authenticated, status, is_agent
      ) VALUES (
        NEW.id, v_persona.user_id, v_display_name, false, true, 'active', true
      ) ON CONFLICT DO NOTHING;

      v_idx := v_idx + 1;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
-- Post-deploy verification:
-- 1. SELECT name, display_name, LEFT(system_prompt, 30) FROM agent_personas ORDER BY id;
--    Expected: Agent 1..6, all prompts empty
-- 2. Create a test chat with enable_agents=true, verify participants get generic names
-- 3. Orchestrator will generate dynamic personas on first dispatch
-- =============================================================================
