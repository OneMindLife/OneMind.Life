-- Verifies the Moltbook agent run-lease concurrency guard
-- (migration 20260529180000_moltbook_agent_run_lease.sql).
--
-- The lease is a row-based mutex so only one moltbook-agent invocation runs at
-- a time; overlapping crons otherwise contend on moltbook_agent_state id=1 and
-- the loser hangs in persist_state until the 110s handler deadline.
--
-- All changes here target the singleton state row (id=1) but run inside a
-- BEGIN/ROLLBACK, so prod data is untouched.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(7);

-- Ensure the singleton row exists and starts with no lease held.
INSERT INTO moltbook_agent_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
UPDATE moltbook_agent_state
SET context = COALESCE(context, '{}'::jsonb) - 'run_lease_until'
WHERE id = 1;

-- 1. First claim on a free lease succeeds.
SELECT is(
  claim_moltbook_agent_run(115),
  true,
  'claim succeeds when no lease is held'
);

-- 2. The claim actually wrote a future expiry into the row.
SELECT ok(
  (SELECT (context->>'run_lease_until')::timestamptz FROM moltbook_agent_state WHERE id = 1) > now(),
  'claim sets run_lease_until to a future timestamp'
);

-- 3. A second concurrent claim fails while the lease is held.
SELECT is(
  claim_moltbook_agent_run(115),
  false,
  'claim fails while a valid lease is held (mutual exclusion)'
);

-- 4. Releasing clears the lease.
SELECT release_moltbook_agent_run();
SELECT is(
  (SELECT context ? 'run_lease_until' FROM moltbook_agent_state WHERE id = 1),
  false,
  'release clears run_lease_until'
);

-- 5. After release, a fresh claim succeeds again.
SELECT is(
  claim_moltbook_agent_run(115),
  true,
  'claim succeeds again after release'
);

-- 6. An expired lease is reclaimable: backdate the expiry into the past.
UPDATE moltbook_agent_state
SET context = jsonb_set(context, '{run_lease_until}', to_jsonb((now() - interval '1 second')::text))
WHERE id = 1;
SELECT is(
  claim_moltbook_agent_run(115),
  true,
  'claim succeeds when the existing lease has expired'
);

-- 7. anon must not be able to drive the lease.
SELECT is(
  has_function_privilege('anon', 'public.claim_moltbook_agent_run(integer)', 'EXECUTE'),
  false,
  'anon lacks EXECUTE on claim_moltbook_agent_run'
);

SELECT * FROM finish();
ROLLBACK;
