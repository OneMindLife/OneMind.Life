-- =============================================================================
-- MIGRATION: Fix RLS policies to validate chat membership
-- =============================================================================
-- CRITICAL FIX: Previous RLS policies only checked participant ownership,
-- but didn't verify the participant belonged to the chat where the
-- round/proposition was being created.
--
-- Attack vector (before fix):
--   1. User joins Chat A, gets participant_id = 100
--   2. User finds Chat B's round_id = 50 (from API response)
--   3. User submits proposition with participant_id=100, round_id=50
--   4. Old policy: owns_participant(100) = TRUE → allowed!
--   5. Proposition appears in Chat B even though user isn't a member
--
-- Fix: Validate that participant's chat_id matches the round's chat_id
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Create helper function to validate participant-round relationship
-- =============================================================================

-- Check if participant belongs to the same chat as the round
CREATE OR REPLACE FUNCTION public.participant_can_access_round(
    p_participant_id BIGINT,
    p_round_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    participant_chat_id BIGINT;
    round_chat_id BIGINT;
BEGIN
    -- Get participant's chat
    SELECT chat_id INTO participant_chat_id
    FROM participants
    WHERE id = p_participant_id;

    IF participant_chat_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Get round's chat (through cycle)
    SELECT c.chat_id INTO round_chat_id
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = p_round_id;

    IF round_chat_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Must match
    RETURN participant_chat_id = round_chat_id;
END;
$$;

-- Check if participant belongs to the same chat as the proposition
CREATE OR REPLACE FUNCTION public.participant_can_access_proposition(
    p_participant_id BIGINT,
    p_proposition_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    participant_chat_id BIGINT;
    proposition_chat_id BIGINT;
BEGIN
    -- Get participant's chat
    SELECT chat_id INTO participant_chat_id
    FROM participants
    WHERE id = p_participant_id;

    IF participant_chat_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Get proposition's chat (through round -> cycle)
    SELECT c.chat_id INTO proposition_chat_id
    FROM propositions p
    JOIN rounds r ON r.id = p.round_id
    JOIN cycles c ON c.id = r.cycle_id
    WHERE p.id = p_proposition_id;

    IF proposition_chat_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Must match
    RETURN participant_chat_id = proposition_chat_id;
END;
$$;

-- =============================================================================
-- STEP 2: Drop and recreate propositions INSERT policy
-- =============================================================================

DROP POLICY IF EXISTS "Participants can create own propositions" ON "public"."propositions";

-- New policy: Must own participant AND participant must belong to the round's chat
CREATE POLICY "Participants can create own propositions" ON "public"."propositions"
FOR INSERT
WITH CHECK (
    -- Service role can always insert (for edge functions, migrations, tests)
    (current_setting('role', true) = 'service_role')
    OR
    -- No session token = tests/direct DB access (skip RLS check)
    (public.get_session_token() IS NULL)
    OR
    (
        -- User must own the participant
        public.owns_participant(participant_id)
        AND
        -- Participant must belong to the same chat as the round
        public.participant_can_access_round(participant_id, round_id)
    )
);

-- =============================================================================
-- STEP 3: Drop and recreate ratings INSERT policy
-- =============================================================================

DROP POLICY IF EXISTS "Participants can submit own ratings" ON "public"."ratings";

-- New policy: Must own participant AND participant must belong to the proposition's chat
CREATE POLICY "Participants can submit own ratings" ON "public"."ratings"
FOR INSERT
WITH CHECK (
    -- Service role can always insert
    (current_setting('role', true) = 'service_role')
    OR
    -- No session token = tests/direct DB access
    (public.get_session_token() IS NULL)
    OR
    (
        -- User must own the participant
        public.owns_participant(participant_id)
        AND
        -- Participant must belong to the same chat as the proposition
        public.participant_can_access_proposition(participant_id, proposition_id)
    )
);

-- =============================================================================
-- STEP 4: Add policy for ratings UPDATE (upsert needs this)
-- =============================================================================

DROP POLICY IF EXISTS "Participants can update own ratings" ON "public"."ratings";

CREATE POLICY "Participants can update own ratings" ON "public"."ratings"
FOR UPDATE
USING (
    (current_setting('role', true) = 'service_role')
    OR
    (public.get_session_token() IS NULL)
    OR
    (
        public.owns_participant(participant_id)
        AND
        public.participant_can_access_proposition(participant_id, proposition_id)
    )
)
WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR
    (public.get_session_token() IS NULL)
    OR
    (
        public.owns_participant(participant_id)
        AND
        public.participant_can_access_proposition(participant_id, proposition_id)
    )
);

-- =============================================================================
-- STEP 5: Grant permissions on new functions
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.participant_can_access_round(BIGINT, BIGINT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.participant_can_access_proposition(BIGINT, BIGINT) TO anon, authenticated, service_role;

COMMIT;
