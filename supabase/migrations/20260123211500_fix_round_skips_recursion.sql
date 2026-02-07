-- =============================================================================
-- FIX: Infinite recursion in round_skips RLS policy
-- =============================================================================
-- The INSERT policy was querying round_skips from within itself, causing
-- infinite recursion. Fix by using a SECURITY DEFINER function to bypass RLS.
-- =============================================================================

-- Helper function to count skips for a round (bypasses RLS)
CREATE OR REPLACE FUNCTION public.count_round_skips(p_round_id BIGINT)
RETURNS INTEGER
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
    SELECT COUNT(*)::INTEGER FROM public.round_skips WHERE round_id = p_round_id;
$$;

-- Drop the problematic policy
DROP POLICY IF EXISTS "Users can skip in rounds they participate in" ON "public"."round_skips";

-- Recreate the policy using the helper function
CREATE POLICY "Users can skip in rounds they participate in" ON "public"."round_skips"
    FOR INSERT WITH CHECK (
        -- Verify participant belongs to current user
        participant_id IN (
            SELECT id FROM participants WHERE user_id = auth.uid()
        )
        -- Verify round is in proposing phase
        AND EXISTS (
            SELECT 1 FROM rounds WHERE id = round_id AND phase = 'proposing'
        )
        -- Verify user hasn't already submitted a proposition
        AND NOT EXISTS (
            SELECT 1 FROM propositions
            WHERE propositions.round_id = round_skips.round_id
            AND propositions.participant_id = round_skips.participant_id
            AND propositions.carried_from_id IS NULL  -- Only check new submissions
        )
        -- Verify skip quota not exceeded (skips < participants - proposing_minimum)
        -- Uses helper function to avoid infinite recursion
        AND count_round_skips(round_id) < (
            SELECT COUNT(*)::INTEGER FROM participants p
            JOIN cycles c ON p.chat_id = c.chat_id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_skips.round_id AND p.status = 'active'
        ) - COALESCE((
            SELECT ch.proposing_minimum FROM chats ch
            JOIN cycles c ON c.chat_id = ch.id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_skips.round_id
        ), 1)
    );

COMMENT ON FUNCTION public.count_round_skips IS
'Helper function to count skips for a round. Uses SECURITY DEFINER to bypass RLS and avoid infinite recursion in the round_skips INSERT policy.';
