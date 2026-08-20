-- Per-Telegram-user transient DM step for @OneMindGameBot: tracks what a user is
-- doing in their 1:1 chat with the bot (submitting a take / voting) and for which
-- round, so their next DM message/tap is interpreted correctly. Written+read only
-- by the telegram-bot edge fn (service role). RLS on, no policies = locked down.
-- (Applied to prod 2026-07-11 via execute_sql; idempotent.)
CREATE TABLE IF NOT EXISTS public.telegram_dm_state (
  telegram_user_id BIGINT PRIMARY KEY,
  action  TEXT   NOT NULL,
  round_id BIGINT,
  chat_id  BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.telegram_dm_state ENABLE ROW LEVEL SECURITY;
