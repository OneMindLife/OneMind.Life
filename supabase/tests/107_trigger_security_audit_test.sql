-- =============================================================================
-- Architectural lint: every public trigger function that mutates a table
-- OTHER than its attached table must be SECURITY DEFINER.
-- =============================================================================
-- Background — the trap (see feedback_trigger_security_definer.md):
--
--   When a trigger function fires on user-initiated DML, the function runs
--   as the calling role (typically `authenticated`/`anon`). Any UPDATE /
--   INSERT / DELETE inside the function then has to satisfy that role's
--   RLS policies on the target table. If the target has RLS enabled and
--   lacks a permissive policy for the operation, default-deny silently
--   filters the statement to ZERO rows — no error, no warning, no log.
--
--   We learned this the hard way twice on 2026-05-02:
--     - sync_proposition_rating_count (L1 denorm trigger) — fixed in
--       20260502150000
--     - on_proposition_update_activity + on_rating_update_activity —
--       fixed in 20260502160000
--
--   This test makes a third occurrence impossible to ship: it scans
--   pg_proc ∩ pg_trigger and fails if any non-DEFINER trigger function's
--   body contains DML against a table other than the trigger's own.
--
-- Allowlist semantics:
--   - RAISE-only triggers (rate limits, validations) — never do DML
--   - NEW-only triggers (BEFORE INSERT/UPDATE that just set NEW.col) —
--     no DML to other tables
--   - Latent triggers (only fire via SECURITY DEFINER chains today) —
--     allowlisted with explicit reason; if a future change adds a
--     user-initiated path to the firing table, REMOVE from allowlist
--     and add SECURITY DEFINER.
--
-- Adding a new trigger? Two paths:
--   1. Mark the function SECURITY DEFINER + SET search_path = public, pg_temp
--      → no further action needed. The lint accepts it.
--   2. The trigger doesn't do cross-table DML (RAISE only, or NEW only)
--      → add the function name to v_allowlist below with a one-line reason.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(1);

-- Helper: per-function audit, expressed as a CTE chain we can reuse for the
-- test assertion AND a DEBUG dump of any offenders.
DO $$
DECLARE
  v_allowlist TEXT[] := ARRAY[
    -- RAISE-only / NEW-only — no DML to any other table
    'enforce_proposition_rate_limit',
    'enforce_rating_rate_limit',
    'on_chat_insert_set_code',
    'set_schedule_paused_on_insert',
    'update_moltbook_agent_state_updated_at',
    'update_moltcourt_agent_state_updated_at',
    'update_updated_at_column',
    'validate_chat_background_audio_url',
    'trigger_copy_round_media_to_cycle',
    -- Latent — fire today only via SECURITY DEFINER chains.
    -- If a future migration adds a user-initiated path to UPDATE rounds /
    -- UPDATE cycles, REMOVE these from the allowlist and add
    -- SECURITY DEFINER to the function bodies.
    'kick_inactive_from_official_on_round_completion',
    'on_round_winner_set',
    'on_cycle_winner_set'
  ];
  v_offenders TEXT;
  v_offender_count INT;
BEGIN
  -- Strip line-comments + block-comments so we don't false-positive on
  -- DML keywords appearing in commentary.
  CREATE TEMP TABLE _trig_clean ON COMMIT DROP AS
  SELECT
    p.proname::TEXT AS proname,
    p.prosecdef,
    array_agg(DISTINCT lower(t.tgrelid::regclass::TEXT)) AS attached_tables,
    regexp_replace(
      regexp_replace(p.prosrc, '--[^\n]*', '', 'g'),
      '/\*.*?\*/', '', 'g'
    ) AS body
  FROM pg_proc p
  JOIN pg_trigger t ON t.tgfoid = p.oid
  WHERE p.pronamespace = 'public'::regnamespace
    AND NOT t.tgisinternal
    AND p.prorettype = 'trigger'::regtype
  GROUP BY p.oid, p.proname, p.prosecdef, p.prosrc;

  -- For each non-DEFINER, non-allowlisted trigger function, find DML
  -- targets in its body. Strip "public." prefix and pg_-internal noise.
  CREATE TEMP TABLE _trig_dml ON COMMIT DROP AS
  SELECT DISTINCT
    c.proname,
    c.attached_tables,
    lower(m[1]) AS target_tbl
  FROM _trig_clean c,
  LATERAL regexp_matches(
    c.body,
    '(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(?:public\.)?(\w+)',
    'gi'
  ) AS m
  WHERE NOT c.prosecdef
    AND NOT (c.proname = ANY(v_allowlist))
    -- Strip schema-qualified attached tables for comparison
    AND lower(m[1]) NOT IN (
      SELECT replace(unnest(c.attached_tables), 'public.', '')
    )
    AND lower(m[1]) NOT LIKE 'pg_%';

  -- Per-function: collapse target tables into a comma list
  WITH per_func AS (
    SELECT
      proname,
      attached_tables,
      string_agg(DISTINCT target_tbl, ',' ORDER BY target_tbl) AS targets
    FROM _trig_dml
    GROUP BY proname, attached_tables
  )
  SELECT
    string_agg(
      proname || ' [attached=' ||
        array_to_string(attached_tables, ',') ||
        '] writes-to=' || targets,
      E'\n  '
    ),
    COUNT(*)
  INTO v_offenders, v_offender_count
  FROM per_func;

  IF v_offender_count IS NULL THEN
    v_offender_count := 0;
  END IF;

  -- Stash for the assertion + diagnostic
  PERFORM set_config('test.trig_audit.count',
    v_offender_count::TEXT, TRUE);
  PERFORM set_config('test.trig_audit.offenders',
    COALESCE(v_offenders, '<none>'), TRUE);

  IF v_offender_count > 0 THEN
    RAISE NOTICE E'\n[TRIGGER SECURITY AUDIT] % offending trigger function(s):\n  %\n\n'
      'Each does cross-table DML without SECURITY DEFINER. Under RLS-on, '
      'non-host calling roles will silently no-op the side effect. Either:\n'
      '  1. Add SECURITY DEFINER + SET search_path = public, pg_temp, OR\n'
      '  2. Add the function to v_allowlist with a one-line reason.\n'
      'See feedback_trigger_security_definer.md.',
      v_offender_count, v_offenders;
  END IF;
END $$;

-- Single assertion: zero offenders.
SELECT is(
  current_setting('test.trig_audit.count')::INT,
  0,
  'Architectural lint: no non-SECURITY-DEFINER trigger function does cross-table DML (silent-no-op trap). See feedback_trigger_security_definer.md.'
);

SELECT * FROM finish();
ROLLBACK;
