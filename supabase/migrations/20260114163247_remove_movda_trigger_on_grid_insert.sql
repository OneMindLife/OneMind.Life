-- =============================================================================
-- Migration: Remove MOVDA trigger on grid_rankings insert
-- =============================================================================
--
-- REASON: The trigger fires on every grid_rankings INSERT, causing:
-- 1. Redundant MOVDA calculations during active rating phase
-- 2. Performance issues and potential timeouts with many participants
--
-- MOVDA should only run ONCE when rating phase ends. This already happens in:
-- - process-timers edge function: calculateWinnerAndComplete() calls
--   calculate_movda_scores_for_round() when rating timer expires
-- - ChatService.completeRatingPhase() calls the same function when host
--   manually ends rating
--
-- This migration removes the redundant trigger.
-- =============================================================================

-- Drop the trigger (safe - it may not exist in all environments)
DROP TRIGGER IF EXISTS "trg_recalculate_movda_on_grid_insert" ON "public"."grid_rankings";

-- Optionally drop the trigger function (keep it for now in case we need it)
-- The function is harmless without the trigger
-- DROP FUNCTION IF EXISTS "public"."recalculate_movda_on_grid_insert"();
