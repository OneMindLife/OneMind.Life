-- =============================================================================
-- MIGRATION: perf_logs — unified observability for Flutter + DB function timings
-- =============================================================================
-- A single dedicated table to correlate frontend and backend events from the
-- same user action. Each row is one event (start / end / error); rows from
-- the same logical action share a correlation_id, so the full timeline (e.g.
-- "user clicked Resume" → "RPC body ran" → "trigger cascade ran" → "Flutter
-- got response" → "Flutter rendered new state") can be reconstructed by
-- sorting on created_at.
--
-- Uses:
--   - Diagnose multi-second waits by seeing where time is actually spent.
--   - Compare timings across many devices in the same chat.
--   - Match Flutter-perceived latency vs DB function execution time.
--
-- Goes hand-in-hand with pg_stat_statements (enabled below). perf_logs is
-- "your code's view"; pg_stat_statements is "Postgres's per-query view".
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TABLE IF NOT EXISTS public.perf_logs (
    id              BIGSERIAL PRIMARY KEY,
    correlation_id  UUID,
    source          TEXT NOT NULL CHECK (source IN ('flutter', 'db_func', 'edge_function')),
    action          TEXT NOT NULL,
    phase           TEXT CHECK (phase IN ('start', 'end', 'error')),
    duration_ms     INTEGER,
    chat_id         BIGINT,
    round_id        BIGINT,
    user_id         UUID,
    device_id       TEXT,
    payload         JSONB,
    error           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_perf_logs_correlation_id ON public.perf_logs (correlation_id);
CREATE INDEX IF NOT EXISTS idx_perf_logs_chat_id        ON public.perf_logs (chat_id);
CREATE INDEX IF NOT EXISTS idx_perf_logs_created_at     ON public.perf_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_perf_logs_action_phase   ON public.perf_logs (action, phase);

ALTER TABLE public.perf_logs OWNER TO postgres;

-- RLS: anyone authenticated can insert their own rows; reads gated to
-- service_role / postgres for now (we'll query through the dashboard).
ALTER TABLE public.perf_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "perf_logs_insert_authenticated"
    ON public.perf_logs FOR INSERT
    TO authenticated, anon
    WITH CHECK (true);

CREATE POLICY "perf_logs_read_service"
    ON public.perf_logs FOR SELECT
    USING (current_setting('role', true) = 'service_role');

GRANT INSERT ON public.perf_logs TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE public.perf_logs_id_seq TO authenticated, anon;

-- =============================================================================
-- log_perf RPC: uniform write path for DB functions + Flutter helper
-- =============================================================================
-- Both DB triggers/functions and the Flutter PerfLogger call this. Single
-- INSERT, no return value, fast — designed to be safe to call from anywhere
-- including hot trigger paths. Failures don't propagate (we don't want the
-- logging to break the actual operation).
CREATE OR REPLACE FUNCTION public.log_perf(
    p_correlation_id UUID,
    p_source         TEXT,
    p_action         TEXT,
    p_phase          TEXT DEFAULT NULL,
    p_duration_ms    INTEGER DEFAULT NULL,
    p_chat_id        BIGINT DEFAULT NULL,
    p_round_id       BIGINT DEFAULT NULL,
    p_user_id        UUID DEFAULT NULL,
    p_device_id      TEXT DEFAULT NULL,
    p_payload        JSONB DEFAULT NULL,
    p_error          TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.perf_logs (
        correlation_id, source, action, phase, duration_ms,
        chat_id, round_id, user_id, device_id, payload, error
    ) VALUES (
        p_correlation_id, p_source, p_action, p_phase, p_duration_ms,
        p_chat_id, p_round_id, COALESCE(p_user_id, auth.uid()), p_device_id, p_payload, p_error
    );
EXCEPTION WHEN OTHERS THEN
    -- Never let logging failure break the calling operation.
    NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_perf(UUID, TEXT, TEXT, TEXT, INTEGER, BIGINT, BIGINT, UUID, TEXT, JSONB, TEXT)
    TO authenticated, anon;

COMMENT ON TABLE public.perf_logs IS
'Unified observability table — every row is one event (start/end/error) from Flutter or a DB function. Same correlation_id ties events from the same logical user action across all sources. Query by correlation_id to reconstruct timelines, or by chat_id + created_at to see what happened in a chat over a window.';

COMMENT ON FUNCTION public.log_perf IS
'Uniform write path for perf_logs. Safe from any context — failures are swallowed so logging never breaks the actual operation. Pairs with the Flutter PerfLogger helper which calls this RPC.';
