-- Migration: Add translations support
-- Adds language_code to users table and creates translations table for AI-translated content

-- ==============================================================================
-- 1. ADD LANGUAGE_CODE TO USERS TABLE
-- ==============================================================================

-- Add language_code column with default 'en'
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS language_code text DEFAULT 'en' NOT NULL;

-- Add constraint to validate language codes (en, es for now)
ALTER TABLE public.users
ADD CONSTRAINT users_language_code_check
CHECK (language_code IN ('en', 'es'));

-- ==============================================================================
-- 2. CREATE TRANSLATIONS TABLE
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.translations (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proposition_id bigint NOT NULL REFERENCES public.propositions(id) ON DELETE CASCADE,
    entity_type text NOT NULL DEFAULT 'proposition',
    field_name text NOT NULL DEFAULT 'content',
    language_code text NOT NULL,
    translated_text text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,

    -- Validate language codes
    CONSTRAINT translations_language_code_check CHECK (language_code IN ('en', 'es')),

    -- Each proposition can only have one translation per field per language
    CONSTRAINT translations_unique_key UNIQUE (proposition_id, field_name, language_code)
);

-- Comment on table
COMMENT ON TABLE public.translations IS 'Stores AI-generated translations of user content (propositions)';

-- ==============================================================================
-- 3. ROW LEVEL SECURITY
-- ==============================================================================

-- Enable RLS
ALTER TABLE public.translations ENABLE ROW LEVEL SECURITY;

-- Anyone can read translations (public content)
CREATE POLICY "translations_select_policy"
ON public.translations
FOR SELECT
USING (true);

-- Only service role can insert translations (via Edge Function)
CREATE POLICY "translations_insert_policy"
ON public.translations
FOR INSERT
WITH CHECK ((SELECT auth.role()) = 'service_role');

-- Only service role can update translations
CREATE POLICY "translations_update_policy"
ON public.translations
FOR UPDATE
USING ((SELECT auth.role()) = 'service_role');

-- Only service role can delete translations
CREATE POLICY "translations_delete_policy"
ON public.translations
FOR DELETE
USING ((SELECT auth.role()) = 'service_role');

-- ==============================================================================
-- 4. INDEXES
-- ==============================================================================

-- Index for looking up translations by proposition
CREATE INDEX IF NOT EXISTS idx_translations_proposition_id
ON public.translations (proposition_id);

-- Composite index for efficient lookups
CREATE INDEX IF NOT EXISTS idx_translations_lookup
ON public.translations (proposition_id, field_name, language_code);

-- ==============================================================================
-- 5. RPC FUNCTIONS
-- ==============================================================================

-- Get user's preferred language code
CREATE OR REPLACE FUNCTION public.get_user_language_code()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    RETURN COALESCE(
        (SELECT language_code FROM public.users WHERE id = auth.uid()),
        'en'
    );
END;
$$;

COMMENT ON FUNCTION public.get_user_language_code() IS 'Returns the current user''s preferred language code, defaulting to en';

-- Update user's preferred language code
CREATE OR REPLACE FUNCTION public.update_user_language_code(p_language_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Validate language code
    IF p_language_code NOT IN ('en', 'es') THEN
        RAISE EXCEPTION 'Unsupported language code: %. Supported: en, es', p_language_code;
    END IF;

    -- Update user's language preference
    UPDATE public.users
    SET language_code = p_language_code
    WHERE id = auth.uid();

    RETURN true;
END;
$$;

COMMENT ON FUNCTION public.update_user_language_code(text) IS 'Updates the current user''s preferred language code';

-- ==============================================================================
-- 6. GET PROPOSITIONS WITH TRANSLATIONS
-- ==============================================================================

-- Function to get propositions with translated content
-- Fallback chain: requested_language -> 'en' -> original content
CREATE OR REPLACE FUNCTION public.get_propositions_with_translations(
    p_round_id bigint,
    p_language_code text DEFAULT 'en'
)
RETURNS TABLE(
    id bigint,
    round_id bigint,
    user_id uuid,
    content text,
    content_translated text,
    language_code text,
    created_at timestamp with time zone,
    carried_from_id bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.round_id,
        p.user_id,
        p.content,
        -- Fallback chain: requested language -> English -> original content
        COALESCE(
            -- First try: requested language
            t.translated_text,
            -- Second try: English (if requested language is not English)
            CASE WHEN p_language_code != 'en' THEN (
                SELECT t2.translated_text
                FROM public.translations t2
                WHERE t2.proposition_id = p.id
                  AND t2.field_name = 'content'
                  AND t2.language_code = 'en'
                LIMIT 1
            ) ELSE NULL END,
            -- Fallback: original content
            p.content
        ) as content_translated,
        COALESCE(t.language_code, 'original') as language_code,
        p.created_at,
        p.carried_from_id
    FROM public.propositions p
    LEFT JOIN public.translations t
        ON t.proposition_id = p.id
        AND t.field_name = 'content'
        AND t.language_code = p_language_code
    WHERE p.round_id = p_round_id
    ORDER BY p.created_at ASC;
END;
$$;

COMMENT ON FUNCTION public.get_propositions_with_translations(bigint, text) IS 'Returns propositions for a round with translated content based on user language preference';

-- ==============================================================================
-- 7. CLEANUP TRIGGER (delete translations when proposition is deleted)
-- ==============================================================================

-- Trigger function to delete translations when proposition is deleted
CREATE OR REPLACE FUNCTION public.delete_proposition_translations()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM public.translations WHERE proposition_id = OLD.id;
    RETURN OLD;
END;
$$;

-- Create trigger if it doesn't exist
DROP TRIGGER IF EXISTS trigger_delete_proposition_translations ON public.propositions;
CREATE TRIGGER trigger_delete_proposition_translations
    BEFORE DELETE ON public.propositions
    FOR EACH ROW
    EXECUTE FUNCTION public.delete_proposition_translations();
