-- Migration: Exclude original author from rating carried propositions
--
-- Problem: When a proposition is carried forward, the original author can still
-- rate it if they've left and rejoined the chat (getting a new participant_id).
-- The current check compares participant_id, but should compare user_id.
--
-- Solution:
-- 1. Create helper function to get original author's user_id from a proposition
-- 2. Update get_unranked_propositions() to exclude by user_id

-- =============================================================================
-- STEP 1: Create function to get original author's user_id
-- =============================================================================

CREATE OR REPLACE FUNCTION get_original_author_user_id(p_proposition_id BIGINT)
RETURNS UUID AS $$
DECLARE
    v_root_prop_id BIGINT;
    v_participant_id BIGINT;
    v_user_id UUID;
BEGIN
    -- Get the root proposition ID (follows carried_from_id chain)
    v_root_prop_id := get_root_proposition_id(p_proposition_id);

    -- Get the participant_id of the root proposition
    SELECT participant_id INTO v_participant_id
    FROM propositions
    WHERE id = v_root_prop_id;

    -- Get the user_id of that participant
    SELECT user_id INTO v_user_id
    FROM participants
    WHERE id = v_participant_id;

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_original_author_user_id(BIGINT) IS
'Gets the user_id of the original author of a proposition.
For carried propositions, follows the carried_from_id chain to find the root.';

GRANT EXECUTE ON FUNCTION get_original_author_user_id(BIGINT) TO anon, authenticated, service_role;

-- =============================================================================
-- STEP 2: Update get_unranked_propositions to exclude by user_id
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."get_unranked_propositions"(
    "p_round_id" BIGINT,
    "p_participant_id" BIGINT DEFAULT NULL,
    "p_session_token" UUID DEFAULT NULL
)
RETURNS TABLE (
    proposition_id BIGINT,
    content TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    -- Get the user_id for the participant (if provided)
    IF p_participant_id IS NOT NULL THEN
        SELECT user_id INTO v_current_user_id
        FROM participants
        WHERE id = p_participant_id;
    END IF;

    -- Get propositions that this user hasn't ranked yet
    -- Excludes:
    -- 1. User's own propositions (by participant_id)
    -- 2. Propositions where user is the ORIGINAL author (for carried props)
    -- 3. Already ranked propositions
    RETURN QUERY
    SELECT
        p.id as proposition_id,
        p.content,
        p.created_at
    FROM propositions p
    WHERE p.round_id = p_round_id
    -- Exclude own propositions (by participant_id if available)
    AND (p_participant_id IS NULL OR p.participant_id IS DISTINCT FROM p_participant_id)
    -- Exclude propositions where user is the ORIGINAL author (handles carried props)
    AND (v_current_user_id IS NULL OR get_original_author_user_id(p.id) IS DISTINCT FROM v_current_user_id)
    -- Exclude already ranked
    AND NOT EXISTS (
        SELECT 1 FROM grid_rankings gr
        WHERE gr.round_id = p_round_id
        AND gr.proposition_id = p.id
        AND (
            (p_participant_id IS NOT NULL AND gr.participant_id = p_participant_id)
            OR
            (p_session_token IS NOT NULL AND gr.session_token = p_session_token)
        )
    )
    ORDER BY p.created_at;
END;
$$;

COMMENT ON FUNCTION "public"."get_unranked_propositions"(BIGINT, BIGINT, UUID) IS
'Returns propositions that a user has not yet ranked in a round.
Pass either participant_id or session_token to identify the user.
Excludes:
- The user''s own propositions (by participant_id)
- Propositions where user is the ORIGINAL author (for carried forward props)
- Already ranked propositions';
