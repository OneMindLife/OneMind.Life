-- =============================================================================
-- MIGRATION: Add allow_skip_proposing/allow_skip_rating to chat RPCs
-- =============================================================================
-- The allow_skip columns were added to the chats table but the RPCs that
-- return chat data via RETURNS TABLE didn't include them. This caused
-- Chat.fromJson to default to true (allow skip) even when the DB had false.
--
-- Functions updated:
-- 1. get_chat_translated
-- 2. get_chat_by_code_translated
-- 3. get_my_chats_translated
-- 4. get_my_chats_dashboard
--
-- Must DROP first because RETURNS TABLE changes are not allowed with
-- CREATE OR REPLACE.
-- =============================================================================

-- Drop functions (must match exact signatures)
DROP FUNCTION IF EXISTS public.get_chat_translated(BIGINT, TEXT);
DROP FUNCTION IF EXISTS public.get_chat_by_code_translated(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.get_my_chats_translated(UUID, TEXT);
DROP FUNCTION IF EXISTS public.get_my_chats_dashboard(UUID, TEXT);


-- =============================================================================
-- 1. get_chat_translated
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_chat_translated(
    p_chat_id BIGINT,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE(
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
    allow_skip_proposing BOOLEAN,
    allow_skip_rating BOOLEAN,
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
        c.allow_skip_proposing,
        c.allow_skip_rating,
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


-- =============================================================================
-- 2. get_chat_by_code_translated
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_chat_by_code_translated(
    p_invite_code TEXT,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE(
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
    allow_skip_proposing BOOLEAN,
    allow_skip_rating BOOLEAN,
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
        c.allow_skip_proposing,
        c.allow_skip_rating,
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
-- 3. get_my_chats_translated
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_my_chats_translated(
    p_user_id UUID,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE(
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
    allow_skip_proposing BOOLEAN,
    allow_skip_rating BOOLEAN,
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
        c.allow_skip_proposing,
        c.allow_skip_rating,
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
            WHEN t_name.translated_text IS NOT NULL THEN COALESCE(p.viewing_language_code, p_language_code)
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
        AND t_name.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name'
        AND t_name_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND t_desc.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description'
        AND t_desc_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN translations t_msg ON t_msg.chat_id = c.id
        AND t_msg.field_name = 'initial_message'
        AND t_msg.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_msg_en ON t_msg_en.chat_id = c.id
        AND t_msg_en.field_name = 'initial_message'
        AND t_msg_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    WHERE c.is_active = true
    ORDER BY c.last_activity_at DESC NULLS LAST;
END;
$$;


-- =============================================================================
-- 4. get_my_chats_dashboard
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_my_chats_dashboard(
    p_user_id UUID,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE(
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
    allow_skip_proposing BOOLEAN,
    allow_skip_rating BOOLEAN,
    name_translated TEXT,
    description_translated TEXT,
    initial_message_translated TEXT,
    translation_language TEXT,
    translations_enabled BOOLEAN,
    translation_languages TEXT[],
    participant_count BIGINT,
    current_cycle_id BIGINT,
    current_round_phase TEXT,
    current_round_custom_id INTEGER,
    current_round_phase_ends_at TIMESTAMPTZ,
    current_round_phase_started_at TIMESTAMPTZ,
    viewing_language_code TEXT
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
        c.allow_skip_proposing,
        c.allow_skip_rating,
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
            WHEN t_name.translated_text IS NOT NULL THEN COALESCE(p.viewing_language_code, p_language_code)
            WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
            ELSE 'original'
        END AS translation_language,
        c.translations_enabled,
        c.translation_languages,
        pc.cnt AS participant_count,
        ar.cycle_id AS current_cycle_id,
        ar.phase::TEXT AS current_round_phase,
        ar.custom_id AS current_round_custom_id,
        ar.phase_ends_at AS current_round_phase_ends_at,
        ar.phase_started_at AS current_round_phase_started_at,
        p.viewing_language_code
    FROM chats c
    INNER JOIN participants p ON p.chat_id = c.id
        AND p.user_id = p_user_id
        AND p.status = 'active'
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name'
        AND t_name.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name'
        AND t_name_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND t_desc.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description'
        AND t_desc_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN translations t_msg ON t_msg.chat_id = c.id
        AND t_msg.field_name = 'initial_message'
        AND t_msg.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_msg_en ON t_msg_en.chat_id = c.id
        AND t_msg_en.field_name = 'initial_message'
        AND t_msg_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM participants p2
        WHERE p2.chat_id = c.id AND p2.status = 'active'
    ) pc ON true
    LEFT JOIN LATERAL (
        SELECT r.cycle_id, r.phase, r.custom_id, r.phase_ends_at, r.phase_started_at
        FROM cycles cy
        JOIN rounds r ON r.cycle_id = cy.id
        WHERE cy.chat_id = c.id
          AND cy.completed_at IS NULL
          AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC
        LIMIT 1
    ) ar ON true
    WHERE c.is_active = true
    ORDER BY c.last_activity_at DESC NULLS LAST;
END;
$$;
