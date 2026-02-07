-- Security Hardening Wave 2
-- Fixes CRITICAL and HIGH vulnerabilities from the auth.uid() migration (20260113230000)
--
-- Changes:
-- A. Restrict chats SELECT: stop leaking private chats to anonymous users
-- B. Add get_chat_by_code() RPC: SECURITY DEFINER for join-by-code flow
-- C. Restore access_method validation on participants INSERT
-- D. Restore participant_can_access_round() on propositions INSERT
-- E. REVOKE scoring functions from anon/authenticated (DoS prevention)
-- F. Fix owns_participant() to require active status

-- =============================================================================
-- A. Restrict chats SELECT — stop leaking private chats
-- =============================================================================
-- BEFORE: "Anyone can view active chats" USING (is_active = true)
--   → exposes ALL active chats including invite_only + code (with invite codes!)
-- AFTER: Public chats discoverable; others require participation

DROP POLICY IF EXISTS "Anyone can view active chats" ON public.chats;

CREATE POLICY "Users can view relevant chats" ON public.chats
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (is_active = true AND access_method = 'public')
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = chats.id
        AND p.user_id = auth.uid()
    )
);

-- =============================================================================
-- B. Add get_chat_by_code() RPC — SECURITY DEFINER for join-by-code flow
-- =============================================================================
-- The new restrictive SELECT policy blocks non-participants from seeing code chats.
-- This RPC allows users to look up a chat by invite code to initiate joining.

CREATE OR REPLACE FUNCTION get_chat_by_code(p_invite_code TEXT)
RETURNS SETOF chats
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
    SELECT c.*
    FROM chats c
    WHERE c.invite_code = UPPER(p_invite_code)
    AND c.is_active = true
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION get_chat_by_code(TEXT) TO authenticated, anon;

-- =============================================================================
-- C. Restore access_method validation on participants INSERT
-- =============================================================================
-- BEFORE: Only checked user_id = auth.uid() — anyone could join ANY chat
-- AFTER: Validates access_method. invite_only joins go through
--   approve_join_request() SECURITY DEFINER RPC, so don't need RLS path.
--
-- NOTE: We use a SECURITY DEFINER helper function because the chats SELECT
-- policy (part A) restricts visibility of non-public chats. Without it, the
-- EXISTS subquery would fail for code chats since the user isn't a participant yet.

CREATE OR REPLACE FUNCTION chat_allows_direct_join(p_chat_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM chats c
        WHERE c.id = p_chat_id
        AND c.is_active = true
        AND c.access_method IN ('public', 'code')
    );
$$;

DROP POLICY IF EXISTS "Users can join with valid access" ON participants;

CREATE POLICY "Users can join with valid access" ON participants
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (
        user_id = auth.uid()
        AND chat_allows_direct_join(chat_id)
    )
);

-- =============================================================================
-- D. Restore participant_can_access_round() on propositions INSERT
-- =============================================================================
-- BEFORE: Only checked owns_participant() — cross-chat proposition injection possible
-- AFTER: Re-adds the participant_can_access_round() check that was dropped in
--   the auth.uid() migration (20260113230000, line 164-169)

DROP POLICY IF EXISTS "Participants can create own propositions" ON propositions;

CREATE POLICY "Participants can create own propositions" ON propositions
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (
        owns_participant(participant_id)
        AND participant_can_access_round(participant_id, round_id)
    )
);

-- =============================================================================
-- E. REVOKE scoring functions from anon/authenticated & add host-only wrapper
-- =============================================================================
-- Direct access to scoring functions allows DoS via repeated recalculation.
-- Revoke direct access and provide a host-only wrapper for the Flutter client.

REVOKE EXECUTE ON FUNCTION calculate_movda_scores_for_round(BIGINT, DOUBLE PRECISION) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION store_round_ranks(BIGINT) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION calculate_voting_ranks(BIGINT) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION calculate_proposing_ranks(BIGINT) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION calculate_round_ranks(BIGINT) FROM public, anon, authenticated;

-- Host-only wrapper: validates the caller is the host of the chat that owns the round,
-- then delegates to the actual scoring function.
CREATE OR REPLACE FUNCTION host_calculate_movda_scores(p_round_id BIGINT)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_chat_id BIGINT;
BEGIN
    -- Get chat_id from the round
    SELECT c.chat_id INTO v_chat_id
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = p_round_id;

    IF v_chat_id IS NULL THEN
        RAISE EXCEPTION 'Round not found';
    END IF;

    -- Verify caller is the host
    IF NOT EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = v_chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Only the host can trigger score calculation';
    END IF;

    -- Delegate to the actual function
    PERFORM calculate_movda_scores_for_round(p_round_id);
END;
$$;

GRANT EXECUTE ON FUNCTION host_calculate_movda_scores(BIGINT) TO anon, authenticated;

-- =============================================================================
-- F. Fix owns_participant() to require active status
-- =============================================================================
-- BEFORE: Didn't check status — kicked/left participants could still pass
--   ownership checks and submit propositions/ratings
-- AFTER: Only active participants pass

CREATE OR REPLACE FUNCTION owns_participant(p_participant_id BIGINT)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID;
    participant_user_id UUID;
BEGIN
    current_user_id := auth.uid();
    IF current_user_id IS NULL THEN RETURN FALSE; END IF;
    SELECT p.user_id INTO participant_user_id
    FROM participants p
    WHERE p.id = p_participant_id AND p.status = 'active';
    RETURN current_user_id = participant_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
