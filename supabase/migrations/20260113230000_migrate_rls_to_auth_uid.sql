-- Migration: Replace get_session_token() with auth.uid() for Realtime compatibility
--
-- Problem: get_session_token() reads from request.headers which is only available
-- for REST API requests via PostgREST. Supabase Realtime uses WebSocket connections
-- where request.headers is NOT available, so get_session_token() returns NULL for
-- all Realtime events, causing RLS policies to fail.
--
-- Solution: Use auth.uid() which works with both REST API and Realtime WebSocket
-- connections because it reads from the JWT token.

-- =============================================================================
-- STEP 1: Create new helper functions that use auth.uid()
-- =============================================================================

-- Replace is_chat_participant to use auth.uid() instead of get_session_token()
CREATE OR REPLACE FUNCTION is_chat_participant(p_chat_id BIGINT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.participants
    WHERE chat_id = p_chat_id
    AND user_id = auth.uid()
    AND status = 'active'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Replace owns_participant to use auth.uid() instead of get_session_token()
CREATE OR REPLACE FUNCTION owns_participant(p_participant_id BIGINT)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID;
    participant_user_id UUID;
BEGIN
    current_user_id := auth.uid();

    IF current_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT p.user_id INTO participant_user_id
    FROM participants p
    WHERE p.id = p_participant_id;

    RETURN current_user_id = participant_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- =============================================================================
-- STEP 2: Update participants table policies
-- =============================================================================

-- participants SELECT policy
DROP POLICY IF EXISTS "Participants can view same chat participants" ON participants;
CREATE POLICY "Participants can view same chat participants" ON participants
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (user_id = auth.uid())
    OR is_chat_participant(chat_id)
);

-- participants DELETE policy
DROP POLICY IF EXISTS "Participants can leave chat" ON participants;
CREATE POLICY "Participants can leave chat" ON participants
FOR DELETE USING (
    user_id = auth.uid()
);

-- participants INSERT policy (update to use user_id = auth.uid())
DROP POLICY IF EXISTS "Users can join with valid access" ON participants;
CREATE POLICY "Users can join with valid access" ON participants
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (user_id = auth.uid())
);

-- =============================================================================
-- STEP 3: Update join_requests table policies
-- =============================================================================

DROP POLICY IF EXISTS "Users can view relevant join_requests" ON join_requests;
CREATE POLICY "Users can view relevant join_requests" ON join_requests
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (user_id = auth.uid())
    OR (EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = join_requests.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
    ))
);

DROP POLICY IF EXISTS "Users can create own join_requests" ON join_requests;
CREATE POLICY "Users can create own join_requests" ON join_requests
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (user_id = auth.uid())
);

-- =============================================================================
-- STEP 4: Update cycles table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view cycles" ON cycles;
CREATE POLICY "Chat participants can view cycles" ON cycles
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = cycles.chat_id
        AND p.user_id = auth.uid()
    ))
);

-- =============================================================================
-- STEP 5: Update rounds table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view rounds" ON rounds;
CREATE POLICY "Chat participants can view rounds" ON rounds
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        JOIN cycles c ON c.id = rounds.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
    ))
);

-- =============================================================================
-- STEP 6: Update round_winners table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view round_winners" ON round_winners;
CREATE POLICY "Chat participants can view round_winners" ON round_winners
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = round_winners.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
    ))
);

-- =============================================================================
-- STEP 7: Update propositions table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view propositions" ON propositions;
CREATE POLICY "Chat participants can view propositions" ON propositions
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = propositions.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
    ))
);

DROP POLICY IF EXISTS "Participants can create own propositions" ON propositions;
CREATE POLICY "Participants can create own propositions" ON propositions
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR owns_participant(participant_id)
);

-- Update host delete propositions policy to use auth.uid()
DROP POLICY IF EXISTS "Host can delete propositions during proposing" ON propositions;
CREATE POLICY "Host can delete propositions during proposing" ON propositions
FOR DELETE USING (
    -- Service role can always delete
    (current_setting('role', true) = 'service_role')
    OR (
        -- Check that the round is in proposing phase
        EXISTS (
            SELECT 1 FROM rounds r
            WHERE r.id = propositions.round_id
            AND r.phase = 'proposing'
        )
        AND
        -- Check that the requester is the host of this chat
        EXISTS (
            SELECT 1 FROM participants p
            JOIN rounds r ON r.id = propositions.round_id
            JOIN cycles c ON c.id = r.cycle_id
            WHERE p.chat_id = c.chat_id
            AND p.is_host = TRUE
            AND p.user_id = auth.uid()
        )
    )
);

-- =============================================================================
-- STEP 8: Update ratings table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view ratings" ON ratings;
CREATE POLICY "Chat participants can view ratings" ON ratings
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p1
        JOIN participants p2 ON p2.id = ratings.participant_id
        WHERE p1.chat_id = p2.chat_id
        AND p1.user_id = auth.uid()
    ))
);

DROP POLICY IF EXISTS "Participants can submit own ratings" ON ratings;
CREATE POLICY "Participants can submit own ratings" ON ratings
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR (owns_participant(participant_id) AND participant_can_access_proposition(participant_id, proposition_id))
);

DROP POLICY IF EXISTS "Participants can update own ratings" ON ratings;
CREATE POLICY "Participants can update own ratings" ON ratings
FOR UPDATE USING (
    (current_setting('role', true) = 'service_role')
    OR (owns_participant(participant_id) AND participant_can_access_proposition(participant_id, proposition_id))
);

-- =============================================================================
-- STEP 9: Update grid_rankings table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view grid_rankings" ON grid_rankings;
CREATE POLICY "Chat participants can view grid_rankings" ON grid_rankings
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = grid_rankings.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
    ))
);

-- =============================================================================
-- STEP 10: Update invites table policies
-- =============================================================================

DROP POLICY IF EXISTS "Participants or invitees can view invites" ON invites;
CREATE POLICY "Participants or invitees can view invites" ON invites
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = invites.chat_id
        AND p.user_id = auth.uid()
    ))
    OR (invite_token IS NOT NULL)
);

-- =============================================================================
-- STEP 11: Update proposition_ratings table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view proposition_ratings" ON proposition_ratings;
CREATE POLICY "Chat participants can view proposition_ratings" ON proposition_ratings
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        JOIN propositions pr ON pr.id = proposition_ratings.proposition_id
        JOIN rounds r ON r.id = pr.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
    ))
);

-- =============================================================================
-- STEP 12: Update proposition_movda_ratings table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view proposition_movda_ratings" ON proposition_movda_ratings;
CREATE POLICY "Chat participants can view proposition_movda_ratings" ON proposition_movda_ratings
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        JOIN propositions pr ON pr.id = proposition_movda_ratings.proposition_id
        JOIN rounds r ON r.id = pr.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
    ))
);

-- =============================================================================
-- STEP 13: Update proposition_global_scores table policies
-- =============================================================================

DROP POLICY IF EXISTS "Chat participants can view proposition_global_scores" ON proposition_global_scores;
CREATE POLICY "Chat participants can view proposition_global_scores" ON proposition_global_scores
FOR SELECT USING (
    (current_setting('role', true) = 'service_role')
    OR (EXISTS (
        SELECT 1 FROM participants p
        JOIN propositions pr ON pr.id = proposition_global_scores.proposition_id
        JOIN rounds r ON r.id = pr.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
    ))
);

-- =============================================================================
-- STEP 14: Update RPC functions to use p_user_id instead of p_session_token
-- =============================================================================

-- Drop old session-based versions of the functions
DROP FUNCTION IF EXISTS get_public_chats(integer, integer, uuid);
DROP FUNCTION IF EXISTS search_public_chats(text, integer, uuid);

-- Create new user_id-based version of get_public_chats
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
      -- Exclude chats user has already joined (if user_id provided)
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id
    ORDER BY c.last_activity_at DESC NULLS LAST
    LIMIT p_limit
    OFFSET p_offset;
$$;

-- Create new user_id-based version of search_public_chats
CREATE OR REPLACE FUNCTION search_public_chats(
    p_query TEXT,
    p_limit INTEGER DEFAULT 20,
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
      -- Exclude chats user has already joined (if user_id provided)
      AND (p_user_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM participants p2
          WHERE p2.chat_id = c.id
          AND p2.user_id = p_user_id
          AND p2.status = 'active'
      ))
    GROUP BY c.id
    ORDER BY c.last_activity_at DESC NULLS LAST
    LIMIT p_limit;
$$;

-- =============================================================================
-- DONE: All RLS policies and RPC functions now use auth.uid() / user_id
-- which works with both REST API and Realtime WebSocket connections
-- =============================================================================
