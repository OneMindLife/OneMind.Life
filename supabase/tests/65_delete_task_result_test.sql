-- =============================================================================
-- TEST: delete_task_result and delete_consensus task_result fix
-- =============================================================================
-- Verifies:
-- 1. delete_task_result function exists
-- 2. delete_consensus now clears task_result
-- 3. delete_consensus enforces latest-only deletion
-- 4. delete_task_result enforces latest-only deletion
-- 5. Both functions verify host permissions
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;

SELECT plan(8);

-- =============================================================================
-- 1. Function existence
-- =============================================================================

SELECT has_function(
  'public',
  'delete_task_result',
  ARRAY['bigint'],
  'delete_task_result(bigint) function exists'
);

-- =============================================================================
-- 2. Source introspection — delete_consensus clears task_result
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus')::text,
  '%task_result = NULL%'::text,
  'delete_consensus source clears task_result'
);

-- =============================================================================
-- 3. Source introspection — delete_consensus enforces latest-only
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus')::text,
  '%Only the latest consensus can be deleted%'::text,
  'delete_consensus enforces latest-only deletion'
);

-- =============================================================================
-- 4. Source introspection — delete_task_result verifies host
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_task_result')::text,
  '%is_host%'::text,
  'delete_task_result source contains host verification'
);

-- =============================================================================
-- 5. Source introspection — delete_task_result enforces latest-only
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_task_result')::text,
  '%Only the latest consensus research results can be deleted%'::text,
  'delete_task_result enforces latest-only deletion'
);

-- =============================================================================
-- 6. Source introspection — delete_task_result clears task_result
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_task_result')::text,
  '%task_result = NULL%'::text,
  'delete_task_result source clears task_result'
);

-- =============================================================================
-- 7. delete_task_result is SECURITY DEFINER
-- =============================================================================

SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'delete_task_result'),
  true,
  'delete_task_result is SECURITY DEFINER'
);

-- =============================================================================
-- 8. delete_task_result returns JSONB
-- =============================================================================

SELECT is(
  (SELECT prorettype::regtype::text FROM pg_proc WHERE proname = 'delete_task_result'),
  'jsonb',
  'delete_task_result returns jsonb'
);

SELECT * FROM finish();
ROLLBACK;
