-- Per-chat LLM backend selection. The agent-orchestrator edge function reads
-- this column to decide which API to call — `claude-*` routes to Claude,
-- anything else routes to DeepSeek (OpenAI-compatible).
--
-- Default stays 'deepseek-chat' so new chats don't accidentally hit the
-- Anthropic API. OneMind (chat 246) is the only chat currently flipped to
-- Claude; the migration updates it directly to avoid a manual follow-up.

ALTER TABLE public.chats
ADD COLUMN IF NOT EXISTS agent_model TEXT NOT NULL DEFAULT 'deepseek-chat';

UPDATE public.chats SET agent_model = 'claude-opus-4-7' WHERE id = 246;
