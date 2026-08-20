-- Waitlist for pre-launch demand tests (journaling product, others later).
-- Anon can INSERT (join); nobody can SELECT via the API (email privacy) —
-- counts are read with the service role / MCP.
CREATE TABLE public.waitlist (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email      TEXT NOT NULL CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    product    TEXT NOT NULL DEFAULT 'journal',
    source     TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (email, product)
);

ALTER TABLE public.waitlist ENABLE ROW LEVEL SECURITY;

-- Anon/authenticated may join; no SELECT/UPDATE/DELETE policy = API cannot read
-- or mutate existing rows (service role bypasses RLS for counting).
CREATE POLICY "join waitlist" ON public.waitlist
    FOR INSERT TO anon, authenticated
    WITH CHECK (true);

COMMENT ON TABLE public.waitlist IS
    'Pre-launch email capture for demand smoke-tests (per-product). INSERT-only via API; read with service role.';
