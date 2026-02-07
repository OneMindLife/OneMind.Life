-- Migration: Add atomic proposition submission function
-- Purpose: Prevent duplicate propositions from race conditions using advisory locking

CREATE OR REPLACE FUNCTION submit_proposition_atomic(
    p_round_id bigint,
    p_participant_id bigint,
    p_content text,
    p_normalized_english text
)
RETURNS TABLE (
    status text,
    proposition_id bigint,
    content text,
    duplicate_id bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_existing_id bigint;
    v_existing_content text;
    v_new_id bigint;
BEGIN
    -- Acquire advisory lock for this round to serialize submissions
    PERFORM pg_advisory_xact_lock(p_round_id);

    -- Check for existing duplicate
    SELECT p.id, p.content
    INTO v_existing_id, v_existing_content
    FROM propositions p
    INNER JOIN translations t ON t.proposition_id = p.id
    WHERE p.round_id = p_round_id
        AND t.field_name = 'content'
        AND t.language_code = 'en'
        AND LOWER(TRIM(t.translated_text)) = p_normalized_english
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        RETURN QUERY SELECT
            'duplicate'::text AS status,
            NULL::bigint AS proposition_id,
            v_existing_content AS content,
            v_existing_id AS duplicate_id;
        RETURN;
    END IF;

    -- No duplicate - insert new proposition
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (p_round_id, p_participant_id, p_content)
    RETURNING id INTO v_new_id;

    RETURN QUERY SELECT
        'success'::text AS status,
        v_new_id AS proposition_id,
        p_content AS content,
        NULL::bigint AS duplicate_id;
END;
$$;
