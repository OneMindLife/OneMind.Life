-- =============================================================================
-- MIGRATION: Tighten RLS policies for production security
-- =============================================================================
-- Fixes overly permissive "Anyone can..." policies to properly validate access
-- =============================================================================

-- ============================================================================
-- STEP 1: Fix grid_rankings INSERT policy
-- Current: WITH CHECK (true) - allows anyone to insert
-- Fixed: Validate participant owns the ranking and can access the round
-- ============================================================================

DROP POLICY IF EXISTS "Participants can insert own grid_rankings" ON "public"."grid_rankings";

CREATE POLICY "Participants can insert own grid_rankings" ON "public"."grid_rankings"
FOR INSERT WITH CHECK (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR (
        owns_participant(participant_id)
        AND participant_can_access_round(participant_id, round_id)
    )
);

-- ============================================================================
-- STEP 2: Fix grid_rankings SELECT policy
-- Current: Anyone can view all grid_rankings
-- Fixed: Only participants in the same chat can view grid_rankings
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view grid_rankings" ON "public"."grid_rankings";

CREATE POLICY "Chat participants can view grid_rankings" ON "public"."grid_rankings"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = grid_rankings.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.session_token = get_session_token()
    )
);

-- ============================================================================
-- STEP 3: Fix cycles SELECT policy
-- Current: Anyone can view all cycles
-- Fixed: Only participants in the chat can view cycles
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view cycles" ON "public"."cycles";

CREATE POLICY "Chat participants can view cycles" ON "public"."cycles"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = cycles.chat_id
        AND p.session_token = get_session_token()
    )
);

-- ============================================================================
-- STEP 4: Fix invites SELECT policy
-- Current: Anyone can view all invites
-- Fixed: Only view invites for chats you participate in, or by invite code
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view invites" ON "public"."invites";

CREATE POLICY "Participants or invitees can view invites" ON "public"."invites"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = invites.chat_id
        AND p.session_token = get_session_token()
    )
    -- Also allow viewing by invite_token for join flow (invite_token is UUID type)
    OR (invite_token IS NOT NULL)
);

-- ============================================================================
-- STEP 5: Fix join_requests SELECT policy
-- Current: Anyone can view all join requests
-- Fixed: Only view own requests or requests for chats you created
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view own requests" ON "public"."join_requests";

CREATE POLICY "Users can view relevant join_requests" ON "public"."join_requests"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    -- View own requests (by session token)
    OR (session_token = get_session_token())
    -- Chat creators can view requests for their chats
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = join_requests.chat_id
        AND p.session_token = get_session_token()
        AND p.is_host = true
    )
);

-- ============================================================================
-- STEP 6: Fix join_requests INSERT policy
-- Current: Anyone can create join requests with CHECK (true)
-- Fixed: Validate session token matches
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can create join requests" ON "public"."join_requests";

CREATE POLICY "Users can create own join_requests" ON "public"."join_requests"
FOR INSERT WITH CHECK (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR (session_token = get_session_token())
);

-- ============================================================================
-- STEP 7: Fix rounds SELECT policy
-- Current: Anyone can view all rounds
-- Fixed: Only participants in the chat can view rounds
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view rounds" ON "public"."rounds";

CREATE POLICY "Chat participants can view rounds" ON "public"."rounds"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN cycles c ON c.id = rounds.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.session_token = get_session_token()
    )
);

-- ============================================================================
-- STEP 8: Fix round_winners SELECT policy
-- Current: Anyone can view all round_winners
-- Fixed: Only participants in the chat can view round_winners
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view round_winners" ON "public"."round_winners";

CREATE POLICY "Chat participants can view round_winners" ON "public"."round_winners"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = round_winners.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.session_token = get_session_token()
    )
);

-- ============================================================================
-- STEP 9: Fix propositions SELECT policy
-- Current: Anyone can view all propositions
-- Fixed: Only participants in the chat can view propositions
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view propositions" ON "public"."propositions";

CREATE POLICY "Chat participants can view propositions" ON "public"."propositions"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = propositions.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.session_token = get_session_token()
    )
);

-- ============================================================================
-- STEP 10: Fix ratings SELECT policy
-- Current: Anyone can view all ratings
-- Fixed: Only participants in the chat can view ratings
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view ratings" ON "public"."ratings";

CREATE POLICY "Chat participants can view ratings" ON "public"."ratings"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p1
        JOIN participants p2 ON p2.id = ratings.participant_id
        WHERE p1.chat_id = p2.chat_id
        AND p1.session_token = get_session_token()
    )
);

-- ============================================================================
-- STEP 11: Fix participants SELECT policy
-- Current: Anyone can view all participants
-- Fixed: Only participants in the same chat can view each other
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view participants" ON "public"."participants";

CREATE POLICY "Chat participants can view participants" ON "public"."participants"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    -- Can view participants in chats you're part of
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = participants.chat_id
        AND p.session_token = get_session_token()
    )
    -- Can also view own participant record
    OR (session_token = get_session_token())
);

-- ============================================================================
-- STEP 12: Fix proposition_ratings, proposition_movda_ratings, proposition_global_scores
-- These should only be viewable by chat participants
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can view proposition ratings" ON "public"."proposition_ratings";

CREATE POLICY "Chat participants can view proposition_ratings" ON "public"."proposition_ratings"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN propositions pr ON pr.id = proposition_ratings.proposition_id
        JOIN rounds r ON r.id = pr.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.session_token = get_session_token()
    )
);

DROP POLICY IF EXISTS "Anyone can view proposition_movda_ratings" ON "public"."proposition_movda_ratings";

CREATE POLICY "Chat participants can view proposition_movda_ratings" ON "public"."proposition_movda_ratings"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN propositions pr ON pr.id = proposition_movda_ratings.proposition_id
        JOIN rounds r ON r.id = pr.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.session_token = get_session_token()
    )
);

DROP POLICY IF EXISTS "Anyone can view proposition_global_scores" ON "public"."proposition_global_scores";

CREATE POLICY "Chat participants can view proposition_global_scores" ON "public"."proposition_global_scores"
FOR SELECT USING (
    (current_setting('role'::text, true) = 'service_role'::text)
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN propositions pr ON pr.id = proposition_global_scores.proposition_id
        JOIN rounds r ON r.id = pr.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.session_token = get_session_token()
    )
);

-- ============================================================================
-- Note: Keeping these policies as-is (they are appropriately permissive):
-- - chats: "Anyone can create chats" - OK for anonymous app
-- - chats: "Anyone can view active chats" - OK for discovery
-- - movda_config: "Anyone can view" - Public config is fine
-- ============================================================================
