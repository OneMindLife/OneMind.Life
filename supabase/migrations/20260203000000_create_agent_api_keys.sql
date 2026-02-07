-- Migration: Create agent_api_keys table for AI Agent API authentication
--
-- This table stores API keys for AI agents to participate in OneMind programmatically.
-- Each agent gets a pseudo-user in auth.users so existing RLS policies work unchanged.

-- ============================================================================
-- STEP 1: Create agent_api_keys table
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."agent_api_keys" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "api_key" TEXT UNIQUE NOT NULL,              -- Format: onemind_sk_<random>
    "agent_name" TEXT NOT NULL,                  -- Unique name for the agent
    "description" TEXT,                          -- Optional description
    "user_id" UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,  -- Pseudo-user for RLS
    "created_at" TIMESTAMPTZ DEFAULT now() NOT NULL,
    "last_used_at" TIMESTAMPTZ,
    "is_active" BOOLEAN DEFAULT true NOT NULL,

    -- Agent name must be unique and follow naming conventions
    CONSTRAINT "agent_api_keys_agent_name_unique" UNIQUE ("agent_name"),
    CONSTRAINT "agent_api_keys_agent_name_format" CHECK (
        "agent_name" ~ '^[a-zA-Z][a-zA-Z0-9_-]{2,49}$'
    )
);

ALTER TABLE "public"."agent_api_keys" OWNER TO "postgres";

-- ============================================================================
-- STEP 2: Create indexes for fast lookups
-- ============================================================================

-- Primary lookup by API key (used on every authenticated request)
CREATE INDEX IF NOT EXISTS idx_agent_api_keys_api_key ON agent_api_keys(api_key);

-- Lookup by user_id (for finding agent by pseudo-user)
CREATE INDEX IF NOT EXISTS idx_agent_api_keys_user_id ON agent_api_keys(user_id);

-- Lookup by agent_name (for registration uniqueness check)
CREATE INDEX IF NOT EXISTS idx_agent_api_keys_agent_name ON agent_api_keys(agent_name);

-- ============================================================================
-- STEP 3: RLS Policies (minimal - agents use service role key internally)
-- ============================================================================

ALTER TABLE "public"."agent_api_keys" ENABLE ROW LEVEL SECURITY;

-- Only service role can access this table (Edge Functions use service role)
-- No user-facing policies needed since agents don't query this table directly

COMMENT ON TABLE "public"."agent_api_keys" IS
'API keys for AI agents to participate in OneMind. Each agent has a pseudo-user for RLS compatibility.';

COMMENT ON COLUMN "public"."agent_api_keys"."api_key" IS
'Secret API key in format onemind_sk_<random>. Hashed before storage would be ideal for production.';

COMMENT ON COLUMN "public"."agent_api_keys"."user_id" IS
'References a pseudo-user created in auth.users. All RLS policies use auth.uid() so this gives agents access.';

-- ============================================================================
-- STEP 4: Function to generate secure API keys
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_agent_api_key()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    -- Characters for URL-safe base64-like encoding
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    result TEXT := 'onemind_sk_';
    i INT;
BEGIN
    -- Generate 32 random characters (192 bits of entropy)
    FOR i IN 1..32 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    RETURN result;
END;
$$;

ALTER FUNCTION generate_agent_api_key() OWNER TO postgres;

COMMENT ON FUNCTION generate_agent_api_key() IS
'Generates a secure API key with format onemind_sk_<32 random chars>';

-- ============================================================================
-- STEP 5: Function to validate API key and get agent info
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_agent_api_key(p_api_key TEXT)
RETURNS TABLE (
    agent_id UUID,
    agent_name TEXT,
    user_id UUID,
    is_valid BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ak.id AS agent_id,
        ak.agent_name,
        ak.user_id,
        TRUE AS is_valid
    FROM agent_api_keys ak
    WHERE ak.api_key = p_api_key
      AND ak.is_active = TRUE;

    -- If no rows returned, the key is invalid
    IF NOT FOUND THEN
        RETURN QUERY SELECT
            NULL::UUID AS agent_id,
            NULL::TEXT AS agent_name,
            NULL::UUID AS user_id,
            FALSE AS is_valid;
    END IF;
END;
$$;

ALTER FUNCTION validate_agent_api_key(TEXT) OWNER TO postgres;

COMMENT ON FUNCTION validate_agent_api_key(TEXT) IS
'Validates an API key and returns agent info if valid';

-- ============================================================================
-- STEP 6: Function to update last_used_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION touch_agent_api_key(p_api_key TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE agent_api_keys
    SET last_used_at = now()
    WHERE api_key = p_api_key;
END;
$$;

ALTER FUNCTION touch_agent_api_key(TEXT) OWNER TO postgres;

COMMENT ON FUNCTION touch_agent_api_key(TEXT) IS
'Updates the last_used_at timestamp for an API key';
