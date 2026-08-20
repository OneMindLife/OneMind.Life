-- Telegram identity bridge for the @OneMindGameBot flow.
--
-- Telegram users have no Supabase auth.uid(); the telegram-bot edge function
-- (service role) creates and acts for them entirely server-side, keyed by these
-- IDs. A Telegram group (or 1:1 chat) binds to exactly one OneMind chat; each
-- Telegram user maps to one participant within that chat.
--
-- Purely additive: both columns are nullable and untouched for web/auth chats.
-- (Applied to prod 2026-07-11 via execute_sql; DDL is idempotent so re-running
-- through db push is safe.)

ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS telegram_chat_id BIGINT;

CREATE UNIQUE INDEX IF NOT EXISTS chats_telegram_chat_id_key
  ON public.chats(telegram_chat_id)
  WHERE telegram_chat_id IS NOT NULL;

COMMENT ON COLUMN public.chats.telegram_chat_id IS
'Telegram chat/group id this OneMind chat is bound to (bot flow). NULL for non-Telegram chats. Unique when set.';

ALTER TABLE public.participants
  ADD COLUMN IF NOT EXISTS telegram_user_id BIGINT;

CREATE INDEX IF NOT EXISTS participants_chat_telegram_user_idx
  ON public.participants(chat_id, telegram_user_id)
  WHERE telegram_user_id IS NOT NULL;

COMMENT ON COLUMN public.participants.telegram_user_id IS
'Telegram user id for participants who joined via @OneMindGameBot. NULL for web/auth participants. Managed server-side by the telegram-bot edge fn (service role).';
