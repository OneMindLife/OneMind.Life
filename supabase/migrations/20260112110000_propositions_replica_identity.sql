-- Enable REPLICA IDENTITY FULL for propositions table
-- This is required for Supabase Realtime to include all columns in DELETE events
-- Without this, filtered subscriptions (e.g., by round_id) won't receive delete events

ALTER TABLE propositions REPLICA IDENTITY FULL;
