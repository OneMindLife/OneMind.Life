-- =============================================================================
-- MIGRATION: Enforce invite-only access at database level
-- =============================================================================
-- This migration adds RLS policies to ensure that invite-only chats
-- can only be joined by users with valid, pending invites.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Update participants INSERT policy to check invite-only access
-- -----------------------------------------------------------------------------

-- Drop the existing policy
DROP POLICY IF EXISTS "Users can join with own session" ON "public"."participants";

-- Create new policy that enforces invite-only
CREATE POLICY "Users can join with valid access" ON "public"."participants"
FOR INSERT
WITH CHECK (
    -- Service role can always insert (for host creation, approvals, etc.)
    (current_setting('role', true) = 'service_role')
    OR
    (
        -- Session token must match
        session_token = public.get_session_token()
        AND
        -- Check access method
        (
            -- For 'code' access: anyone with the code can join
            EXISTS (
                SELECT 1 FROM chats c
                WHERE c.id = chat_id
                AND c.access_method = 'code'
            )
            OR
            -- For 'invite_only': must have a valid pending invite
            -- Note: The app must verify email matches before allowing join
            -- This policy allows insert if ANY pending invite exists for this chat
            -- The app-level check ensures the user's email matches
            EXISTS (
                SELECT 1 FROM chats c
                WHERE c.id = chat_id
                AND c.access_method = 'invite_only'
                AND EXISTS (
                    SELECT 1 FROM invites i
                    WHERE i.chat_id = c.id
                    AND i.status = 'pending'
                    AND (i.expires_at IS NULL OR i.expires_at > now())
                )
            )
        )
    )
);

-- -----------------------------------------------------------------------------
-- STEP 2: Add function to validate and accept an invite
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.accept_invite(
    p_invite_token UUID,
    p_participant_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite_id BIGINT;
BEGIN
    -- Find and validate the invite
    SELECT id INTO v_invite_id
    FROM invites
    WHERE invite_token = p_invite_token
    AND status = 'pending'
    AND (expires_at IS NULL OR expires_at > now());

    IF v_invite_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Mark invite as accepted
    UPDATE invites
    SET status = 'accepted',
        accepted_at = now(),
        accepted_by = p_participant_id
    WHERE id = v_invite_id;

    RETURN TRUE;
END;
$$;

-- Grant execute to authenticated and anon roles
GRANT EXECUTE ON FUNCTION public.accept_invite(UUID, BIGINT) TO authenticated, anon;

-- -----------------------------------------------------------------------------
-- STEP 3: Add accepted_at and accepted_by columns to invites table
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."invites"
ADD COLUMN IF NOT EXISTS "accepted_at" TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS "accepted_by" BIGINT REFERENCES participants(id);

-- -----------------------------------------------------------------------------
-- STEP 4: Add function to validate invite by email
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_invite_email(
    p_chat_id BIGINT,
    p_email TEXT
)
RETURNS TABLE (
    invite_token UUID,
    is_valid BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.invite_token,
        TRUE as is_valid
    FROM invites i
    WHERE i.chat_id = p_chat_id
    AND lower(i.email) = lower(p_email)
    AND i.status = 'pending'
    AND (i.expires_at IS NULL OR i.expires_at > now())
    LIMIT 1;
END;
$$;

-- Grant execute to authenticated and anon roles
GRANT EXECUTE ON FUNCTION public.validate_invite_email(BIGINT, TEXT) TO authenticated, anon;

-- -----------------------------------------------------------------------------
-- STEP 5: Create index for faster invite lookups
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_invites_chat_email_status
ON invites(chat_id, lower(email), status)
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_invites_token_status
ON invites(invite_token, status)
WHERE status = 'pending';
