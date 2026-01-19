-- =============================================================================
-- Migration: Enable Realtime for Join Requests
-- =============================================================================
-- Enables Supabase Realtime for the join_requests table so that:
-- 1. Hosts see new join requests immediately (badge updates in realtime)
-- 2. Requesters see status changes immediately (approved/denied)
-- =============================================================================

-- Add join_requests to the realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE join_requests;

-- Set replica identity to FULL for proper update tracking
-- This ensures that UPDATE events include all column values, not just changed ones
ALTER TABLE join_requests REPLICA IDENTITY FULL;
