-- =============================================================================
-- TESTS: cadence anchor engine (unit level)
--   Migration: supabase/migrations/20260703003822_cadence_anchor_engine.sql
--   Spec:      docs/CADENCE_ANCHOR_SPEC.md (Design C — replaces v1
--              "clock_aligned"; the old v1 tests this file used to hold are
--              superseded along with the engine).
--
-- Coverage:
--   A1-A13  next_cadence_boundary(): grid math incl. wrap-around, non-12h
--           steps, 24h step, timezone awareness, and FIXED-DATE DST cases
--           (America/New_York 2027-03-14 spring-forward = one 11h phase;
--           2026-11-01 fall-back = one 13h phase), defensive step<=0.
--   B1-B4   safe_timezone(): valid / NULL / empty / garbage.
--   C1-C8   snap_phase_end_to_cadence trigger: snap-to-grid, null-anchor
--           no-op (byte-identical), unequal-duration defensive no-op, NULL
--           phase_ends_at no-op, extendTimer-shape stale-start regression
--           (GREATEST(now(),...) reference), minimum-runway skip (12h and
--           1h durations).
--   D1-D3   old-client compat shim (clock_aligned=true -> ambient 3am/3pm
--           anchor; no-fire for non-12h and adaptive inserts).
--   E1-E7   coherence enforcement: guard trigger RAISEs (unequal durations,
--           non-dividing duration, post-create duration edits) and the
--           chats_cadence_adaptive_excl CHECK; coherent insert lives.
--
-- Writer-matrix integration tests (real trigger pipeline) live in
-- 132_cadence_writer_matrix_test.sql.
--
-- NOTE: now() is transaction_timestamp() — constant for this whole BEGIN/
-- ROLLBACK block — so expectations computed from now() are deterministic.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(35);

-- --- A: next_cadence_boundary() ----------------------------------------------
-- Ambient grid (anchor time-of-day 03:00, 12h step -> {03:00, 15:00}).
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 14:00:00+00', 'UTC', TIME '03:00', 43200),
          TIMESTAMPTZ '2026-06-29 15:00:00+00', 'A1: 2pm UTC -> today 3pm');
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 16:00:00+00', 'UTC', TIME '03:00', 43200),
          TIMESTAMPTZ '2026-06-30 03:00:00+00', 'A2: 4pm UTC -> tomorrow 3am');
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 02:00:00+00', 'UTC', TIME '03:00', 43200),
          TIMESTAMPTZ '2026-06-29 03:00:00+00', 'A3: 2am UTC -> today 3am');
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 15:00:00+00', 'UTC', TIME '03:00', 43200),
          TIMESTAMPTZ '2026-06-30 03:00:00+00', 'A4: exactly on a grid point -> strictly after');
-- Wrap-around: anchor 15:00 with 12h step ALSO means 03:00 belongs to the
-- grid on the same local day (the (anchor + k*step) mod 24h construction).
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 01:00:00+00', 'UTC', TIME '15:00', 43200),
          TIMESTAMPTZ '2026-06-29 03:00:00+00', 'A5: wrap — anchor 15:00 grid includes 03:00 the same day');
-- America/New_York is UTC-4 in June (EDT): 14:00 UTC = 10:00 EDT -> next 3pm EDT = 19:00 UTC
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 14:00:00+00', 'America/New_York', TIME '03:00', 43200),
          TIMESTAMPTZ '2026-06-29 19:00:00+00', 'A6: timezone-aware — 10am EDT -> 3pm EDT');
-- 6h step: anchor 01:00 -> grid {01,07,13,19}
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 14:30:00+00', 'UTC', TIME '01:00', 21600),
          TIMESTAMPTZ '2026-06-29 19:00:00+00', 'A7: 6h step — grid {01,07,13,19} -> 19:00');
-- 24h step: single daily time
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 14:00:00+00', 'UTC', TIME '09:30', 86400),
          TIMESTAMPTZ '2026-06-30 09:30:00+00', 'A8: 24h step — one grid time daily');
-- DST spring-forward (America/New_York, 2027-03-14: 02:00 EST -> 03:00 EDT).
-- 2027-03-13 15:00 EST = 20:00 UTC; next grid point 2027-03-14 03:00 EDT
-- = 07:00 UTC — an 11h phase on the transition day (accepted + documented).
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2027-03-13 20:00:00+00', 'America/New_York', TIME '03:00', 43200),
          TIMESTAMPTZ '2027-03-14 07:00:00+00', 'A9: spring-forward — 3pm EST -> 3am EDT is an 11h phase, grid stays on local wall time');
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2027-03-14 07:00:00+00', 'America/New_York', TIME '03:00', 43200),
          TIMESTAMPTZ '2027-03-14 19:00:00+00', 'A10: spring-forward day continues 3am->3pm local (normal 12h)');
-- DST fall-back (America/New_York, 2026-11-01: 02:00 EDT -> 01:00 EST).
-- 2026-10-31 15:00 EDT = 19:00 UTC; next grid point 2026-11-01 03:00 EST
-- = 08:00 UTC — a 13h phase on the transition day.
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-10-31 19:00:00+00', 'America/New_York', TIME '03:00', 43200),
          TIMESTAMPTZ '2026-11-01 08:00:00+00', 'A11: fall-back — 3pm EDT -> 3am EST is a 13h phase, grid stays on local wall time');
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-11-01 08:00:00+00', 'America/New_York', TIME '03:00', 43200),
          TIMESTAMPTZ '2026-11-01 20:00:00+00', 'A12: fall-back day continues 3am->3pm local (normal 12h)');
SELECT is(next_cadence_boundary(TIMESTAMPTZ '2026-06-29 14:00:00+00', 'UTC', TIME '03:00', 0),
          NULL::TIMESTAMPTZ, 'A13: defensive — step <= 0 returns NULL instead of dividing by zero');

-- --- B: safe_timezone() -------------------------------------------------------
SELECT is(safe_timezone('America/New_York'), 'America/New_York', 'B1: valid tz passes through');
SELECT is(safe_timezone(NULL),               'UTC',              'B2: NULL -> UTC');
SELECT is(safe_timezone(''),                 'UTC',              'B3: empty -> UTC');
SELECT is(safe_timezone('Not/AZone'),        'UTC',              'B4: garbage -> UTC (never raises — v1 aborted all rounds writes)');

-- --- C: the snap trigger -------------------------------------------------------
-- Isolate our BEFORE trigger from the advance/winner/agent pipelines so the
-- inserts give a clean, deterministic phase_ends_at. Disabling chats triggers
-- ALSO disables the cadence guard, which is deliberate here: chat C needs an
-- incoherent (anchor + unequal durations) row to prove the snap trigger's
-- DEFENSIVE internal gate no-ops — a state the guard makes unreachable
-- through normal writes. (The real-pipeline tests live in 132.)
ALTER TABLE chats  DISABLE TRIGGER USER;
ALTER TABLE cycles DISABLE TRIGGER USER;
ALTER TABLE rounds DISABLE TRIGGER USER;
ALTER TABLE rounds ENABLE  TRIGGER snap_phase_end_to_cadence_trg;

DO $$
DECLARE
  v_anchor  TIMESTAMPTZ := date_trunc('second', now()) + interval '2 hours';   -- >= 1h runway away
  v_anchor2 TIMESTAMPTZ := date_trunc('second', now()) + interval '30 minutes'; -- inside 1h runway (12h phases)
  v_anchor3 TIMESTAMPTZ := date_trunc('second', now()) + interval '10 minutes'; -- inside 15min runway (1h phases)
  v_cyc_a INT; v_cyc_b INT; v_cyc_c INT; v_cyc_e INT; v_cyc_f INT; v_cyc_g INT; v_id INT;
BEGIN
  PERFORM set_config('test.anchor',  v_anchor::text,  false);
  PERFORM set_config('test.anchor2', v_anchor2::text, false);
  PERFORM set_config('test.anchor3', v_anchor3::text, false);

  -- A: cadence chat (anchor 2h from now, 12h phases, UTC) -> snaps
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('Cadence', gen_random_uuid(), 'code', 43200, 43200, v_anchor, 'UTC')
  RETURNING id INTO v_id;
  INSERT INTO cycles (chat_id) VALUES (v_id) RETURNING id INTO v_cyc_a;

  -- B: NULL anchor -> true no-op (byte-identical)
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('Plain', gen_random_uuid(), 'code', 43200, 43200, NULL, 'UTC')
  RETURNING id INTO v_id;
  INSERT INTO cycles (chat_id) VALUES (v_id) RETURNING id INTO v_cyc_b;

  -- C: anchor set but UNEQUAL durations (guard bypassed above) -> defensive no-op
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('Incoherent', gen_random_uuid(), 'code', 43200, 21600, v_anchor, 'UTC')
  RETURNING id INTO v_id;
  INSERT INTO cycles (chat_id) VALUES (v_id) RETURNING id INTO v_cyc_c;

  -- E: cadence chat for the extendTimer-shape regression
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('CadenceStale', gen_random_uuid(), 'code', 43200, 43200, v_anchor, 'UTC')
  RETURNING id INTO v_id;
  INSERT INTO cycles (chat_id) VALUES (v_id) RETURNING id INTO v_cyc_e;

  -- F: cadence chat whose next boundary is 30min away (< 1h runway, 12h phases)
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('CadenceRunway12h', gen_random_uuid(), 'code', 43200, 43200, v_anchor2, 'UTC')
  RETURNING id INTO v_id;
  INSERT INTO cycles (chat_id) VALUES (v_id) RETURNING id INTO v_cyc_f;

  -- G: 1h phases -> runway = LEAST(3600/4, 1h) = 15min; boundary 10min away
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('CadenceRunway1h', gen_random_uuid(), 'code', 3600, 3600, v_anchor3, 'UTC')
  RETURNING id INTO v_id;
  INSERT INTO cycles (chat_id) VALUES (v_id) RETURNING id INTO v_cyc_g;

  -- A: normal-advance shape (phase_started_at = now() in the same tx).
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cyc_a, 1, 'proposing', now(), now() + interval '12 hours');
  -- B/C: fixed non-grid values so "unchanged" is distinguishable from a snap.
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cyc_b, 1, 'proposing', TIMESTAMPTZ '2026-06-29 14:00:00+00', TIMESTAMPTZ '2026-06-30 02:00:00+00');
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cyc_c, 1, 'proposing', TIMESTAMPTZ '2026-06-29 14:00:00+00', TIMESTAMPTZ '2026-06-29 20:00:00+00');

  PERFORM set_config('test.ends_a', (SELECT phase_ends_at::text FROM rounds WHERE cycle_id = v_cyc_a), false);
  PERFORM set_config('test.ends_b', (SELECT phase_ends_at::text FROM rounds WHERE cycle_id = v_cyc_b), false);
  PERFORM set_config('test.ends_c', (SELECT phase_ends_at::text FROM rounds WHERE cycle_id = v_cyc_c), false);

  -- Null end (e.g. host-paused) -> stays null, no error.
  UPDATE rounds SET phase_ends_at = NULL WHERE cycle_id = v_cyc_a;
  PERFORM set_config('test.ends_a_null',
    COALESCE((SELECT phase_ends_at::text FROM rounds WHERE cycle_id = v_cyc_a), 'NULL'), false);

  -- E (extendTimer shape): the phase started 26h ago — its grid boundary
  -- passed long ago. Insert with NULL end (no snap on insert), then do what
  -- process-timers extendTimer does on an unmet minimum: re-arm the full
  -- duration from now WITHOUT touching phase_started_at. The GREATEST(now(),
  -- ...) reference must land the snap in the FUTURE (the v1 hotfix, kept —
  -- pre-hotfix this pinned the round expired forever, one rounds write +
  -- Realtime broadcast per cron minute).
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cyc_e, 1, 'proposing', now() - interval '26 hours', NULL);
  UPDATE rounds SET phase_ends_at = now() + interval '12 hours' WHERE cycle_id = v_cyc_e;
  PERFORM set_config('test.ends_e', (SELECT phase_ends_at::text FROM rounds WHERE cycle_id = v_cyc_e), false);

  -- F (runway skip, 12h): next grid point is 30min out (< LEAST(3h,1h)=1h) ->
  -- must skip to the FOLLOWING point (anchor2 + 12h), never a sliver phase.
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cyc_f, 1, 'proposing', now(), now() + interval '12 hours');
  PERFORM set_config('test.ends_f', (SELECT phase_ends_at::text FROM rounds WHERE cycle_id = v_cyc_f), false);

  -- G (runway skip, 1h): next grid point 10min out (< LEAST(15min,1h)=15min)
  -- -> skip to anchor3 + 1h.
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cyc_g, 1, 'proposing', now(), now() + interval '1 hour');
  PERFORM set_config('test.ends_g', (SELECT phase_ends_at::text FROM rounds WHERE cycle_id = v_cyc_g), false);
END $$;

SELECT is(current_setting('test.ends_a')::timestamptz, current_setting('test.anchor')::timestamptz,
          'C1: cadence chat — phase_ends_at snapped to the anchor grid point after now()');
SELECT is(current_setting('test.ends_b')::timestamptz, TIMESTAMPTZ '2026-06-30 02:00:00+00',
          'C2: NULL anchor — phase_ends_at byte-identical to what the writer computed (true no-op)');
SELECT is(current_setting('test.ends_c')::timestamptz, TIMESTAMPTZ '2026-06-29 20:00:00+00',
          'C3: anchor + unequal durations — defensive gate leaves the value untouched');
SELECT is(current_setting('test.ends_a_null'), 'NULL',
          'C4: NULL phase_ends_at — no snap, no error');
SELECT ok(current_setting('test.ends_e')::timestamptz > now(),
          'C5: REGRESSION extendTimer — stale-start re-arm snaps to the FUTURE, not the past boundary');
SELECT is(current_setting('test.ends_e')::timestamptz, current_setting('test.anchor')::timestamptz,
          'C6: REGRESSION extendTimer — held over to exactly the next grid point after now()');
SELECT is(current_setting('test.ends_f')::timestamptz,
          current_setting('test.anchor2')::timestamptz + interval '12 hours',
          'C7: runway skip (12h) — boundary 30min out is skipped to the following grid point');
SELECT is(current_setting('test.ends_g')::timestamptz,
          current_setting('test.anchor3')::timestamptz + interval '1 hour',
          'C8: runway skip (1h phases, 15min runway) — boundary 10min out is skipped');

-- --- D: old-client compat shim -------------------------------------------------
-- Re-enable the chats pipeline: the shim + guard are chats triggers.
ALTER TABLE chats ENABLE TRIGGER USER;

DO $$
DECLARE
  v_id INT;
BEGIN
  -- Old client (iOS 20.2.0) shape: clock_aligned = true, 12h phases.
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     clock_aligned, schedule_timezone)
  VALUES ('OldClient', gen_random_uuid(), 'code', 43200, 43200, true, 'UTC')
  RETURNING id INTO v_id;
  PERFORM set_config('test.shim_anchor',
    COALESCE((SELECT cadence_anchor_at::text FROM chats WHERE id = v_id), 'NULL'), false);

  -- clock_aligned but non-12h: v1 silently gated on 43200 — the shim only
  -- translates the 12h shape; everything else keeps plain durations.
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     clock_aligned, schedule_timezone)
  VALUES ('OldClientShort', gen_random_uuid(), 'code', 3600, 3600, true, 'UTC')
  RETURNING id INTO v_id;
  PERFORM set_config('test.shim_anchor_short',
    COALESCE((SELECT cadence_anchor_at::text FROM chats WHERE id = v_id), 'NULL'), false);

  -- clock_aligned + adaptive: setting an anchor would trip the CHECK and
  -- break the old client's create — the shim leaves the anchor NULL.
  INSERT INTO chats (name, creator_session_token, access_method,
                     proposing_duration_seconds, rating_duration_seconds,
                     clock_aligned, adaptive_duration_enabled, schedule_timezone)
  VALUES ('OldClientAdaptive', gen_random_uuid(), 'code', 43200, 43200, true, true, 'UTC')
  RETURNING id INTO v_id;
  PERFORM set_config('test.shim_anchor_adaptive',
    COALESCE((SELECT cadence_anchor_at::text FROM chats WHERE id = v_id), 'NULL'), false);
END $$;

SELECT is(current_setting('test.shim_anchor')::timestamptz,
          next_cadence_boundary(now(), 'UTC', TIME '03:00', 43200),
          'D1: compat shim — clock_aligned=true 12h insert gets the ambient next-3am/3pm anchor');
SELECT is(current_setting('test.shim_anchor_short'), 'NULL',
          'D2: compat shim — non-12h clock_aligned insert keeps a NULL anchor (plain durations)');
SELECT is(current_setting('test.shim_anchor_adaptive'), 'NULL',
          'D3: compat shim — adaptive clock_aligned insert keeps a NULL anchor (no CHECK explosion for old clients)');

-- --- E: coherence enforcement — loud, never silent ------------------------------
SELECT throws_ok(
  $$INSERT INTO chats (name, creator_session_token, access_method,
                       proposing_duration_seconds, rating_duration_seconds, cadence_anchor_at)
    VALUES ('BadUnequal', gen_random_uuid(), 'code', 43200, 21600, now() + interval '2 hours')$$,
  NULL,
  'E1: guard — INSERT anchor with unequal durations RAISES');

SELECT throws_ok(
  $$INSERT INTO chats (name, creator_session_token, access_method,
                       proposing_duration_seconds, rating_duration_seconds, cadence_anchor_at)
    VALUES ('BadNonDividing', gen_random_uuid(), 'code', 18000, 18000, now() + interval '2 hours')$$,
  NULL,
  'E2: guard — INSERT anchor with a duration that does not divide 24h (5h) RAISES');

-- A coherent cadence chat to mutate.
SELECT lives_ok(
  $$INSERT INTO chats (name, creator_session_token, access_method,
                       proposing_duration_seconds, rating_duration_seconds,
                       cadence_anchor_at, schedule_timezone)
    VALUES ('GoodCadence', gen_random_uuid(), 'code', 21600, 21600, now() + interval '2 hours', 'America/New_York')$$,
  'E3: coherent anchor (equal 6h phases) INSERTs fine');

SELECT throws_ok(
  $$UPDATE chats SET proposing_duration_seconds = 3600 WHERE name = 'GoodCadence'$$,
  NULL,
  'E4: guard — post-create duration edit that breaks the grid RAISES (not silent)');

SELECT throws_ok(
  $$UPDATE chats SET proposing_duration_seconds = 18000, rating_duration_seconds = 18000
    WHERE name = 'GoodCadence'$$,
  NULL,
  'E5: guard — post-create edit to a non-dividing duration RAISES');

SELECT throws_ok(
  $$UPDATE chats SET adaptive_duration_enabled = true WHERE name = 'GoodCadence'$$,
  '23514', NULL,
  'E6: CHECK chats_cadence_adaptive_excl — enabling adaptive on a cadence chat violates the constraint');

SELECT throws_ok(
  $$INSERT INTO chats (name, creator_session_token, access_method,
                       proposing_duration_seconds, rating_duration_seconds,
                       cadence_anchor_at, adaptive_duration_enabled)
    VALUES ('BadAdaptive', gen_random_uuid(), 'code', 43200, 43200, now() + interval '2 hours', true)$$,
  '23514', NULL,
  'E7: CHECK — INSERT with anchor + adaptive violates the constraint');

SELECT * FROM finish();
ROLLBACK;
