-- =============================================================================
-- notify_push_round — structural contract for the push-notification trigger
-- (the FCM twin of notify_telegram_round; migration 20260712160000).
-- =============================================================================
-- Guards:
--   1. The trigger exists on rounds (INSERT + UPDATE) — pushes must fire no
--      matter which driver flips a phase (thresholds, telegram bot,
--      process-timers). process-timers' direct notify calls were REMOVED in
--      favor of this trigger; if the trigger disappears, pushes silently die.
--   2. notify_push_round() and verify_push_internal() are SECURITY DEFINER
--      (vault reads + cross-table SELECTs run from user-initiated DML).
--   3. verify_push_internal is not executable by anon/authenticated (it
--      would let clients brute-force the internal bearer).
--   4. The vault secret exists.

BEGIN;
SELECT plan(8);

-- 1. Trigger wiring
SELECT has_trigger('public', 'rounds', 'notify_push_round_trg',
  'notify_push_round_trg exists on rounds');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'rounds' AND t.tgname = 'notify_push_round_trg'
      AND (t.tgtype::int & 4) > 0   -- INSERT
      AND (t.tgtype::int & 16) > 0  -- UPDATE
  ),
  'notify_push_round_trg fires on both INSERT and UPDATE'
);

-- 2. SECURITY DEFINER
SELECT ok(
  (SELECT prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'notify_push_round'),
  'notify_push_round() is SECURITY DEFINER'
);

SELECT ok(
  (SELECT prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'verify_push_internal'),
  'verify_push_internal() is SECURITY DEFINER'
);

-- 3. Client roles cannot execute the verifier
SELECT ok(
  NOT has_function_privilege('anon', 'public.verify_push_internal(text)', 'EXECUTE'),
  'anon cannot execute verify_push_internal'
);

SELECT ok(
  NOT has_function_privilege('authenticated', 'public.verify_push_internal(text)', 'EXECUTE'),
  'authenticated cannot execute verify_push_internal'
);

SELECT ok(
  has_function_privilege('service_role', 'public.verify_push_internal(text)', 'EXECUTE'),
  'service_role can execute verify_push_internal'
);

-- 4. Vault secret provisioned
SELECT ok(
  EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'push_internal_secret'),
  'push_internal_secret exists in vault'
);

SELECT * FROM finish();
ROLLBACK;
