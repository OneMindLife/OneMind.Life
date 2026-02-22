-- =============================================================================
-- TEST: Host Consensus Management
-- =============================================================================
-- Tests for delete_consensus, update_initial_message, delete_initial_message
-- functions and the translate_chat_on_update trigger.
-- Uses function source introspection (pg_proc.prosrc) since pgTAP tests
-- cannot set auth.uid() for SECURITY DEFINER functions.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;

SELECT plan(15);

-- =============================================================================
-- 1. Function existence tests
-- =============================================================================

SELECT has_function(
  'public',
  'delete_consensus',
  ARRAY['bigint'],
  'delete_consensus(bigint) function exists'
);

SELECT has_function(
  'public',
  'update_initial_message',
  ARRAY['bigint', 'text'],
  'update_initial_message(bigint, text) function exists'
);

SELECT has_function(
  'public',
  'delete_initial_message',
  ARRAY['bigint'],
  'delete_initial_message(bigint) function exists'
);

SELECT has_function(
  'public',
  'trigger_translate_chat_on_update',
  'trigger_translate_chat_on_update() function exists'
);

-- =============================================================================
-- 2. Source introspection — delete_consensus contains host verification
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus')::text,
  '%is_host%'::text,
  'delete_consensus source contains host verification (is_host)'
);

-- =============================================================================
-- 3. Source introspection — delete_consensus contains cycle restart logic
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus')::text,
  '%create_round_for_cycle%'::text,
  'delete_consensus source contains cycle restart via create_round_for_cycle'
);

-- =============================================================================
-- 4. Source introspection — update_initial_message contains host verification
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'update_initial_message')::text,
  '%is_host%'::text,
  'update_initial_message source contains host verification (is_host)'
);

-- =============================================================================
-- 5. Source introspection — delete_initial_message clears translations
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_initial_message')::text,
  '%DELETE FROM translations%'::text,
  'delete_initial_message source deletes translations'
);

-- =============================================================================
-- 6. Source introspection — trigger clears stale translations
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_translate_chat_on_update')::text,
  '%DELETE FROM translations%'::text,
  'trigger_translate_chat_on_update deletes stale translations'
);

-- =============================================================================
-- 7. Source introspection — trigger calls translate edge function
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_translate_chat_on_update')::text,
  '%net.http_post%'::text,
  'trigger_translate_chat_on_update calls translate via net.http_post'
);

-- =============================================================================
-- 8. Permissions — delete_consensus NOT executable by anon
-- =============================================================================

SELECT is(
  (SELECT COUNT(*)::int FROM information_schema.routine_privileges
   WHERE routine_name = 'delete_consensus'
     AND grantee = 'anon'
     AND privilege_type = 'EXECUTE'),
  0,
  'delete_consensus is not executable by anon role'
);

-- =============================================================================
-- 9. Trigger exists on chats for initial_message update
-- =============================================================================

SELECT has_trigger(
  'chats',
  'translate_chat_on_update',
  'translate_chat_on_update trigger exists on chats table'
);

-- =============================================================================
-- 10. Source introspection — delete_consensus checks latest BEFORE clearing
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus')::text,
  '%v_was_latest%'::text,
  'delete_consensus checks if cycle was latest BEFORE clearing completed_at'
);

-- =============================================================================
-- 11. Source introspection — delete_consensus cleans up subsequent cycles
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus')::text,
  '%DELETE FROM cycles%'::text,
  'delete_consensus deletes subsequent incomplete cycles'
);

-- =============================================================================
-- 12. Source introspection — delete_consensus uses v_was_latest in IF
-- =============================================================================

SELECT like(
  (SELECT prosrc FROM pg_proc WHERE proname = 'delete_consensus')::text,
  '%IF v_was_latest THEN%'::text,
  'delete_consensus branches on v_was_latest flag'
);

SELECT * FROM finish();
ROLLBACK;
