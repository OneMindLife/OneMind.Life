-- =============================================================================
-- TEST: Host Force Consensus
-- =============================================================================
-- Tests for the host_force_consensus() function and host_override column.
-- Uses function source introspection (pg_proc.prosrc) since pgTAP tests
-- cannot set auth.uid() for SECURITY DEFINER functions.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;

SELECT plan(13);

-- =============================================================================
-- 1. Column existence: host_override on cycles
-- =============================================================================

SELECT has_column(
  'public',
  'cycles',
  'host_override',
  'cycles table has host_override column'
);

SELECT col_type_is(
  'public',
  'cycles',
  'host_override',
  'boolean',
  'host_override column is boolean'
);

SELECT col_default_is(
  'public',
  'cycles',
  'host_override',
  'false',
  'host_override defaults to FALSE'
);

-- =============================================================================
-- 2. Function existence
-- =============================================================================

SELECT has_function(
  'public',
  'host_force_consensus',
  ARRAY['bigint', 'text', 'text'],
  'host_force_consensus(bigint, text, text) function exists'
);

-- =============================================================================
-- 3. Source introspection — contains host verification
-- =============================================================================

SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus') LIKE '%is_host%',
  'host_force_consensus source contains host verification (is_host)'
);

SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus') LIKE '%Only the host can force a consensus%',
  'host_force_consensus source contains host-only error message'
);

-- =============================================================================
-- 4. Source introspection — creates proposition and sets cycle winner
-- =============================================================================

SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus') LIKE '%INSERT INTO propositions%',
  'host_force_consensus source creates a proposition'
);

SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus') LIKE '%winning_proposition_id%',
  'host_force_consensus source sets winning_proposition_id on cycle'
);

SELECT ok(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus') LIKE '%host_override = TRUE%',
  'host_force_consensus source sets host_override = TRUE'
);

-- =============================================================================
-- 5. Security — function is SECURITY DEFINER
-- =============================================================================

SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'host_force_consensus'),
  true,
  'host_force_consensus is SECURITY DEFINER'
);

-- =============================================================================
-- 6. Source introspection — marks all rounds completed
-- =============================================================================

-- 11. host_force_consensus marks rounds as completed
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'UPDATE rounds',
  'host_force_consensus marks rounds as completed before completing cycle'
);

-- 12. Rounds completion targets only the current cycle's incomplete rounds
SELECT matches(
  (SELECT prosrc FROM pg_proc WHERE proname = 'host_force_consensus' LIMIT 1),
  'v_current_cycle_id AND completed_at IS NULL',
  'host_force_consensus only completes rounds in the current cycle that are still open'
);

-- 13. Rounds are completed BEFORE the cycle (order matters for timer queries)
SELECT ok(
  (SELECT
    position('UPDATE rounds' in prosrc) < position('UPDATE cycles' in prosrc)
   FROM pg_proc WHERE proname = 'host_force_consensus'),
  'host_force_consensus completes rounds BEFORE completing the cycle'
);

-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
