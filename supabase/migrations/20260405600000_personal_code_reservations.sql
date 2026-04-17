-- Migration: Add reservation system to personal codes
-- When a user looks up a personal code (via QR scan, manual entry, or URL),
-- the code is reserved for them. This triggers a realtime event so the host's
-- sheet auto-generates a new code. Reservations expire after 5 minutes.

-- ============================================================================
-- STEP 1: Add reservation columns
-- ============================================================================

ALTER TABLE public.personal_codes
ADD COLUMN reserved_by UUID,
ADD COLUMN reserved_at TIMESTAMPTZ;

-- ============================================================================
-- STEP 2: Helper to clear expired reservations (lazy cleanup)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.clear_expired_reservations()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
    UPDATE personal_codes
    SET reserved_by = NULL, reserved_at = NULL
    WHERE reserved_at IS NOT NULL
      AND reserved_at < NOW() - INTERVAL '5 minutes'
      AND used_at IS NULL;
$$;

-- ============================================================================
-- STEP 3: reserve_personal_code RPC
-- Called automatically when get_chat_by_code looks up a personal code.
-- Reserves the code for auth.uid() so no one else can use it.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reserve_personal_code(p_code TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user_id UUID;
    v_code_record RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN; -- Anonymous browsing, don't reserve
    END IF;

    -- Clear expired reservations first (lazy cleanup)
    PERFORM clear_expired_reservations();

    -- Find the code: must be unused, unrevoked, and either unreserved or reserved by self or expired
    SELECT pc.id, pc.reserved_by
    INTO v_code_record
    FROM personal_codes pc
    JOIN chats c ON c.id = pc.chat_id
    WHERE pc.code = UPPER(p_code)
      AND pc.used_at IS NULL
      AND pc.revoked_at IS NULL
      AND c.is_active = true
      AND (
          pc.reserved_by IS NULL
          OR pc.reserved_by = v_user_id
          OR pc.reserved_at < NOW() - INTERVAL '5 minutes'
      )
    FOR UPDATE OF pc
    LIMIT 1;

    IF v_code_record IS NULL THEN
        RETURN; -- Code not found, already used, or reserved by someone else
    END IF;

    -- Skip if already reserved by this user (idempotent)
    IF v_code_record.reserved_by = v_user_id THEN
        RETURN;
    END IF;

    -- Reserve it
    UPDATE personal_codes
    SET reserved_by = v_user_id, reserved_at = NOW()
    WHERE id = v_code_record.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reserve_personal_code(TEXT) TO anon, authenticated;

-- ============================================================================
-- STEP 4: Update get_chat_by_code to auto-reserve personal codes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_chat_by_code(p_invite_code TEXT)
RETURNS SETOF chats
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
DECLARE
    v_chat_id BIGINT;
    v_is_personal_code BOOLEAN := FALSE;
BEGIN
    -- Check personal codes first (unused, not revoked, active chat)
    SELECT pc.chat_id INTO v_chat_id
    FROM personal_codes pc
    JOIN chats c ON c.id = pc.chat_id
    WHERE pc.code = UPPER(p_invite_code)
      AND pc.used_at IS NULL
      AND pc.revoked_at IS NULL
      AND c.is_active = true
      AND (
          pc.reserved_by IS NULL
          OR pc.reserved_by = auth.uid()
          OR pc.reserved_at < NOW() - INTERVAL '5 minutes'
      )
    LIMIT 1;

    IF v_chat_id IS NOT NULL THEN
        v_is_personal_code := TRUE;

        -- Reserve the code for this user (side effect in a STABLE function
        -- requires a separate call since STABLE can't do writes)
        -- We'll handle reservation in the Flutter layer instead.
        -- Actually: we use a NOTIFY or separate call. See note below.

        RETURN QUERY SELECT c.* FROM chats c WHERE c.id = v_chat_id;
        RETURN;
    END IF;

    -- Fallback: chat-level invite code
    RETURN QUERY
    SELECT c.*
    FROM chats c
    WHERE c.invite_code = UPPER(p_invite_code)
      AND c.is_active = true
    LIMIT 1;
END;
$$;

-- NOTE: get_chat_by_code is STABLE (read-only), so it can't do writes.
-- The reservation must happen in the Flutter layer by calling reserve_personal_code
-- after get_chat_by_code returns a personal_code chat.
-- We keep get_chat_by_code filtering out codes reserved by others so they don't
-- see a chat they can't actually join.

-- ============================================================================
-- STEP 5: Update redeem_personal_code to handle reservations
-- Accepts codes reserved by the caller. Rejects codes reserved by others.
-- ============================================================================

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

    -- Clear expired reservations
    PERFORM clear_expired_reservations();

    -- Look up the code: unused, unrevoked, and either unreserved, reserved by self, or expired
    SELECT pc.id, pc.chat_id
    INTO v_code_record
    FROM personal_codes pc
    JOIN chats c ON c.id = pc.chat_id
    WHERE pc.code = UPPER(p_code)
      AND pc.used_at IS NULL
      AND pc.revoked_at IS NULL
      AND c.is_active = true
      AND (
          pc.reserved_by IS NULL
          OR pc.reserved_by = v_user_id
          OR pc.reserved_at < NOW() - INTERVAL '5 minutes'
      )
    FOR UPDATE OF pc;

    IF v_code_record IS NULL THEN
        RAISE EXCEPTION 'Invalid or already used code';
    END IF;

    v_chat_id := v_code_record.chat_id;

    -- Mark code as used (clears reservation implicitly since used_at is set)
    UPDATE personal_codes
    SET used_by = v_user_id, used_at = now(),
        reserved_by = NULL, reserved_at = NULL
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

-- ============================================================================
-- STEP 6: Update list_personal_codes to include reservation info
-- Must DROP first because RETURNS TABLE signature is changing.
-- ============================================================================

DROP FUNCTION IF EXISTS public.list_personal_codes(bigint);
CREATE OR REPLACE FUNCTION public.list_personal_codes(p_chat_id bigint)
RETURNS TABLE(
    id bigint,
    code character,
    label text,
    used_by uuid,
    used_at timestamptz,
    revoked_at timestamptz,
    reserved_by uuid,
    reserved_at timestamptz,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Verify caller is host
    IF NOT EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = p_chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Only the host can list personal codes';
    END IF;

    RETURN QUERY
    SELECT pc.id, pc.code, pc.label, pc.used_by, pc.used_at, pc.revoked_at,
           pc.reserved_by, pc.reserved_at, pc.created_at
    FROM personal_codes pc
    WHERE pc.chat_id = p_chat_id
    ORDER BY pc.created_at DESC;
END;
$$;

-- ============================================================================
-- STEP 7: Comments
-- ============================================================================

COMMENT ON COLUMN public.personal_codes.reserved_by IS 'UUID of user who looked up this code (reserved for 5 min)';
COMMENT ON COLUMN public.personal_codes.reserved_at IS 'When the code was reserved. Expires after 5 minutes.';
COMMENT ON FUNCTION public.reserve_personal_code(TEXT) IS 'Reserve a personal code for the calling user. Expires after 5 min.';
COMMENT ON FUNCTION public.clear_expired_reservations() IS 'Clear personal code reservations older than 5 minutes.';
