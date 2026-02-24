-- Update all public chat RPC functions to:
-- 1. Order alphabetically by name (ASC) instead of last_activity_at DESC
-- 2. Add offset support to search functions for pagination

-- ============================================================
-- get_public_chats: already has limit/offset, just change ordering
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
    last_activity_at TIMESTAMPTZ
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
        c.last_activity_at
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
-- search_public_chats: add p_offset parameter, alphabetical order
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
    last_activity_at TIMESTAMPTZ
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
        c.last_activity_at
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
-- get_public_chats_translated: alphabetical by translated name
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
        END AS translation_language
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
-- search_public_chats_translated: add p_offset, alphabetical order
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
        END AS translation_language
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
