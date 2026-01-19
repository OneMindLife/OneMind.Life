-- =============================================================================
-- MIGRATION: Add public access method for discoverable chats
-- =============================================================================
-- This migration adds 'public' as a new access_method option, making chats
-- discoverable and joinable without an invite code.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 1: Update the access_method check constraint
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."chats"
DROP CONSTRAINT IF EXISTS "chats_access_method_check";

ALTER TABLE "public"."chats"
ADD CONSTRAINT "chats_access_method_check"
CHECK (access_method = ANY (ARRAY['public'::text, 'code'::text, 'invite_only'::text]));

-- -----------------------------------------------------------------------------
-- STEP 2: Change default access_method to 'public'
-- -----------------------------------------------------------------------------

ALTER TABLE "public"."chats"
ALTER COLUMN "access_method" SET DEFAULT 'public'::text;

-- -----------------------------------------------------------------------------
-- STEP 3: Add index for efficient public chat queries
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_chats_public_active
ON "public"."chats" (access_method, is_active, created_at DESC)
WHERE access_method = 'public' AND is_active = true;

-- -----------------------------------------------------------------------------
-- STEP 4: Update RLS policy to allow reading public chats
-- -----------------------------------------------------------------------------

-- Drop existing select policy if it exists
DROP POLICY IF EXISTS "Anyone can view public chats" ON "public"."chats";

-- Create policy allowing anyone to view public active chats
CREATE POLICY "Anyone can view public chats" ON "public"."chats"
FOR SELECT
USING (
    access_method = 'public'
    AND is_active = true
);

-- -----------------------------------------------------------------------------
-- STEP 5: Update participants INSERT policy for public chats
-- -----------------------------------------------------------------------------

-- Drop existing policy
DROP POLICY IF EXISTS "Users can join with valid access" ON "public"."participants";

-- Create updated policy that includes public access
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
            -- For 'public' access: anyone can join
            EXISTS (
                SELECT 1 FROM chats c
                WHERE c.id = chat_id
                AND c.access_method = 'public'
                AND c.is_active = true
            )
            OR
            -- For 'code' access: anyone with the code can join
            EXISTS (
                SELECT 1 FROM chats c
                WHERE c.id = chat_id
                AND c.access_method = 'code'
            )
            OR
            -- For 'invite_only': must have a valid pending invite
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
-- STEP 6: Create function to list public chats
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_public_chats(
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    description TEXT,
    initial_message TEXT,
    participant_count BIGINT,
    created_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) as participant_count,
        c.created_at,
        c.last_activity_at
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
    WHERE c.access_method = 'public'
    AND c.is_active = true
    GROUP BY c.id
    ORDER BY c.last_activity_at DESC NULLS LAST, c.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- Grant execute to authenticated and anon roles
GRANT EXECUTE ON FUNCTION public.get_public_chats(INT, INT) TO authenticated, anon;

-- -----------------------------------------------------------------------------
-- STEP 7: Create function to search public chats
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.search_public_chats(
    p_query TEXT,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    description TEXT,
    initial_message TEXT,
    participant_count BIGINT,
    created_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) as participant_count,
        c.created_at,
        c.last_activity_at
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
    WHERE c.access_method = 'public'
    AND c.is_active = true
    AND (
        c.name ILIKE '%' || p_query || '%'
        OR c.description ILIKE '%' || p_query || '%'
        OR c.initial_message ILIKE '%' || p_query || '%'
    )
    GROUP BY c.id
    ORDER BY
        CASE WHEN c.name ILIKE '%' || p_query || '%' THEN 0 ELSE 1 END,
        c.last_activity_at DESC NULLS LAST
    LIMIT p_limit;
END;
$$;

-- Grant execute to authenticated and anon roles
GRANT EXECUTE ON FUNCTION public.search_public_chats(TEXT, INT) TO authenticated, anon;
