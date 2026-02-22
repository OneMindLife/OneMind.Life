-- =============================================================================
-- Agent Logs Table
-- =============================================================================
-- Generic structured logging table for all agent activity.
-- Designed for easy querying by chat, round, persona, event type, or time range.
-- Flexible JSONB metadata column accepts any additional payload.

CREATE TABLE agent_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Scope columns: nullable so logs can exist at any level
  chat_id BIGINT REFERENCES chats(id) ON DELETE CASCADE,
  cycle_id BIGINT REFERENCES cycles(id) ON DELETE CASCADE,
  round_id BIGINT REFERENCES rounds(id) ON DELETE CASCADE,
  persona_name TEXT,          -- null for dispatcher-level events

  -- Classification
  event_type TEXT NOT NULL,   -- e.g. 'dispatch', 'classify', 'search', 'search_validate',
                              -- 'propose', 'rate', 'task_execute', 'worker_start',
                              -- 'worker_complete', 'error', 'prompt', etc.
  level TEXT NOT NULL DEFAULT 'info'
    CHECK (level IN ('debug', 'info', 'warn', 'error')),
  phase TEXT CHECK (phase IS NULL OR phase IN ('proposing', 'rating')),

  -- Content
  message TEXT NOT NULL,              -- human-readable summary
  duration_ms INTEGER,                -- how long the operation took (nullable)
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb  -- flexible payload
);

-- =============================================================================
-- Indexes — optimized for common query patterns
-- =============================================================================

-- "Show all logs for this chat" (most common query)
CREATE INDEX idx_agent_logs_chat_created
  ON agent_logs (chat_id, created_at DESC)
  WHERE chat_id IS NOT NULL;

-- "Show all logs for this round"
CREATE INDEX idx_agent_logs_round
  ON agent_logs (round_id, created_at DESC)
  WHERE round_id IS NOT NULL;

-- "Show all events of this type" (e.g. all classifications, all errors)
CREATE INDEX idx_agent_logs_event_type
  ON agent_logs (event_type, created_at DESC);

-- "Show what this persona did"
CREATE INDEX idx_agent_logs_persona
  ON agent_logs (persona_name, created_at DESC)
  WHERE persona_name IS NOT NULL;

-- "Show all errors" — filtered partial index for fast error queries
CREATE INDEX idx_agent_logs_errors
  ON agent_logs (created_at DESC)
  WHERE level = 'error';

-- Time-range scans (cleanup, recent logs)
CREATE INDEX idx_agent_logs_created
  ON agent_logs (created_at DESC);

-- JSONB payload — GIN index for @> containment queries
-- e.g. WHERE metadata @> '{"classification": "RESEARCH_TASK"}'
CREATE INDEX idx_agent_logs_metadata
  ON agent_logs USING GIN (metadata);

-- =============================================================================
-- RLS — service role only (agents write via edge functions)
-- =============================================================================

ALTER TABLE agent_logs ENABLE ROW LEVEL SECURITY;

-- No policies = only service_role can read/write (bypasses RLS)
-- This prevents anon/authenticated users from accessing agent internals

-- =============================================================================
-- Cleanup function — retain 30 days of logs by default
-- =============================================================================

CREATE OR REPLACE FUNCTION cleanup_agent_logs(retention_days INTEGER DEFAULT 30)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM agent_logs
  WHERE created_at < NOW() - (retention_days || ' days')::INTERVAL;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;

  IF deleted_count > 0 THEN
    RAISE NOTICE '[AGENT-LOGS] Cleaned up % logs older than % days', deleted_count, retention_days;
  END IF;

  RETURN deleted_count;
END;
$$;

-- Restrict cleanup function to service role
REVOKE EXECUTE ON FUNCTION cleanup_agent_logs FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE agent_logs IS
  'Structured log table for all agent orchestrator activity. '
  'Query by chat_id, round_id, persona_name, event_type, or level. '
  'JSONB metadata column accepts arbitrary payloads. '
  'Service-role access only (RLS enabled, no policies).';

COMMENT ON FUNCTION cleanup_agent_logs IS
  'Deletes agent_logs older than retention_days (default 30). '
  'Called manually or via cron. Returns count of deleted rows.';

-- =============================================================================
-- Cron job for automatic cleanup (weekly, keep 30 days)
-- =============================================================================

DO $$
BEGIN
  PERFORM cron.schedule(
    'cleanup-agent-logs',
    '0 3 * * 0',  -- Every Sunday at 3 AM UTC
    'SELECT cleanup_agent_logs(30)'
  );
EXCEPTION WHEN undefined_function OR invalid_schema_name THEN
  RAISE NOTICE 'pg_cron not available, skipping cleanup-agent-logs cron job';
END;
$$;
