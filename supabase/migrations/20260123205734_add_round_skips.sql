-- =============================================================================
-- MIGRATION: Add round_skips table for Skip Proposing Feature
-- =============================================================================
-- Allows users to skip submitting a proposition during the proposing phase.
-- Skippers count toward participation for early advance calculations.
--
-- Key constraints:
-- - Only one skip per participant per round (unique constraint)
-- - Skip quota: current_skips < total_participants - proposing_minimum
-- - Once submitted, cannot skip (enforce in application layer)
-- =============================================================================

-- Table to track users who skip proposing
CREATE TABLE "public"."round_skips" (
    "id" BIGSERIAL PRIMARY KEY,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "participant_id" BIGINT NOT NULL REFERENCES "public"."participants"("id") ON DELETE CASCADE,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT "unique_round_participant_skip" UNIQUE ("round_id", "participant_id")
);

-- Index for faster lookups by round
CREATE INDEX "idx_round_skips_round_id" ON "public"."round_skips"("round_id");

-- Enable Row Level Security
ALTER TABLE "public"."round_skips" ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can skip in rounds they participate in
-- Validates:
-- 1. User is a participant (via participant_id -> user_id check)
-- 2. Round is in proposing phase
-- 3. User hasn't already submitted a proposition
-- 4. Skip quota not exceeded
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
            WHERE round_id = round_skips.round_id
            AND participant_id = round_skips.participant_id
            AND carried_from_id IS NULL  -- Only check new submissions, not carried forward
        )
        -- Verify skip quota not exceeded (skips < participants - proposing_minimum)
        AND (
            SELECT COUNT(*) FROM round_skips rs WHERE rs.round_id = round_skips.round_id
        ) < (
            SELECT COUNT(*) FROM participants p
            JOIN cycles c ON p.chat_id = c.chat_id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_skips.round_id AND p.status = 'active'
        ) - (
            SELECT ch.proposing_minimum FROM chats ch
            JOIN cycles c ON c.chat_id = ch.id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_skips.round_id
        )
    );

-- RLS Policy: Users can read skips in rounds of chats they participate in
CREATE POLICY "Users can read skips in their chats" ON "public"."round_skips"
    FOR SELECT USING (
        round_id IN (
            SELECT r.id FROM rounds r
            JOIN cycles c ON r.cycle_id = c.id
            JOIN participants p ON c.chat_id = p.chat_id
            WHERE p.user_id = auth.uid()
        )
    );

-- Enable realtime for round_skips table
ALTER PUBLICATION supabase_realtime ADD TABLE "public"."round_skips";

-- Set replica identity to FULL for realtime subscriptions
ALTER TABLE "public"."round_skips" REPLICA IDENTITY FULL;

COMMENT ON TABLE "public"."round_skips" IS
'Tracks participants who skip submitting a proposition during the proposing phase.
Skippers count toward participation for early advance threshold calculations.
Skip quota: total_skips < total_participants - proposing_minimum';

COMMENT ON COLUMN "public"."round_skips"."round_id" IS 'The round being skipped';
COMMENT ON COLUMN "public"."round_skips"."participant_id" IS 'The participant who is skipping';
