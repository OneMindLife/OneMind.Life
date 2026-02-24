-- Drop stale function overloads created by earlier migrations.
-- CREATE OR REPLACE with different parameter counts creates NEW overloads
-- instead of replacing. These old signatures are no longer called by the app.

-- get_public_chats: old 2-param version (no user_id filter)
DROP FUNCTION IF EXISTS get_public_chats(integer, integer);

-- search_public_chats: old 2-param version (no offset, no user_id)
DROP FUNCTION IF EXISTS search_public_chats(text, integer);

-- search_public_chats: old 3-param version (no offset)
DROP FUNCTION IF EXISTS search_public_chats(text, integer, uuid);
