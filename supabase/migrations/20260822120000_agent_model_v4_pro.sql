-- In-chat agents: default to DeepSeek V4 Pro instead of the legacy
-- `deepseek-chat` alias. V4 ships explicit versioned model names
-- (`deepseek-v4-flash` / `deepseek-v4-pro`); `deepseek-chat` no longer tracks
-- the latest. chat 246 stays pinned to Claude (excluded by the WHERE below).
ALTER TABLE public.chats
ALTER COLUMN agent_model SET DEFAULT 'deepseek-v4-pro';

UPDATE public.chats
SET agent_model = 'deepseek-v4-pro'
WHERE agent_model = 'deepseek-chat';
