-- Migration: Add RPC functions for Chat model translations
-- Adds functions to fetch individual chats and user's chats with translations

-- ==============================================================================
-- 1. GET SINGLE CHAT WITH TRANSLATIONS
-- ==============================================================================

-- Get a single chat with translations by ID
-- Fallback chain: requested language -> English -> original content
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
    translation_language TEXT
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
        -- Name translation with fallback chain
        COALESCE(
            t_name.translated_text,
            t_name_en.translated_text,
            c.name
        ) AS name_translated,
        -- Description translation with fallback chain
        COALESCE(
            t_desc.translated_text,
            t_desc_en.translated_text,
            c.description
        ) AS description_translated,
        -- Initial message translation with fallback chain
        COALESCE(
            t_msg.translated_text,
            t_msg_en.translated_text,
            c.initial_message
        ) AS initial_message_translated,
        -- Which language was actually used
        CASE
            WHEN t_name.translated_text IS NOT NULL THEN p_language_code
            WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
            ELSE 'original'
        END AS translation_language
    FROM chats c
    -- Name translations
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name'
        AND t_name.language_code = p_language_code
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name'
        AND t_name_en.language_code = 'en'
        AND p_language_code != 'en'
    -- Description translations
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND t_desc.language_code = p_language_code
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description'
        AND t_desc_en.language_code = 'en'
        AND p_language_code != 'en'
    -- Initial message translations
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

COMMENT ON FUNCTION public.get_chat_translated(BIGINT, TEXT)
IS 'Returns a single chat with translated name, description, and initial_message. Fallback: requested language -> English -> original';

-- ==============================================================================
-- 2. GET USER'S CHATS WITH TRANSLATIONS
-- ==============================================================================

-- Get all chats the user is participating in with translations
-- Fallback chain: requested language -> English -> original content
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
    translation_language TEXT
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
        -- Name translation with fallback chain
        COALESCE(
            t_name.translated_text,
            t_name_en.translated_text,
            c.name
        ) AS name_translated,
        -- Description translation with fallback chain
        COALESCE(
            t_desc.translated_text,
            t_desc_en.translated_text,
            c.description
        ) AS description_translated,
        -- Initial message translation with fallback chain
        COALESCE(
            t_msg.translated_text,
            t_msg_en.translated_text,
            c.initial_message
        ) AS initial_message_translated,
        -- Which language was actually used
        CASE
            WHEN t_name.translated_text IS NOT NULL THEN p_language_code
            WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
            ELSE 'original'
        END AS translation_language
    FROM chats c
    INNER JOIN participants p ON p.chat_id = c.id
        AND p.user_id = p_user_id
        AND p.status = 'active'
    -- Name translations
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name'
        AND t_name.language_code = p_language_code
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name'
        AND t_name_en.language_code = 'en'
        AND p_language_code != 'en'
    -- Description translations
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND t_desc.language_code = p_language_code
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description'
        AND t_desc_en.language_code = 'en'
        AND p_language_code != 'en'
    -- Initial message translations
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

COMMENT ON FUNCTION public.get_my_chats_translated(UUID, TEXT)
IS 'Returns all chats the user is participating in with translated name, description, and initial_message. Fallback: requested language -> English -> original';

-- ==============================================================================
-- 3. GET CHAT BY INVITE CODE WITH TRANSLATIONS
-- ==============================================================================

-- Get a chat by invite code with translations (for Join dialog)
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
    translation_language TEXT
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
        -- Name translation with fallback chain
        COALESCE(
            t_name.translated_text,
            t_name_en.translated_text,
            c.name
        ) AS name_translated,
        -- Description translation with fallback chain
        COALESCE(
            t_desc.translated_text,
            t_desc_en.translated_text,
            c.description
        ) AS description_translated,
        -- Initial message translation with fallback chain
        COALESCE(
            t_msg.translated_text,
            t_msg_en.translated_text,
            c.initial_message
        ) AS initial_message_translated,
        -- Which language was actually used
        CASE
            WHEN t_name.translated_text IS NOT NULL THEN p_language_code
            WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
            ELSE 'original'
        END AS translation_language
    FROM chats c
    -- Name translations
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name'
        AND t_name.language_code = p_language_code
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name'
        AND t_name_en.language_code = 'en'
        AND p_language_code != 'en'
    -- Description translations
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND t_desc.language_code = p_language_code
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description'
        AND t_desc_en.language_code = 'en'
        AND p_language_code != 'en'
    -- Initial message translations
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

COMMENT ON FUNCTION public.get_chat_by_code_translated(TEXT, TEXT)
IS 'Returns a chat by invite code with translated fields. For Join dialog. Fallback: requested language -> English -> original';
