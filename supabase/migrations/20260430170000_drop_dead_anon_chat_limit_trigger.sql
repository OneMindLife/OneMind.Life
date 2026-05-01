-- Drop the `on_chat_check_limit` trigger and its function. The trigger
-- was added in 20260109215906_remote_schema.sql to cap anonymous users
-- at 10 active chats per `creator_session_token`. It checks:
--
--     IF NEW.creator_session_token IS NOT NULL AND NEW.creator_id IS NULL
--
-- That condition has been impossible to satisfy since Supabase
-- Anonymous Auth was adopted in 20260113230000. Every user now has a
-- real `auth.uid()` whether anonymous or not, and `chat_service.dart`
-- always populates `creator_id` from `auth.currentUser.id`. The
-- `creator_session_token` field is no longer set by the client at all.
--
-- So the trigger never fires. It's dead code that pretends to be a
-- rate limit. Removing it makes the actual policy explicit: there is
-- no per-user cap on chat creation today.
--
-- If we ever want to re-introduce a cap, the right gate is
-- `auth.users.is_anonymous = true` keyed by `auth.uid()`, not the
-- legacy session-token column.

DROP TRIGGER IF EXISTS trg_chat_check_limit ON public.chats;
DROP FUNCTION IF EXISTS public.on_chat_check_limit();
