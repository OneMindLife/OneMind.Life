-- =============================================================================
-- MIGRATION: Fix max_phase_duration constraint to cap at 1 day
-- =============================================================================

-- Drop the old constraint
ALTER TABLE "public"."chats"
DROP CONSTRAINT IF EXISTS "max_phase_duration_valid";

-- Add updated constraint: max must be >= min AND <= 86400 (1 day)
ALTER TABLE "public"."chats"
ADD CONSTRAINT "max_phase_duration_valid"
    CHECK ("max_phase_duration_seconds" IS NULL OR ("max_phase_duration_seconds" >= "min_phase_duration_seconds" AND "max_phase_duration_seconds" <= 86400));
