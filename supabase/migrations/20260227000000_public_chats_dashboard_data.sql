-- Migration: Add dashboard data (phase/timer) to public chats RPCs
-- Adds current_round_phase, current_round_custom_id, current_round_phase_ends_at,
-- current_round_phase_started_at, schedule_paused, and host_paused to all 4
-- public chat discovery functions using the same LEFT JOIN LATERAL pattern
-- from get_my_chats_dashboard.

-- Must DROP first because RETURNS TABLE columns are changing.
DROP FUNCTION IF EXISTS get_public_chats(INTEGER, INTEGER, UUID);
DROP FUNCTION IF EXISTS search_public_chats(TEXT, INTEGER, INTEGER, UUID);
DROP FUNCTION IF EXISTS public.get_public_chats_translated(INTEGER, INTEGER, UUID, TEXT);
DROP FUNCTION IF EXISTS public.search_public_chats_translated(TEXT, INTEGER, INTEGER, UUID, TEXT);

-- ============================================================
-- 1. get_public_chats: add dashboard columns
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
    translation_languages TEXT[],
    current_round_phase TEXT,
    current_round_custom_id INTEGER,
    current_round_phase_ends_at TIMESTAMPTZ,
    current_round_phase_started_at TIMESTAMPTZ,
    schedule_paused BOOLEAN,
    host_paused BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        pc.cnt AS participant_count,
        c.created_at,
        c.last_activity_at,
        c.translation_languages,
        ar.phase::TEXT AS current_round_phase,
        ar.custom_id AS current_round_custom_id,
        ar.phase_ends_at AS current_round_phase_ends_at,
        ar.phase_started_at AS current_round_phase_started_at,
        c.schedule_paused,
        c.host_paused
    FROM chats c
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM participants p
        WHERE p.chat_id = c.id AND p.status = 'active'
    ) pc ON true
    LEFT JOIN LATERAL (
        SELECT r.phase, r.custom_id, r.phase_ends_at, r.phase_started_at
        FROM cycles cy
        JOIN rounds r ON r.cycle_id = cy.id
        WHERE cy.chat_id = c.id
          AND cy.completed_at IS NULL
          AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC
        LIMIT 1
    ) ar ON true
    WHERE c.is_active = true
      AND c.access_method = 'public'
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    ORDER BY c.name ASC
    LIMIT p_limit
    OFFSET p_offset;
$$;

-- ============================================================
-- 2. search_public_chats: add dashboard columns
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
    translation_languages TEXT[],
    current_round_phase TEXT,
    current_round_custom_id INTEGER,
    current_round_phase_ends_at TIMESTAMPTZ,
    current_round_phase_started_at TIMESTAMPTZ,
    schedule_paused BOOLEAN,
    host_paused BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT
        c.id,
        c.name,
        c.description,
        c.initial_message,
        pc.cnt AS participant_count,
        c.created_at,
        c.last_activity_at,
        c.translation_languages,
        ar.phase::TEXT AS current_round_phase,
        ar.custom_id AS current_round_custom_id,
        ar.phase_ends_at AS current_round_phase_ends_at,
        ar.phase_started_at AS current_round_phase_started_at,
        c.schedule_paused,
        c.host_paused
    FROM chats c
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM participants p
        WHERE p.chat_id = c.id AND p.status = 'active'
    ) pc ON true
    LEFT JOIN LATERAL (
        SELECT r.phase, r.custom_id, r.phase_ends_at, r.phase_started_at
        FROM cycles cy
        JOIN rounds r ON r.cycle_id = cy.id
        WHERE cy.chat_id = c.id
          AND cy.completed_at IS NULL
          AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC
        LIMIT 1
    ) ar ON true
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
    ORDER BY c.name ASC
    LIMIT p_limit
    OFFSET p_offset;
$$;

-- ============================================================
-- 3. get_public_chats_translated: add dashboard columns
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
    translation_languages TEXT[],
    current_round_phase TEXT,
    current_round_custom_id INTEGER,
    current_round_phase_ends_at TIMESTAMPTZ,
    current_round_phase_started_at TIMESTAMPTZ,
    schedule_paused BOOLEAN,
    host_paused BOOLEAN
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
        pc.cnt AS participant_count,
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
        c.translation_languages,
        ar.phase::TEXT AS current_round_phase,
        ar.custom_id AS current_round_custom_id,
        ar.phase_ends_at AS current_round_phase_ends_at,
        ar.phase_started_at AS current_round_phase_started_at,
        c.schedule_paused,
        c.host_paused
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
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM participants p
        WHERE p.chat_id = c.id AND p.status = 'active'
    ) pc ON true
    LEFT JOIN LATERAL (
        SELECT r.phase, r.custom_id, r.phase_ends_at, r.phase_started_at
        FROM cycles cy
        JOIN rounds r ON r.cycle_id = cy.id
        WHERE cy.chat_id = c.id
          AND cy.completed_at IS NULL
          AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC
        LIMIT 1
    ) ar ON true
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
             t_msg.translated_text, t_msg_en.translated_text,
             ar.phase, ar.custom_id, ar.phase_ends_at, ar.phase_started_at,
             pc.cnt
    ORDER BY COALESCE(t_name.translated_text, t_name_en.translated_text, c.name) ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- ============================================================
-- 4. search_public_chats_translated: add dashboard columns
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
    translation_languages TEXT[],
    current_round_phase TEXT,
    current_round_custom_id INTEGER,
    current_round_phase_ends_at TIMESTAMPTZ,
    current_round_phase_started_at TIMESTAMPTZ,
    schedule_paused BOOLEAN,
    host_paused BOOLEAN
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
        pc.cnt AS participant_count,
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
        c.translation_languages,
        ar.phase::TEXT AS current_round_phase,
        ar.custom_id AS current_round_custom_id,
        ar.phase_ends_at AS current_round_phase_ends_at,
        ar.phase_started_at AS current_round_phase_started_at,
        c.schedule_paused,
        c.host_paused
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
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM participants p
        WHERE p.chat_id = c.id AND p.status = 'active'
    ) pc ON true
    LEFT JOIN LATERAL (
        SELECT r.phase, r.custom_id, r.phase_ends_at, r.phase_started_at
        FROM cycles cy
        JOIN rounds r ON r.cycle_id = cy.id
        WHERE cy.chat_id = c.id
          AND cy.completed_at IS NULL
          AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC
        LIMIT 1
    ) ar ON true
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
             t_msg.translated_text, t_msg_en.translated_text,
             ar.phase, ar.custom_id, ar.phase_ends_at, ar.phase_started_at,
             pc.cnt
    ORDER BY COALESCE(t_name.translated_text, t_name_en.translated_text, c.name) ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;
