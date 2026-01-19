-- Migration: Fix get_propositions_with_translations RPC
-- The original function incorrectly referenced user_id instead of participant_id

-- Must drop first because we're changing the return type signature
DROP FUNCTION IF EXISTS public.get_propositions_with_translations(bigint, text);

-- Recreate the function with correct column name
CREATE OR REPLACE FUNCTION public.get_propositions_with_translations(
    p_round_id bigint,
    p_language_code text DEFAULT 'en'
)
RETURNS TABLE(
    id bigint,
    round_id bigint,
    participant_id bigint,
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
        p.participant_id,
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
