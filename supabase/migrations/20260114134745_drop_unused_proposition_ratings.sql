-- =============================================================================
-- MIGRATION: Drop Unused proposition_ratings Table
-- =============================================================================
-- The proposition_ratings table was created in the initial schema but never
-- populated in production. MOVDA scores are stored in proposition_movda_ratings.
--
-- This table caused Bug #17: Flutter code was querying this empty table instead
-- of proposition_movda_ratings, resulting in null ratings in the results view.
-- =============================================================================

-- Drop RLS policies first
DROP POLICY IF EXISTS "Anyone can view proposition ratings" ON "public"."proposition_ratings";
DROP POLICY IF EXISTS "Service role can manage proposition ratings" ON "public"."proposition_ratings";
DROP POLICY IF EXISTS "Chat participants can view proposition_ratings" ON "public"."proposition_ratings";

-- Drop the table (CASCADE handles the foreign key constraint)
DROP TABLE IF EXISTS "public"."proposition_ratings" CASCADE;

-- Drop the sequence if it still exists
DROP SEQUENCE IF EXISTS "public"."proposition_ratings_id_seq";
