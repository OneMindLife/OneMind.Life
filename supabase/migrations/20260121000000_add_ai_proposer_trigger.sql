-- =============================================================================
-- MIGRATION: Add AI proposer trigger for automatic proposition generation
-- =============================================================================
-- This migration:
-- 1. Changes default for enable_ai_participant to TRUE (always on)
-- 2. Changes default for ai_propositions_count to 1 (one thoughtful AI proposition)
-- 3. Creates a trigger that calls ai-proposer Edge Function when a round enters
--    the proposing phase
--
-- The AI proposer receives:
-- - Chat context (name, initial message, description)
-- - Consensus history (all completed cycles' winning propositions)
-- - Carried forward propositions (the competition to beat)
--
-- Architecture:
-- 1. Trigger fires on INSERT/UPDATE to rounds when phase = 'proposing'
-- 2. Trigger function calls ai-proposer Edge Function via pg_net (async HTTP)
-- 3. Edge Function fetches context and calls Claude API
-- 4. Edge Function inserts AI propositions with participant_id = NULL
-- =============================================================================

-- =============================================================================
-- STEP 1: Update default values for AI participant settings
-- =============================================================================

-- Change enable_ai_participant default from FALSE to TRUE
ALTER TABLE chats ALTER COLUMN enable_ai_participant SET DEFAULT TRUE;

-- Change ai_propositions_count default from 3 to 1
ALTER TABLE chats ALTER COLUMN ai_propositions_count SET DEFAULT 1;

-- Add comment explaining the change
COMMENT ON COLUMN chats.enable_ai_participant IS
  'Whether AI automatically generates propositions each round. Default TRUE (always on).';

COMMENT ON COLUMN chats.ai_propositions_count IS
  'Number of AI propositions to generate per round. Default 1 for focused competition.';

-- =============================================================================
-- STEP 2: Create trigger function to call AI proposer Edge Function
-- =============================================================================

CREATE OR REPLACE FUNCTION trigger_ai_proposer_on_proposing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_chat RECORD;
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
  v_cycle_id BIGINT;
  v_chat_id BIGINT;
BEGIN
  -- Only trigger when phase becomes 'proposing'
  -- For INSERT: NEW.phase = 'proposing'
  -- For UPDATE: NEW.phase = 'proposing' AND (OLD.phase IS NULL OR OLD.phase != 'proposing')
  IF NEW.phase != 'proposing' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.phase = 'proposing' THEN
    -- Already in proposing phase, don't trigger again
    RETURN NEW;
  END IF;

  -- Get the chat_id from the cycle
  SELECT c.chat_id INTO v_chat_id
  FROM cycles c
  WHERE c.id = NEW.cycle_id;

  -- Get chat settings to check if AI is enabled
  SELECT
    ch.id,
    ch.name,
    ch.initial_message,
    ch.description,
    ch.enable_ai_participant,
    ch.ai_propositions_count
  INTO v_chat
  FROM chats ch
  WHERE ch.id = v_chat_id;

  -- Skip if AI participant is disabled for this chat
  IF NOT v_chat.enable_ai_participant THEN
    RAISE LOG 'AI proposer skipped for round %: AI participant disabled for chat %',
      NEW.id, v_chat_id;
    RETURN NEW;
  END IF;

  -- Skip if ai_propositions_count is 0 or NULL
  IF v_chat.ai_propositions_count IS NULL OR v_chat.ai_propositions_count = 0 THEN
    RAISE LOG 'AI proposer skipped for round %: ai_propositions_count is %',
      NEW.id, COALESCE(v_chat.ai_propositions_count::TEXT, 'NULL');
    RETURN NEW;
  END IF;

  -- Get service role key from vault
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  -- If no key found, log warning and skip (don't fail the operation)
  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'AI proposer skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  -- Build Edge Function URL (hardcoded for production, use get_edge_function_url for flexibility)
  v_url := 'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/ai-proposer';

  -- Build request body
  v_body := jsonb_build_object(
    'round_id', NEW.id,
    'chat_id', v_chat_id,
    'cycle_id', NEW.cycle_id,
    'custom_id', NEW.custom_id
  );

  -- Call Edge Function via pg_net (async, non-blocking)
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body
  ) INTO v_request_id;

  -- Log the request for debugging
  RAISE LOG 'AI proposer called for round % in chat % (request_id: %)',
    NEW.id, v_chat_id, v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't fail the operation
  RAISE WARNING 'AI proposer trigger error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trigger_ai_proposer_on_proposing() IS
  'Trigger function that calls ai-proposer Edge Function when a round enters the proposing phase. '
  'Uses pg_net for async HTTP calls and service role key from vault for auth. '
  'Skips if enable_ai_participant is FALSE or ai_propositions_count is 0/NULL.';

-- =============================================================================
-- STEP 3: Create trigger on rounds table
-- =============================================================================

-- Drop existing trigger if it exists (idempotent)
DROP TRIGGER IF EXISTS ai_proposer_on_proposing_phase ON rounds;

-- Create trigger for rounds entering proposing phase
-- AFTER trigger to ensure the round is committed before calling the edge function
CREATE TRIGGER ai_proposer_on_proposing_phase
  AFTER INSERT OR UPDATE OF phase ON rounds
  FOR EACH ROW
  WHEN (NEW.phase = 'proposing')
  EXECUTE FUNCTION trigger_ai_proposer_on_proposing();

COMMENT ON TRIGGER ai_proposer_on_proposing_phase ON rounds IS
  'Automatically calls AI proposer Edge Function when a round enters the proposing phase. '
  'Catches all scenarios: manual start, auto-start, new round after rating, new cycle after consensus.';

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
-- Next steps:
-- 1. Deploy the ai-proposer Edge Function with --no-verify-jwt flag
-- 2. Set ANTHROPIC_API_KEY in Edge Function secrets (already set for translate function)
-- 3. Ensure edge_function_service_key is in Supabase Vault (already set for translate)
-- =============================================================================
