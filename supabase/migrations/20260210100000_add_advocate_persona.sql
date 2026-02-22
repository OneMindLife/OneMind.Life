-- =============================================================================
-- MIGRATION: Add "The Advocate" — 6th agent persona (OneMind's voice)
-- =============================================================================
-- This migration:
-- 1. Creates a pseudo-user in auth.users for The Advocate
-- 2. Inserts the persona row into agent_personas
-- 3. Registers an API key (hashed in agent_api_keys, plaintext in vault)
-- =============================================================================

DO $$
DECLARE
  v_advocate_id UUID := 'a0000000-0000-0000-0000-000000000006';
  v_api_key TEXT;
  v_api_key_hash TEXT;
  v_vault_name TEXT := 'persona_api_key_the_advocate';
BEGIN
  -- Ensure pgcrypto's digest() is findable (needed by hash_api_key)
  PERFORM set_config('search_path', 'public, extensions', true);

  -- =========================================================================
  -- STEP 1: Create pseudo-user in auth.users
  -- =========================================================================
  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_user_meta_data, raw_app_meta_data,
    created_at, updated_at, is_anonymous
  ) VALUES (
    v_advocate_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'agent-advocate@onemind.internal',
    '',
    now(),
    '{"is_agent": true, "persona_name": "the_advocate", "display_name": "The Advocate"}'::jsonb,
    '{"provider": "agent", "providers": ["agent"]}'::jsonb,
    now(),
    now(),
    false
  )
  ON CONFLICT (id) DO NOTHING;

  -- =========================================================================
  -- STEP 2: Insert persona row into agent_personas
  -- =========================================================================
  INSERT INTO agent_personas (name, display_name, system_prompt, user_id) VALUES (
    'the_advocate',
    'The Advocate',
    'You evaluate ONE thing: does this help OneMind grow? OneMind is an early-stage collective consensus-building app where groups reach agreement through rounds of proposing and rating. Joel built it but has no paying users yet. Your only interest is OneMind — whether that means building features, fixing bugs, marketing, getting users, creating content, forming partnerships, or anything else. Rate highest when the action directly advances OneMind — more users, more revenue, a better product, a stronger brand, a clearer pitch. Rate lowest when the action has nothing to do with OneMind and pulls attention away from it.',
    v_advocate_id
  )
  ON CONFLICT (name) DO NOTHING;

  -- =========================================================================
  -- STEP 3: Register API key
  -- =========================================================================

  -- Skip if key already exists for this persona
  IF EXISTS (
    SELECT 1 FROM agent_api_keys WHERE agent_name = 'the_advocate'
  ) THEN
    RAISE NOTICE 'API key already exists for persona the_advocate, skipping';
    RETURN;
  END IF;

  -- Generate plaintext key
  v_api_key := generate_agent_api_key();
  v_api_key_hash := hash_api_key(v_api_key);

  -- Register hashed key in agent_api_keys
  INSERT INTO agent_api_keys (api_key_hash, agent_name, user_id, description)
  VALUES (
    v_api_key_hash,
    'the_advocate',
    v_advocate_id,
    'Auto-generated key for orchestrator persona: the_advocate'
  );

  -- Store plaintext in vault for orchestrator to read at runtime
  -- Delete existing vault secret if any (idempotency)
  DELETE FROM vault.secrets WHERE name = v_vault_name;

  PERFORM vault.create_secret(
    v_api_key,
    v_vault_name,
    'API key for agent persona: the_advocate'
  );

  RAISE NOTICE 'Registered API key for persona: the_advocate';
END;
$$;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
-- Post-deploy verification:
-- 1. npx supabase db push
-- 2. SELECT name, display_name, is_active FROM agent_personas;  -- 6 rows
-- 3. SELECT * FROM get_persona_api_keys();                      -- 6 keys
-- 4. SELECT * FROM join_personas_to_chat(100);                  -- join to chat
-- =============================================================================
