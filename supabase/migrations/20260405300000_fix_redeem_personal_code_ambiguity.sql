-- Fix: redeem_personal_code had ambiguous chat_id reference.
-- The RETURNS TABLE(chat_id bigint) creates an implicit PL/pgSQL variable
-- that conflicts with the chat_id column in INSERT/ON CONFLICT statements.
-- The original migration had #variable_conflict use_column but pg_dump strips it.
-- Fix: use EXECUTE for the INSERT to avoid PL/pgSQL variable resolution,
-- and use a v_ prefixed variable for the RETURN QUERY.

CREATE OR REPLACE FUNCTION public.redeem_personal_code(p_code TEXT, p_display_name TEXT)
RETURNS TABLE (
    participant_id BIGINT,
    chat_id BIGINT,
    display_name TEXT,
    status TEXT,
    chat_name TEXT,
    chat_initial_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user_id UUID;
    v_code_record RECORD;
    v_chat_id BIGINT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Look up the code (must be unused and not revoked, in an active chat)
    SELECT pc.id, pc.chat_id
    INTO v_code_record
    FROM personal_codes pc
    JOIN chats c ON c.id = pc.chat_id
    WHERE pc.code = UPPER(p_code)
      AND pc.used_at IS NULL
      AND pc.revoked_at IS NULL
      AND c.is_active = true
    FOR UPDATE OF pc;

    IF v_code_record IS NULL THEN
        RAISE EXCEPTION 'Invalid or already used code';
    END IF;

    v_chat_id := v_code_record.chat_id;

    -- Mark code as used
    UPDATE personal_codes
    SET used_by = v_user_id, used_at = now()
    WHERE personal_codes.id = v_code_record.id;

    -- Idempotent participant insert via EXECUTE to avoid PL/pgSQL variable ambiguity
    EXECUTE 'INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
             VALUES ($1, $2, $3, false, true, ''active'')
             ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
             DO NOTHING'
    USING v_chat_id, v_user_id, p_display_name;

    -- Return participant + chat info
    RETURN QUERY
    SELECT p.id, p.chat_id, p.display_name, p.status::TEXT, c.name, c.initial_message
    FROM participants p
    JOIN chats c ON c.id = p.chat_id
    WHERE p.chat_id = v_chat_id
      AND p.user_id = v_user_id;
END;
$$;
