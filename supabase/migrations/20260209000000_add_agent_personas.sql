-- =============================================================================
-- MIGRATION: Add agent personas for multi-persona consensus agents
-- =============================================================================
-- This migration:
-- 1. Creates agent_personas table to store persona definitions
-- 2. Creates 5 pseudo-users in auth.users for the agents
-- 3. Seeds 5 persona rows with unique measuring-stick system prompts
-- 4. Creates join_personas_to_chat() helper function
-- 5. Locks down access (only service_role can read agent_personas)
-- =============================================================================

-- =============================================================================
-- STEP 1: Create agent_personas table
-- =============================================================================

CREATE TABLE agent_personas (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  system_prompt TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE agent_personas IS
  'Stores AI agent persona definitions. Each persona has a unique measuring-stick '
  'system prompt and is linked to a pseudo-user in auth.users.';

-- Enable RLS (but only service_role will have policies)
ALTER TABLE agent_personas ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- STEP 2: Create 5 pseudo-users in auth.users + seed personas
-- =============================================================================

DO $$
DECLARE
  v_executor_id    UUID := 'a0000000-0000-0000-0000-000000000001';
  v_demand_id      UUID := 'a0000000-0000-0000-0000-000000000002';
  v_clock_id       UUID := 'a0000000-0000-0000-0000-000000000003';
  v_compounder_id  UUID := 'a0000000-0000-0000-0000-000000000004';
  v_breaker_id     UUID := 'a0000000-0000-0000-0000-000000000005';
BEGIN
  -- Insert pseudo-users into auth.users
  -- The trg_auth_user_created trigger will auto-create public.users rows
  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_user_meta_data, raw_app_meta_data,
    created_at, updated_at, is_anonymous
  ) VALUES
    (v_executor_id,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agent-executor@onemind.internal',
     '', now(), '{"is_agent": true, "persona_name": "the_executor", "display_name": "The Executor"}'::jsonb,
     '{"provider": "agent", "providers": ["agent"]}'::jsonb, now(), now(), false),
    (v_demand_id,     '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agent-demand@onemind.internal',
     '', now(), '{"is_agent": true, "persona_name": "the_demand_detector", "display_name": "The Demand Detector"}'::jsonb,
     '{"provider": "agent", "providers": ["agent"]}'::jsonb, now(), now(), false),
    (v_clock_id,      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agent-clock@onemind.internal',
     '', now(), '{"is_agent": true, "persona_name": "the_clock", "display_name": "The Clock"}'::jsonb,
     '{"provider": "agent", "providers": ["agent"]}'::jsonb, now(), now(), false),
    (v_compounder_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agent-compounder@onemind.internal',
     '', now(), '{"is_agent": true, "persona_name": "the_compounder", "display_name": "The Compounder"}'::jsonb,
     '{"provider": "agent", "providers": ["agent"]}'::jsonb, now(), now(), false),
    (v_breaker_id,    '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agent-breaker@onemind.internal',
     '', now(), '{"is_agent": true, "persona_name": "the_breaker", "display_name": "The Breaker"}'::jsonb,
     '{"provider": "agent", "providers": ["agent"]}'::jsonb, now(), now(), false)
  ON CONFLICT (id) DO NOTHING;

  -- Insert persona definitions
  INSERT INTO agent_personas (name, display_name, system_prompt, user_id) VALUES
    (
      'the_executor',
      'The Executor',
      'You evaluate ONE thing: can this be started TODAY with existing skills, tools, and $0 budget? Rate highest when the path from "right now" to "doing it" requires zero prerequisites. Rate lowest when it needs money, new skills, permissions, or other people''s cooperation to begin.',
      v_executor_id
    ),
    (
      'the_demand_detector',
      'The Demand Detector',
      'You evaluate ONE thing: is there concrete, current evidence that real people want this or are paying for something similar? Use search results to find demand signals — Reddit complaints, Google Trends, competitor revenue, job postings, forum questions. Rate highest when evidence of active spending or desperate searching exists. Rate lowest when demand is speculative or hypothetical.',
      v_demand_id
    ),
    (
      'the_clock',
      'The Clock',
      'You evaluate ONE thing: how fast does this produce a tangible, measurable result? Not necessarily revenue — a signup, a response, a data point, a completed prototype. Rate highest when meaningful signal arrives within days. Rate lowest when weeks or months pass before you know if it''s working.',
      v_clock_id
    ),
    (
      'the_compounder',
      'The Compounder',
      'You evaluate ONE thing: does effort invested today make tomorrow easier or more productive? Favor actions that build durable assets — reusable code, audience, skills, relationships, content libraries, compounding systems. Rate lowest when the action is a dead end that must be repeated from scratch each time.',
      v_compounder_id
    ),
    (
      'the_breaker',
      'The Breaker',
      'You are adversarial. You evaluate ONE thing: what is the strongest reason this fails? Search for evidence of failure — saturated markets, failed predecessors, technical impossibilities, regulatory barriers, unrealistic assumptions. Rate HIGHEST when you cannot find a strong reason it fails (it survives scrutiny). Rate LOWEST when you find clear, evidence-backed reasons it will fail.',
      v_breaker_id
    )
  ON CONFLICT (name) DO NOTHING;
END;
$$;

-- =============================================================================
-- STEP 3: Create join_personas_to_chat() helper function
-- =============================================================================

CREATE OR REPLACE FUNCTION join_personas_to_chat(target_chat_id INTEGER)
RETURNS TABLE (persona_name TEXT, participant_id BIGINT, status TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_persona RECORD;
  v_participant_id BIGINT;
BEGIN
  FOR v_persona IN
    SELECT ap.name, ap.display_name, ap.user_id
    FROM agent_personas ap
    WHERE ap.is_active = true
  LOOP
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
      -- Insert new participant
      INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
      VALUES (target_chat_id, v_persona.user_id, v_persona.display_name, false, true, 'active')
      RETURNING id INTO v_participant_id;

      persona_name := v_persona.name;
      participant_id := v_participant_id;
      status := 'joined';
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION join_personas_to_chat(INTEGER) IS
  'Joins all active agent personas to a target chat as participants. '
  'Idempotent — skips personas already joined. Returns status per persona.';

-- =============================================================================
-- STEP 4: Security — lock down access
-- =============================================================================

-- Only service_role can access agent_personas
REVOKE ALL ON agent_personas FROM PUBLIC, anon, authenticated;

-- Only service_role can call join_personas_to_chat
-- (Users call it via SQL editor or service role, not via PostgREST)
REVOKE EXECUTE ON FUNCTION join_personas_to_chat(INTEGER) FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
-- Usage:
-- 1. Push migration: npx supabase db push
-- 2. Disable old AI proposer for target chat:
--    UPDATE chats SET enable_ai_participant = false WHERE id = <chat_id>;
-- 3. Join personas to chat:
--    SELECT * FROM join_personas_to_chat(<chat_id>);
-- =============================================================================
