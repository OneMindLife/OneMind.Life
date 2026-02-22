-- Migration: Register API keys for agent personas
--
-- Each of the 5 orchestrator personas gets its own API key so the orchestrator
-- can call agent-propose and agent-rate through the Agent API instead of
-- bypassing validation with direct DB writes.
--
-- Keys are hashed in agent_api_keys (standard auth flow) and plaintext
-- is stored in vault for the orchestrator to retrieve at runtime.

DO $$
DECLARE
  v_persona RECORD;
  v_api_key TEXT;
  v_api_key_hash TEXT;
  v_vault_name TEXT;
BEGIN
  -- Ensure pgcrypto's digest() is findable (needed by hash_api_key)
  PERFORM set_config('search_path', 'public, extensions', true);

  FOR v_persona IN
    SELECT name, user_id FROM agent_personas WHERE is_active = true
  LOOP
    -- Skip if key already exists for this persona
    IF EXISTS (
      SELECT 1 FROM agent_api_keys WHERE agent_name = v_persona.name
    ) THEN
      RAISE NOTICE 'API key already exists for persona %, skipping', v_persona.name;
      CONTINUE;
    END IF;

    -- Generate plaintext key
    v_api_key := generate_agent_api_key();
    v_api_key_hash := hash_api_key(v_api_key);

    -- Register hashed key in agent_api_keys
    INSERT INTO agent_api_keys (api_key_hash, agent_name, user_id, description)
    VALUES (
      v_api_key_hash,
      v_persona.name,
      v_persona.user_id,
      'Auto-generated key for orchestrator persona: ' || v_persona.name
    );

    -- Store plaintext in vault for orchestrator to read at runtime
    v_vault_name := 'persona_api_key_' || v_persona.name;

    -- Delete existing vault secret if any (idempotency)
    DELETE FROM vault.secrets WHERE name = v_vault_name;

    PERFORM vault.create_secret(
      v_api_key,
      v_vault_name,
      'API key for agent persona: ' || v_persona.name
    );

    RAISE NOTICE 'Registered API key for persona: %', v_persona.name;
  END LOOP;
END;
$$;

-- Helper function: bulk-fetch all persona API keys from vault in one call.
-- The orchestrator calls this once per invocation instead of 5 separate vault lookups.
CREATE OR REPLACE FUNCTION get_persona_api_keys()
RETURNS TABLE (persona_name TEXT, api_key TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ap.name AS persona_name,
    ds.decrypted_secret AS api_key
  FROM agent_personas ap
  JOIN vault.decrypted_secrets ds
    ON ds.name = 'persona_api_key_' || ap.name
  WHERE ap.is_active = true;
END;
$$;

-- Lock down: only service_role should access this (reads vault secrets)
REVOKE EXECUTE ON FUNCTION get_persona_api_keys() FROM PUBLIC, anon, authenticated;
