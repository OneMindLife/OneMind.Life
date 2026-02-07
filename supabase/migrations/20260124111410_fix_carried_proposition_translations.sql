-- Fix: get_propositions_with_translations should look up translations from original proposition
-- for carried-forward propositions (via carried_from_id)
--
-- Bug: Carried propositions (196, 203) have no translations because the function
-- looks for translations by p.id, but translations are stored under the original's ID.
-- Fix: Use COALESCE(p.carried_from_id, p.id) to find the original proposition's translations.

CREATE OR REPLACE FUNCTION public.get_propositions_with_translations(
    p_round_id bigint,
    p_language_code text DEFAULT 'en'::text
)
RETURNS TABLE(
    id bigint,
    round_id bigint,
    participant_id bigint,
    content text,
    content_translated text,
    language_code text,
    created_at timestamp with time zone,
    carried_from_id bigint,
    proposition_global_scores jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.round_id,
        p.participant_id,
        p.content,
        -- Fallback chain: requested language -> English -> original content
        -- For carried propositions, look up translations from the ORIGINAL proposition
        COALESCE(
            -- First try: requested language (from original if carried)
            t.translated_text,
            -- Second try: English (if requested language is not English)
            CASE WHEN p_language_code != 'en' THEN (
                SELECT t2.translated_text
                FROM public.translations t2
                WHERE t2.proposition_id = COALESCE(p.carried_from_id, p.id)
                  AND t2.field_name = 'content'
                  AND t2.language_code = 'en'
                LIMIT 1
            ) ELSE NULL END,
            -- Fallback: original content
            p.content
        ) as content_translated,
        COALESCE(t.language_code, 'original') as language_code,
        p.created_at,
        p.carried_from_id,
        -- Include global_score as JSONB to match the expected format from Proposition.fromJson
        (
            SELECT jsonb_build_object('global_score', pgs.global_score)
            FROM public.proposition_global_scores pgs
            WHERE pgs.proposition_id = p.id
              AND pgs.round_id = p_round_id
            LIMIT 1
        ) as proposition_global_scores
    FROM public.propositions p
    -- Join translations using the ORIGINAL proposition ID for carried propositions
    LEFT JOIN public.translations t
        ON t.proposition_id = COALESCE(p.carried_from_id, p.id)
        AND t.field_name = 'content'
        AND t.language_code = p_language_code
    WHERE p.round_id = p_round_id
    ORDER BY p.created_at ASC;
END;
$function$;

COMMENT ON FUNCTION public.get_propositions_with_translations IS
'Get propositions with translations for a round. For carried-forward propositions,
looks up translations from the original proposition via carried_from_id.';
