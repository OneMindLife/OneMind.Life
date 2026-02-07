-- =============================================================================
-- SECURITY FIX: Remove vulnerable "Service role" RLS policies
-- =============================================================================
-- These 14 policies use USING(true) with no role restriction, meaning ANY user
-- (including anon) can perform the operations. Service role bypasses RLS entirely,
-- so these policies are dead code for service_role but wide-open doors for everyone.
--
-- Fix: DROP all 14, then add properly scoped policies for tables where the
-- Flutter client performs direct writes (chats, cycles, rounds, round_winners,
-- participants, join_requests). Tables only written by edge functions/triggers
-- get no replacement — they're locked to service_role only.
-- =============================================================================

-- =============================================================================
-- PART 1: DROP all 14 vulnerable "Service role can ..." policies
-- =============================================================================

DROP POLICY IF EXISTS "Service role can update chats" ON public.chats;
DROP POLICY IF EXISTS "Service role can manage cycles" ON public.cycles;
DROP POLICY IF EXISTS "Service role can manage rounds" ON public.rounds;
DROP POLICY IF EXISTS "Service role can manage round_winners" ON public.round_winners;
DROP POLICY IF EXISTS "Service role can update participants" ON public.participants;
DROP POLICY IF EXISTS "Service role can update join requests" ON public.join_requests;
DROP POLICY IF EXISTS "Service role can manage invites" ON public.invites;
DROP POLICY IF EXISTS "Service role can manage grid_rankings" ON public.grid_rankings;
DROP POLICY IF EXISTS "Service role can manage movda_config" ON public.movda_config;
DROP POLICY IF EXISTS "Service role can manage proposition_movda_ratings" ON public.proposition_movda_ratings;
DROP POLICY IF EXISTS "Service role can manage proposition_global_scores" ON public.proposition_global_scores;
DROP POLICY IF EXISTS "Service role can manage user_voting_ranks" ON public.user_voting_ranks;
DROP POLICY IF EXISTS "Service role can manage user_proposing_ranks" ON public.user_proposing_ranks;
DROP POLICY IF EXISTS "Service role can manage user_round_ranks" ON public.user_round_ranks;

-- =============================================================================
-- PART 2: Add scoped replacement policies for Flutter client writes
-- =============================================================================

-- -----------------------------------------------------------------------------
-- chats: Host can UPDATE own chat (e.g. last_activity_at)
-- Flutter: chat_service.dart:615
-- -----------------------------------------------------------------------------
CREATE POLICY "Host can update own chat" ON public.chats
FOR UPDATE USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = chats.id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- -----------------------------------------------------------------------------
-- cycles: Host can INSERT cycles in own chat
-- Flutter: chat_service.dart:580
-- -----------------------------------------------------------------------------
CREATE POLICY "Host can create cycles in own chat" ON public.cycles
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = cycles.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- -----------------------------------------------------------------------------
-- rounds: Host can INSERT rounds in own chat
-- Flutter: chat_service.dart:609
-- -----------------------------------------------------------------------------
CREATE POLICY "Host can create rounds in own chat" ON public.rounds
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN cycles c ON c.id = rounds.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- -----------------------------------------------------------------------------
-- rounds: Host can UPDATE rounds in own chat
-- Flutter: chat_service.dart:571,732,769
-- -----------------------------------------------------------------------------
CREATE POLICY "Host can update rounds in own chat" ON public.rounds
FOR UPDATE USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN cycles c ON c.id = rounds.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- -----------------------------------------------------------------------------
-- round_winners: Host can INSERT/UPDATE round_winners in own chat
-- Flutter: chat_service.dart:716 (upsert)
-- -----------------------------------------------------------------------------
CREATE POLICY "Host can manage round_winners in own chat" ON public.round_winners
FOR INSERT WITH CHECK (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = round_winners.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

CREATE POLICY "Host can update round_winners in own chat" ON public.round_winners
FOR UPDATE USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM participants p
        JOIN rounds r ON r.id = round_winners.round_id
        JOIN cycles c ON c.id = r.cycle_id
        WHERE p.chat_id = c.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- -----------------------------------------------------------------------------
-- participants: Host can UPDATE others (kick); user can UPDATE own record
-- Flutter: participant_service.dart:67 (reactivate own), :142 (host kick)
-- -----------------------------------------------------------------------------
CREATE POLICY "Host or self can update participants" ON public.participants
FOR UPDATE USING (
    (current_setting('role', true) = 'service_role')
    -- User can update own participant record (e.g. reactivation)
    OR (user_id = auth.uid())
    -- Host can update participants in their chat (e.g. kick)
    OR EXISTS (
        SELECT 1 FROM participants host_p
        WHERE host_p.chat_id = participants.chat_id
        AND host_p.user_id = auth.uid()
        AND host_p.is_host = true
        AND host_p.status = 'active'
    )
);

-- -----------------------------------------------------------------------------
-- join_requests: Host can UPDATE requests for own chat (deny)
-- Flutter: participant_service.dart:134
-- -----------------------------------------------------------------------------
CREATE POLICY "Host can update join requests for own chat" ON public.join_requests
FOR UPDATE USING (
    (current_setting('role', true) = 'service_role')
    OR EXISTS (
        SELECT 1 FROM participants p
        WHERE p.chat_id = join_requests.chat_id
        AND p.user_id = auth.uid()
        AND p.is_host = true
        AND p.status = 'active'
    )
);

-- =============================================================================
-- PART 3: No replacement needed for these 8 tables (service-role only writes)
-- =============================================================================
-- invites              - managed by edge functions
-- grid_rankings        - already has user-facing INSERT/UPDATE from
--                        20260110210000_tighten_rls_policies.sql
-- movda_config         - managed by edge functions/triggers
-- proposition_movda_ratings   - managed by calculate_movda_scores_for_round()
-- proposition_global_scores   - managed by calculate_movda_scores_for_round()
-- user_voting_ranks    - managed by triggers
-- user_proposing_ranks - managed by triggers
-- user_round_ranks     - managed by triggers
-- =============================================================================
