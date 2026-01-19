-- Fix grid_rankings foreign key to cascade on participant delete
--
-- Problem: grid_rankings has participant_id with ON DELETE SET NULL
-- but also has a check constraint requiring participant_id OR session_token to be NOT NULL.
-- When a chat is deleted, participants are cascade deleted, which sets grid_rankings.participant_id
-- to NULL, violating the check constraint.
--
-- Solution: Change ON DELETE SET NULL to ON DELETE CASCADE for participant_id

-- First, drop the existing foreign key constraint
ALTER TABLE "public"."grid_rankings"
    DROP CONSTRAINT IF EXISTS "grid_rankings_participant_id_fkey";

-- Re-add with ON DELETE CASCADE
ALTER TABLE "public"."grid_rankings"
    ADD CONSTRAINT "grid_rankings_participant_id_fkey"
    FOREIGN KEY ("participant_id")
    REFERENCES "public"."participants"("id")
    ON DELETE CASCADE;

-- Also check if there are any orphaned grid_rankings with NULL participant_id
-- and delete them (shouldn't happen with new constraint but clean up any existing)
DELETE FROM "public"."grid_rankings"
WHERE "participant_id" IS NULL AND "session_token" IS NULL;

COMMENT ON TABLE "public"."grid_rankings" IS
'Grid rankings for propositions. Cascade deletes when participant is deleted.';
