-- =============================================================================
-- Personal Codes: Single-use invite codes for controlled chat access
-- =============================================================================
-- Adds a new access_method 'personal_code' where the host generates unique,
-- single-use 6-character codes and gives them to specific people. The code
-- itself is the authorization — no approval step needed. Once used, burned.

-- =============================================================================
-- A. Add 'personal_code' to access_method CHECK constraint
-- =============================================================================
ALTER TABLE public.chats DROP CONSTRAINT chats_access_method_check;
ALTER TABLE public.chats ADD CONSTRAINT chats_access_method_check
  CHECK (access_method = ANY (ARRAY['public'::text, 'code'::text, 'invite_only'::text, 'personal_code'::text]));

-- =============================================================================
-- B. Create personal_codes table
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.personal_codes (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    chat_id     BIGINT NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
    code        CHAR(6) NOT NULL,
    label       TEXT,                -- optional tag: "for Alice", "reddit-batch", etc.
    created_by  UUID NOT NULL,       -- host's auth.uid()
    used_by     UUID,                -- user who redeemed it (NULL = unused)
    used_at     TIMESTAMPTZ,         -- when redeemed (NULL = unused)
    revoked_at  TIMESTAMPTZ,         -- when revoked by host (NULL = not revoked)
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT personal_codes_code_unique UNIQUE (code),
    CONSTRAINT not_used_and_revoked CHECK (NOT (used_at IS NOT NULL AND revoked_at IS NOT NULL))
);

-- Fast lookup for code redemption (only active codes)
CREATE INDEX idx_personal_codes_active ON public.personal_codes(code) WHERE used_at IS NULL AND revoked_at IS NULL;

-- Host management: list codes for a chat
CREATE INDEX idx_personal_codes_chat ON public.personal_codes(chat_id);

-- =============================================================================
-- C. RLS on personal_codes
-- =============================================================================
ALTER TABLE public.personal_codes ENABLE ROW LEVEL SECURITY;

-- Host can view their chat's codes
CREATE POLICY "Host can view chat personal codes" ON public.personal_codes
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM public.participants p
        WHERE p.chat_id = personal_codes.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- Host can create codes (defense in depth; generation goes through RPC)
CREATE POLICY "Host can create personal codes" ON public.personal_codes
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.participants p
            WHERE p.chat_id = personal_codes.chat_id
            AND p.user_id = auth.uid()
            AND p.is_host = true
            AND p.status = 'active'
        )
    )
);

-- Host can update (revoke) codes
CREATE POLICY "Host can update personal codes" ON public.personal_codes
FOR UPDATE USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM public.participants p
        WHERE p.chat_id = personal_codes.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- =============================================================================
-- D. RPC: generate_personal_code(p_chat_id) — host generates a single-use code
-- =============================================================================
CREATE OR REPLACE FUNCTION public.generate_personal_code(p_chat_id BIGINT)
RETURNS TABLE (
    id BIGINT,
    code CHAR(6),
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    new_code CHAR(6);
    attempts INT := 0;
    v_user_id UUID;
    v_row RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Verify caller is host of a personal_code chat
    IF NOT EXISTS (
        SELECT 1 FROM chats c
        JOIN participants p ON p.chat_id = c.id
        WHERE c.id = p_chat_id
        AND c.access_method = 'personal_code'
        AND c.is_active = true
        AND p.user_id = v_user_id
        AND p.is_host = true
        AND p.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Only the host of a personal_code chat can generate codes';
    END IF;

    LOOP
        -- Generate random 6-char code
        new_code := '';
        FOR i IN 1..6 LOOP
            new_code := new_code || substr(chars, floor(random() * length(chars) + 1)::int, 1);
        END LOOP;

        -- Check uniqueness across both tables
        IF NOT EXISTS (SELECT 1 FROM chats WHERE invite_code = new_code)
           AND NOT EXISTS (SELECT 1 FROM personal_codes WHERE personal_codes.code = new_code)
        THEN
            INSERT INTO personal_codes (chat_id, code, created_by)
            VALUES (p_chat_id, new_code, v_user_id)
            RETURNING personal_codes.id, personal_codes.code, personal_codes.created_at
            INTO v_row;

            id := v_row.id;
            code := v_row.code;
            created_at := v_row.created_at;
            RETURN NEXT;
            RETURN;
        END IF;

        attempts := attempts + 1;
        IF attempts > 20 THEN
            RAISE EXCEPTION 'Could not generate unique personal code after 20 attempts';
        END IF;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_personal_code(BIGINT) TO authenticated;

-- =============================================================================
-- E. RPC: redeem_personal_code(p_code, p_display_name) — joiner uses a code
-- =============================================================================
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
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
    v_user_id UUID;
    v_code_record RECORD;
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
    FOR UPDATE OF pc;  -- lock to prevent race condition

    IF v_code_record IS NULL THEN
        RAISE EXCEPTION 'Invalid or already used code';
    END IF;

    -- Mark code as used
    UPDATE personal_codes
    SET used_by = v_user_id, used_at = now()
    WHERE personal_codes.id = v_code_record.id;

    -- Idempotent participant insert
    INSERT INTO participants (chat_id, user_id, display_name, is_host, is_authenticated, status)
    VALUES (v_code_record.chat_id, v_user_id, p_display_name, false, true, 'active')
    ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
    DO NOTHING;

    -- Return participant + chat info
    RETURN QUERY
    SELECT p.id, p.chat_id, p.display_name, p.status::TEXT, c.name, c.initial_message
    FROM participants p
    JOIN chats c ON c.id = p.chat_id
    WHERE p.chat_id = v_code_record.chat_id
      AND p.user_id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.redeem_personal_code(TEXT, TEXT) TO authenticated, anon;

-- =============================================================================
-- F. RPC: list_personal_codes(p_chat_id) — host sees all codes for a chat
-- =============================================================================
CREATE OR REPLACE FUNCTION public.list_personal_codes(p_chat_id BIGINT)
RETURNS TABLE (
    id BIGINT,
    code CHAR(6),
    label TEXT,
    used_by UUID,
    used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER STABLE
SET search_path = public
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
    SELECT pc.id, pc.code, pc.label, pc.used_by, pc.used_at, pc.revoked_at, pc.created_at
    FROM personal_codes pc
    WHERE pc.chat_id = p_chat_id
    ORDER BY pc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_personal_codes(BIGINT) TO authenticated;

-- =============================================================================
-- G. RPC: revoke_personal_code(p_code_id) — host revokes an unused code
-- =============================================================================
CREATE OR REPLACE FUNCTION public.revoke_personal_code(p_code_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Verify caller is host AND code is unused
    IF NOT EXISTS (
        SELECT 1 FROM personal_codes pc
        JOIN participants p ON p.chat_id = pc.chat_id
        WHERE pc.id = p_code_id
        AND pc.used_at IS NULL
        AND pc.revoked_at IS NULL
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Cannot revoke: code not found, already used, or not the host';
    END IF;

    UPDATE personal_codes SET revoked_at = now() WHERE personal_codes.id = p_code_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_personal_code(BIGINT) TO authenticated;

-- =============================================================================
-- H. Update get_chat_by_code() to check personal_codes first
-- =============================================================================
CREATE OR REPLACE FUNCTION get_chat_by_code(p_invite_code TEXT)
RETURNS SETOF chats
LANGUAGE plpgsql SECURITY DEFINER STABLE
AS $$
DECLARE
    v_chat_id BIGINT;
BEGIN
    -- Check personal codes first (unused, not revoked, active chat)
    SELECT pc.chat_id INTO v_chat_id
    FROM personal_codes pc
    JOIN chats c ON c.id = pc.chat_id
    WHERE pc.code = UPPER(p_invite_code)
      AND pc.used_at IS NULL
      AND pc.revoked_at IS NULL
      AND c.is_active = true
    LIMIT 1;

    IF v_chat_id IS NOT NULL THEN
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

-- =============================================================================
-- I. Update get_chat_by_code_translated() to check personal_codes first
-- =============================================================================
-- Must DROP first because we're changing from SQL to plpgsql (body change only,
-- but the original was already plpgsql so CREATE OR REPLACE works)
CREATE OR REPLACE FUNCTION public.get_chat_by_code_translated(
    p_invite_code TEXT,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    initial_message TEXT,
    description TEXT,
    invite_code TEXT,
    access_method TEXT,
    require_auth BOOLEAN,
    require_approval BOOLEAN,
    creator_id UUID,
    creator_session_token UUID,
    host_display_name TEXT,
    is_active BOOLEAN,
    is_official BOOLEAN,
    expires_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ,
    start_mode TEXT,
    rating_start_mode TEXT,
    auto_start_participant_count INTEGER,
    proposing_duration_seconds INTEGER,
    rating_duration_seconds INTEGER,
    proposing_minimum INTEGER,
    rating_minimum INTEGER,
    proposing_threshold_percent INTEGER,
    proposing_threshold_count INTEGER,
    rating_threshold_percent INTEGER,
    rating_threshold_count INTEGER,
    enable_ai_participant BOOLEAN,
    ai_propositions_count INTEGER,
    confirmation_rounds_required INTEGER,
    show_previous_results BOOLEAN,
    propositions_per_user INTEGER,
    created_at TIMESTAMPTZ,
    adaptive_duration_enabled BOOLEAN,
    adaptive_adjustment_percent INTEGER,
    min_phase_duration_seconds INTEGER,
    max_phase_duration_seconds INTEGER,
    schedule_type TEXT,
    schedule_timezone TEXT,
    scheduled_start_at TIMESTAMPTZ,
    schedule_windows JSONB,
    visible_outside_schedule BOOLEAN,
    schedule_paused BOOLEAN,
    host_paused BOOLEAN,
    name_translated TEXT,
    description_translated TEXT,
    initial_message_translated TEXT,
    translation_language TEXT,
    translations_enabled BOOLEAN,
    translation_languages TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_resolved_invite_code TEXT;
BEGIN
    -- Check personal codes first (unused, not revoked, active chat)
    SELECT ch.invite_code INTO v_resolved_invite_code
    FROM personal_codes pc
    JOIN chats ch ON ch.id = pc.chat_id
    WHERE pc.code = UPPER(p_invite_code)
      AND pc.used_at IS NULL
      AND pc.revoked_at IS NULL
      AND ch.is_active = true
    LIMIT 1;

    -- If no personal code match, use the code directly as a chat invite code
    IF v_resolved_invite_code IS NULL THEN
        v_resolved_invite_code := UPPER(p_invite_code);
    END IF;

    RETURN QUERY
    SELECT
        c.id,
        c.name,
        c.initial_message,
        c.description,
        c.invite_code::TEXT,
        c.access_method::TEXT,
        c.require_auth,
        c.require_approval,
        c.creator_id,
        c.creator_session_token,
        c.host_display_name,
        c.is_active,
        c.is_official,
        c.expires_at,
        c.last_activity_at,
        c.start_mode::TEXT,
        c.rating_start_mode::TEXT,
        c.auto_start_participant_count,
        c.proposing_duration_seconds,
        c.rating_duration_seconds,
        c.proposing_minimum,
        c.rating_minimum,
        c.proposing_threshold_percent,
        c.proposing_threshold_count,
        c.rating_threshold_percent,
        c.rating_threshold_count,
        c.enable_ai_participant,
        c.ai_propositions_count,
        c.confirmation_rounds_required,
        c.show_previous_results,
        c.propositions_per_user,
        c.created_at,
        c.adaptive_duration_enabled,
        c.adaptive_adjustment_percent,
        c.min_phase_duration_seconds,
        c.max_phase_duration_seconds,
        c.schedule_type::TEXT,
        c.schedule_timezone,
        c.scheduled_start_at,
        c.schedule_windows,
        c.visible_outside_schedule,
        c.schedule_paused,
        c.host_paused,
        COALESCE(
            t_name.translated_text,
            t_name_en.translated_text,
            c.name
        ) AS name_translated,
        COALESCE(
            t_desc.translated_text,
            t_desc_en.translated_text,
            c.description
        ) AS description_translated,
        COALESCE(
            t_msg.translated_text,
            t_msg_en.translated_text,
            c.initial_message
        ) AS initial_message_translated,
        CASE
            WHEN t_name.translated_text IS NOT NULL THEN p_language_code
            WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
            ELSE 'original'
        END AS translation_language,
        c.translations_enabled,
        c.translation_languages
    FROM chats c
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name'
        AND t_name.language_code = p_language_code
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name'
        AND t_name_en.language_code = 'en'
        AND p_language_code != 'en'
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND t_desc.language_code = p_language_code
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description'
        AND t_desc_en.language_code = 'en'
        AND p_language_code != 'en'
    LEFT JOIN translations t_msg ON t_msg.chat_id = c.id
        AND t_msg.field_name = 'initial_message'
        AND t_msg.language_code = p_language_code
    LEFT JOIN translations t_msg_en ON t_msg_en.chat_id = c.id
        AND t_msg_en.field_name = 'initial_message'
        AND t_msg_en.language_code = 'en'
        AND p_language_code != 'en'
    WHERE (c.invite_code = v_resolved_invite_code OR c.id = (
        -- For personal_code chats that don't have invite_code, match by chat_id
        SELECT pc2.chat_id FROM personal_codes pc2
        WHERE pc2.code = UPPER(p_invite_code)
          AND pc2.used_at IS NULL
          AND pc2.revoked_at IS NULL
        LIMIT 1
    ))
      AND c.is_active = true;
END;
$$;

-- =============================================================================
-- J. Update on_chat_insert_set_code() to check personal_codes for collisions
-- =============================================================================
CREATE OR REPLACE FUNCTION public.on_chat_insert_set_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    new_code CHAR(6);
    attempts INT := 0;
BEGIN
    -- Generate code for public and code-based chats (not invite_only or personal_code)
    IF NEW.access_method IN ('public', 'code') AND NEW.invite_code IS NULL THEN
        LOOP
            new_code := generate_invite_code();
            -- Also check personal_codes for collisions
            IF NOT EXISTS (SELECT 1 FROM personal_codes WHERE personal_codes.code = new_code) THEN
                BEGIN
                    NEW.invite_code := new_code;
                    EXIT;
                EXCEPTION WHEN unique_violation THEN
                    attempts := attempts + 1;
                    IF attempts > 10 THEN
                        RAISE EXCEPTION 'Could not generate unique invite code';
                    END IF;
                END;
            ELSE
                attempts := attempts + 1;
                IF attempts > 10 THEN
                    RAISE EXCEPTION 'Could not generate unique invite code';
                END IF;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

-- =============================================================================
-- K. Enable Realtime on personal_codes
-- =============================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE personal_codes;
