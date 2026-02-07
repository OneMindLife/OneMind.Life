-- Migration: Add find_duplicate_proposition function
-- Purpose: Reliable duplicate detection for submit-proposition Edge Function
--
-- The previous PostgREST query using embedded resource filtering was unreliable.
-- This function uses explicit SQL joins for consistent behavior.

CREATE OR REPLACE FUNCTION find_duplicate_proposition(
  p_round_id bigint,
  p_normalized_english text
)
RETURNS TABLE (
  proposition_id bigint,
  content text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT 
    p.id AS proposition_id,
    p.content
  FROM propositions p
  INNER JOIN translations t ON t.proposition_id = p.id
  WHERE p.round_id = p_round_id
    AND t.field_name = 'content'
    AND t.language_code = 'en'
    AND LOWER(TRIM(t.translated_text)) = p_normalized_english
  LIMIT 1;
$$;

-- Grant access to service role (Edge Functions use service role)
GRANT EXECUTE ON FUNCTION find_duplicate_proposition(bigint, text) TO service_role;

-- Also grant to authenticated users in case we need it later
GRANT EXECUTE ON FUNCTION find_duplicate_proposition(bigint, text) TO authenticated;

COMMENT ON FUNCTION find_duplicate_proposition IS 
  'Find existing proposition in a round with matching normalized English translation. 
   Used by submit-proposition Edge Function for duplicate detection.';
