-- Migration: Expose translation_languages in all public-facing RPCs
-- Users need to see what language(s) a chat uses before joining.
--
-- We must DROP existing functions first because adding columns to
-- RETURNS TABLE changes the return type, which CREATE OR REPLACE
-- does not allow.

-- Drop all functions that need return-type changes
DROP FUNCTION IF EXISTS get_public_chats(INTEGER, INTEGER, UUID);
DROP FUNCTION IF EXISTS search_public_chats(TEXT, INTEGER, INTEGER, UUID);
DROP FUNCTION IF EXISTS public.get_public_chats_translated(INTEGER, INTEGER, UUID, TEXT);
DROP FUNCTION IF EXISTS public.search_public_chats_translated(TEXT, INTEGER, INTEGER, UUID, TEXT);
DROP FUNCTION IF EXISTS public.get_chat_translated(BIGINT, TEXT);
DROP FUNCTION IF EXISTS public.get_my_chats_translated(UUID, TEXT);
DROP FUNCTION IF EXISTS public.get_chat_by_code_translated(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.validate_invite_token(UUID);

-- ============================================================
-- 1. get_public_chats: add translation_languages
-- ============================================================
CREATE OR REPLACE FUNCTION get_public_chats(
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    description TEXT,
    initial_message TEXT,
    participant_count BIGINT,
    created_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ,
    translation_languages TEXT[]
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) AS participant_count,
        c.created_at,
        c.last_activity_at,
        c.translation_languages
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
    WHERE c.is_active = true
      AND c.access_method = 'public'
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id
    ORDER BY c.name ASC
    LIMIT p_limit
    OFFSET p_offset;
$$;

-- ============================================================
-- 2. search_public_chats: add translation_languages
-- ============================================================
CREATE OR REPLACE FUNCTION search_public_chats(
    p_query TEXT,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    description TEXT,
    initial_message TEXT,
    participant_count BIGINT,
    created_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ,
    translation_languages TEXT[]
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) AS participant_count,
        c.created_at,
        c.last_activity_at,
        c.translation_languages
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
    WHERE c.is_active = true
      AND c.access_method = 'public'
      AND (
          c.name ILIKE '%' || p_query || '%'
          OR c.description ILIKE '%' || p_query || '%'
          OR c.initial_message ILIKE '%' || p_query || '%'
      )
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id
    ORDER BY c.name ASC
    LIMIT p_limit
    OFFSET p_offset;
$$;

-- ============================================================
-- 3. get_public_chats_translated: add translation_languages
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_public_chats_translated(
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_user_id UUID DEFAULT NULL,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    description TEXT,
    initial_message TEXT,
    participant_count BIGINT,
    created_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ,
    name_translated TEXT,
    description_translated TEXT,
    initial_message_translated TEXT,
    translation_language TEXT,
    translation_languages TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) AS participant_count,
        c.created_at,
        c.last_activity_at,
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
        c.translation_languages
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
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
    WHERE c.is_active = true
      AND c.access_method = 'public'
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id, t_name.translated_text, t_name_en.translated_text,
             t_desc.translated_text, t_desc_en.translated_text,
             t_msg.translated_text, t_msg_en.translated_text
    ORDER BY COALESCE(t_name.translated_text, t_name_en.translated_text, c.name) ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- ============================================================
-- 4. search_public_chats_translated: add translation_languages
-- ============================================================
CREATE OR REPLACE FUNCTION public.search_public_chats_translated(
    p_query TEXT,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_user_id UUID DEFAULT NULL,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE (
    id BIGINT,
    name TEXT,
    description TEXT,
    initial_message TEXT,
    participant_count BIGINT,
    created_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ,
    name_translated TEXT,
    description_translated TEXT,
    initial_message_translated TEXT,
    translation_language TEXT,
    translation_languages TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        COUNT(p.id) AS participant_count,
        c.created_at,
        c.last_activity_at,
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
        c.translation_languages
    FROM chats c
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
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
    WHERE c.is_active = true
      AND c.access_method = 'public'
      AND (
          c.name ILIKE '%' || p_query || '%'
          OR c.description ILIKE '%' || p_query || '%'
          OR c.initial_message ILIKE '%' || p_query || '%'
          OR t_name.translated_text ILIKE '%' || p_query || '%'
          OR t_desc.translated_text ILIKE '%' || p_query || '%'
          OR t_msg.translated_text ILIKE '%' || p_query || '%'
      )
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id, t_name.translated_text, t_name_en.translated_text,
             t_desc.translated_text, t_desc_en.translated_text,
             t_msg.translated_text, t_msg_en.translated_text
    ORDER BY COALESCE(t_name.translated_text, t_name_en.translated_text, c.name) ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- ============================================================
-- 5. get_chat_translated: add translations_enabled + translation_languages
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_chat_translated(
    p_chat_id BIGINT,
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
BEGIN
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
    WHERE c.id = p_chat_id;
END;
$$;

-- ============================================================
-- 6. get_my_chats_translated: add translations_enabled + translation_languages
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_chats_translated(
    p_user_id UUID,
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
BEGIN
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
    INNER JOIN participants p ON p.chat_id = c.id
        AND p.user_id = p_user_id
        AND p.status = 'active'
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
    WHERE c.is_active = true
    ORDER BY c.last_activity_at DESC NULLS LAST;
END;
$$;

-- ============================================================
-- 7. get_chat_by_code_translated: add translations_enabled + translation_languages
-- ============================================================
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
BEGIN
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
    WHERE c.invite_code = p_invite_code
      AND c.is_active = true;
END;
$$;

-- ============================================================
-- 8. validate_invite_token: add translation_languages
-- ============================================================
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
    email TEXT,
    translation_languages TEXT[]
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
        i.email,
        c.translation_languages
    FROM invites i
    JOIN chats c ON c.id = i.chat_id
    WHERE i.invite_token = p_invite_token
    AND i.status = 'pending'
    AND (i.expires_at IS NULL OR i.expires_at > now())
    LIMIT 1;
END;
$$;

-- Re-grant execute for validate_invite_token (signature changed)
GRANT EXECUTE ON FUNCTION public.validate_invite_token(UUID) TO authenticated, anon;
