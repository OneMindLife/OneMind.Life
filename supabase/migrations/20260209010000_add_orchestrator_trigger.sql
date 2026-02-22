-- =============================================================================
-- MIGRATION: Add orchestrator trigger for multi-persona consensus agents
-- =============================================================================
-- This migration creates a trigger that fires when rounds enter 'proposing'
-- or 'rating' phase. If any active agent personas are participants in the chat,
-- it calls the agent-orchestrator edge function via pg_net.
--
-- This trigger coexists with the existing ai-proposer trigger. The user should
-- disable the old AI proposer for chats that use personas:
--   UPDATE chats SET enable_ai_participant = false WHERE id = <chat_id>;
-- =============================================================================

-- =============================================================================
-- STEP 1: Create trigger function
-- =============================================================================

CREATE OR REPLACE FUNCTION trigger_agent_orchestrator()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_chat_id BIGINT;
  v_has_agents BOOLEAN;
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
BEGIN
  -- Only trigger on phase transitions to proposing or rating
  IF NEW.phase NOT IN ('proposing', 'rating') THEN
    RETURN NEW;
  END IF;

  -- Skip if phase didn't actually change
  IF TG_OP = 'UPDATE' AND OLD.phase = NEW.phase THEN
    RETURN NEW;
  END IF;

  -- Get the chat_id from the cycle
  SELECT c.chat_id INTO v_chat_id
  FROM cycles c
  WHERE c.id = NEW.cycle_id;

  -- Check if any active agent personas are participants in this chat
  SELECT EXISTS (
    SELECT 1
    FROM agent_personas ap
    JOIN participants p ON p.user_id = ap.user_id AND p.chat_id = v_chat_id
    WHERE ap.is_active = true
      AND p.status = 'active'
  ) INTO v_has_agents;

  IF NOT v_has_agents THEN
    RETURN NEW;
  END IF;

  -- Get service role key from vault
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'Agent orchestrator skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  -- Build Edge Function URL from vault
  v_url := get_edge_function_url('agent-orchestrator');

  -- Build request body
  v_body := jsonb_build_object(
    'round_id', NEW.id,
    'chat_id', v_chat_id,
    'cycle_id', NEW.cycle_id,
    'phase', NEW.phase
  );

  -- Call Edge Function via pg_net (async, non-blocking)
  -- 120s timeout: 5 agents × (Tavily ~2s + Kimi K2.5 ~10-15s) in parallel ≈ 15-20s typical
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body,
    timeout_milliseconds := 120000
  ) INTO v_request_id;

  RAISE LOG 'Agent orchestrator called for round % phase % in chat % (request_id: %)',
    NEW.id, NEW.phase, v_chat_id, v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Agent orchestrator trigger error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trigger_agent_orchestrator() IS
  'Trigger function that calls agent-orchestrator Edge Function when a round enters '
  'proposing or rating phase, but only if agent personas are participants in the chat. '
  'Uses pg_net for async HTTP and service role key from vault.';

-- =============================================================================
-- STEP 2: Create trigger on rounds table
-- =============================================================================

DROP TRIGGER IF EXISTS agent_orchestrator_on_phase_change ON rounds;

CREATE TRIGGER agent_orchestrator_on_phase_change
  AFTER INSERT OR UPDATE OF phase ON rounds
  FOR EACH ROW
  WHEN (NEW.phase IN ('proposing', 'rating'))
  EXECUTE FUNCTION trigger_agent_orchestrator();

COMMENT ON TRIGGER agent_orchestrator_on_phase_change ON rounds IS
  'Calls agent-orchestrator Edge Function when rounds enter proposing or rating phase, '
  'if any active agent personas are participants in the chat.';

-- =============================================================================
-- STEP 3: Security — restrict access to trigger function
-- =============================================================================

REVOKE EXECUTE ON FUNCTION trigger_agent_orchestrator() FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
