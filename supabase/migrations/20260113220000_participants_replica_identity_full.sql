-- Set REPLICA IDENTITY FULL on participants table
-- This is required for Supabase Realtime to include all columns in DELETE events
-- Without this, DELETE events only include the primary key, so filters on chat_id won't match

ALTER TABLE participants REPLICA IDENTITY FULL;

COMMENT ON TABLE participants IS
'Chat participants. REPLICA IDENTITY FULL is set to enable realtime DELETE event filtering by chat_id.';
