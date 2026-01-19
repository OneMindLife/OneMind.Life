-- =============================================================================
-- MIGRATION: Add validate_invite_token function for direct token validation
-- =============================================================================
-- This function allows validating an invite token directly (from URL links)
-- without requiring the user to know the chat code first.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Create function to validate invite by token
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_invite_token(
    p_invite_token UUID
)
RETURNS TABLE (
    is_valid BOOLEAN,
    chat_id BIGINT,
    chat_name TEXT,
    chat_initial_message TEXT,
    access_method TEXT,
    require_approval BOOLEAN,
    email TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        TRUE as is_valid,
        c.id as chat_id,
        c.name as chat_name,
        c.initial_message as chat_initial_message,
        c.access_method,
        c.require_approval,
        i.email
    FROM invites i
    JOIN chats c ON c.id = i.chat_id
    WHERE i.invite_token = p_invite_token
    AND i.status = 'pending'
    AND (i.expires_at IS NULL OR i.expires_at > now())
    LIMIT 1;
END;
$$;

-- Grant execute to authenticated and anon roles
GRANT EXECUTE ON FUNCTION public.validate_invite_token(UUID) TO authenticated, anon;

-- -----------------------------------------------------------------------------
-- STEP 2: Add comment for documentation
-- -----------------------------------------------------------------------------

COMMENT ON FUNCTION public.validate_invite_token(UUID) IS
'Validates an invite token and returns chat information. Used for direct invite links (/join/invite?token=xxx).';
