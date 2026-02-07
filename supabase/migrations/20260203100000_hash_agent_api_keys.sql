-- Migration: Hash agent API keys for security
--
-- This migration adds SHA-256 hashing to agent API keys.
-- Keys are no longer stored in plaintext - only the hash is stored.

-- ============================================================================
-- STEP 1: Add api_key_hash column
-- ============================================================================

ALTER TABLE "public"."agent_api_keys"
ADD COLUMN IF NOT EXISTS "api_key_hash" TEXT;

-- ============================================================================
-- STEP 2: Create function to hash API keys using SHA-256
-- ============================================================================

CREATE OR REPLACE FUNCTION hash_api_key(p_api_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- Use SHA-256 hash encoded as hex
    RETURN encode(digest(p_api_key, 'sha256'), 'hex');
END;
$$;

ALTER FUNCTION hash_api_key(TEXT) OWNER TO postgres;

COMMENT ON FUNCTION hash_api_key(TEXT) IS
'Hashes an API key using SHA-256 and returns the hex-encoded result';

-- ============================================================================
-- STEP 3: Migrate existing plaintext keys to hashed (one-time operation)
-- ============================================================================

-- Hash all existing keys and store in the new column
UPDATE agent_api_keys
SET api_key_hash = hash_api_key(api_key)
WHERE api_key_hash IS NULL AND api_key IS NOT NULL;

-- ============================================================================
-- STEP 4: Update validation function to use hash lookup
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
DECLARE
    v_api_key_hash TEXT;
BEGIN
    -- Hash the incoming key
    v_api_key_hash := hash_api_key(p_api_key);

    RETURN QUERY
    SELECT
        ak.id AS agent_id,
        ak.agent_name,
        ak.user_id,
        TRUE AS is_valid
    FROM agent_api_keys ak
    WHERE ak.api_key_hash = v_api_key_hash
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
'Validates an API key by hashing and looking up the hash. Returns agent info if valid.';

-- ============================================================================
-- STEP 5: Update touch function to use hash lookup
-- ============================================================================

CREATE OR REPLACE FUNCTION touch_agent_api_key(p_api_key TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_api_key_hash TEXT;
BEGIN
    v_api_key_hash := hash_api_key(p_api_key);

    UPDATE agent_api_keys
    SET last_used_at = now()
    WHERE api_key_hash = v_api_key_hash;
END;
$$;

ALTER FUNCTION touch_agent_api_key(TEXT) OWNER TO postgres;

COMMENT ON FUNCTION touch_agent_api_key(TEXT) IS
'Updates the last_used_at timestamp for an API key (looks up by hash)';

-- ============================================================================
-- STEP 6: Create index on hash column for fast lookups
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_agent_api_keys_hash ON agent_api_keys(api_key_hash);

-- ============================================================================
-- STEP 7: Make api_key_hash NOT NULL and remove plaintext key
-- ============================================================================

-- After migration, make hash required
ALTER TABLE "public"."agent_api_keys"
ALTER COLUMN "api_key_hash" SET NOT NULL;

-- Remove the plaintext key column (keys can no longer be recovered)
-- CAUTION: This is irreversible! Existing keys will need to be regenerated if lost.
ALTER TABLE "public"."agent_api_keys"
DROP COLUMN IF EXISTS "api_key";

-- Drop the old index that was on the plaintext key
DROP INDEX IF EXISTS idx_agent_api_keys_api_key;

-- ============================================================================
-- STEP 8: Update comments
-- ============================================================================

COMMENT ON COLUMN "public"."agent_api_keys"."api_key_hash" IS
'SHA-256 hash of the API key (hex encoded). The plaintext key is never stored.';
