-- Add host_display_name column to chats table
-- This stores the host's display name for display to joining users

ALTER TABLE chats
ADD COLUMN host_display_name TEXT;

COMMENT ON COLUMN chats.host_display_name IS
'Display name of the chat host, shown to users when joining. Required field enforced at application level.';
