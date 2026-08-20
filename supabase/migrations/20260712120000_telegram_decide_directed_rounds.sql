-- /decide directed rounds (Telegram): a round can carry its own question.
--
-- Ambient rounds (the always-running open floor) have question = NULL and the
-- bot renders the open-floor prompt. When a group member sends
-- /decide <question>, the bot binds the question to the current proposing
-- round (rounds.question), the group answers THAT, and when the winner posts
-- the next auto-created round is born with question = NULL — ambient resumes.
--
-- The column is read through the telegram-bot edge fn only (roundInfo prefers
-- rounds.question over chats.initial_message); nothing else consumes it.

ALTER TABLE public.rounds ADD COLUMN IF NOT EXISTS question TEXT;

COMMENT ON COLUMN public.rounds.question IS
  'Per-round directed question (Telegram /decide). NULL = ambient open floor / chat-level initial_message applies.';
