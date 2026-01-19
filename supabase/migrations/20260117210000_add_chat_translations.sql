-- Migration: Add chat translation support
-- Extends the translations table to support chat name, description, and initial_message translations

-- ==============================================================================
-- 1. SCHEMA CHANGES
-- ==============================================================================

-- Make proposition_id nullable (was NOT NULL)
ALTER TABLE public.translations
ALTER COLUMN proposition_id DROP NOT NULL;

-- Add chat_id column with FK to chats
ALTER TABLE public.translations
ADD COLUMN IF NOT EXISTS chat_id bigint REFERENCES public.chats(id) ON DELETE CASCADE;

-- Add CHECK constraint: exactly one of proposition_id or chat_id must be set
ALTER TABLE public.translations
ADD CONSTRAINT translations_entity_check
CHECK (
    (proposition_id IS NOT NULL AND chat_id IS NULL)
    OR (proposition_id IS NULL AND chat_id IS NOT NULL)
);

-- ==============================================================================
-- 2. INDEXES
-- ==============================================================================

-- Unique index for chat translations (chat_id, field_name, language_code)
CREATE UNIQUE INDEX IF NOT EXISTS idx_translations_chat_unique
ON public.translations (chat_id, field_name, language_code)
WHERE chat_id IS NOT NULL;

-- Lookup index for chat translations
CREATE INDEX IF NOT EXISTS idx_translations_chat_id
ON public.translations (chat_id)
WHERE chat_id IS NOT NULL;

-- Composite lookup index for chat translations
CREATE INDEX IF NOT EXISTS idx_translations_chat_lookup
ON public.translations (chat_id, field_name, language_code)
WHERE chat_id IS NOT NULL;

-- ==============================================================================
-- 3. RPC FUNCTIONS
-- ==============================================================================

-- Get public chats with translations
-- Fallback chain: requested language -> English -> original content
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
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
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
      AND c.access_method = 'public'
      -- Exclude chats user has already joined (if user_id provided)
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id, t_name.translated_text, t_name_en.translated_text,
             t_desc.translated_text, t_desc_en.translated_text,
             t_msg.translated_text, t_msg_en.translated_text
    ORDER BY c.last_activity_at DESC NULLS LAST
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.get_public_chats_translated(INTEGER, INTEGER, UUID, TEXT)
IS 'Returns public chats with translated name, description, and initial_message. Fallback: requested language -> English -> original';

-- Search public chats with translations
-- Searches both original and translated text
CREATE OR REPLACE FUNCTION public.search_public_chats_translated(
    p_query TEXT,
    p_limit INTEGER DEFAULT 20,
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
    LEFT JOIN participants p ON p.chat_id = c.id AND p.status = 'active'
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
      AND c.access_method = 'public'
      -- Search in both original and translated text
      AND (
          c.name ILIKE '%' || p_query || '%'
          OR c.description ILIKE '%' || p_query || '%'
          OR c.initial_message ILIKE '%' || p_query || '%'
          OR t_name.translated_text ILIKE '%' || p_query || '%'
          OR t_desc.translated_text ILIKE '%' || p_query || '%'
          OR t_msg.translated_text ILIKE '%' || p_query || '%'
      )
      -- Exclude chats user has already joined (if user_id provided)
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id, t_name.translated_text, t_name_en.translated_text,
             t_desc.translated_text, t_desc_en.translated_text,
             t_msg.translated_text, t_msg_en.translated_text
    ORDER BY c.last_activity_at DESC NULLS LAST
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION public.search_public_chats_translated(TEXT, INTEGER, UUID, TEXT)
IS 'Search public chats with translations. Searches both original and translated text.';

-- ==============================================================================
-- 4. CLEANUP TRIGGER FOR CHAT TRANSLATIONS
-- ==============================================================================

-- Trigger function to delete chat translations when chat is deleted
CREATE OR REPLACE FUNCTION public.delete_chat_translations()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM public.translations WHERE chat_id = OLD.id;
    RETURN OLD;
END;
$$;

-- Create trigger if it doesn't exist
DROP TRIGGER IF EXISTS trigger_delete_chat_translations ON public.chats;
CREATE TRIGGER trigger_delete_chat_translations
    BEFORE DELETE ON public.chats
    FOR EACH ROW
    EXECUTE FUNCTION public.delete_chat_translations();
