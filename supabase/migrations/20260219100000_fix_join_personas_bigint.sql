-- =============================================================================
-- Fix join_personas_to_chat: change target_chat_id from INTEGER to BIGINT
-- The chats.id column is bigint, so the trigger was failing with:
--   "function join_personas_to_chat(bigint, integer) does not exist"
-- =============================================================================

-- Drop both old signatures
DROP FUNCTION IF EXISTS join_personas_to_chat(INTEGER);
DROP FUNCTION IF EXISTS join_personas_to_chat(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION join_personas_to_chat(
  target_chat_id BIGINT,
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

COMMENT ON FUNCTION join_personas_to_chat(BIGINT, INTEGER) IS
  'Joins active agent personas to a target chat as participants. '
  'When max_count is provided, joins at most that many. '
  'Idempotent — skips personas already joined. Returns status per persona.';

REVOKE EXECUTE ON FUNCTION join_personas_to_chat(BIGINT, INTEGER) FROM PUBLIC, anon, authenticated;
