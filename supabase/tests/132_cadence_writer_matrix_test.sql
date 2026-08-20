-- =============================================================================
-- TESTS: cadence anchor engine — WRITER MATRIX (integration, real pipeline)
--   Migration: supabase/migrations/20260703003822_cadence_anchor_engine.sql
--   Spec:      docs/CADENCE_ANCHOR_SPEC.md section 4 — every live writer of
--              rounds.phase_ends_at runs against a cadence chat AND a
--              null-anchor chat, with the REAL trigger pipeline ENABLED
--              (no DISABLE TRIGGER USER anywhere in this file).
--
-- Writers exercised:
--   W1  auto-start round creation via participant join
--       (trigger_check_auto_start -> create_round_for_cycle)
--   W2  waiting -> proposing UPDATE (process-timers advance shape)
--   W3  proposing -> rating early advance via REAL proposition INSERTs
--       tripping check_early_advance_on_proposition (thresholds enabled)
--   W4  extendTimer shape (UPDATE only phase_ends_at, stale phase_started_at)
--   W5  host_pause_chat / host_resume_chat RPCs across a boundary
--   W6  rating completion (real grid_rankings INSERTs tripping
--       check_early_advance_on_rating) -> complete_round_with_winner ->
--       next-round creation
--
-- Invariants asserted after every writer:
--   (a) committed phase_ends_at > now()
--   (b) cadence chat: phase_ends_at lands ON the anchor grid
--       ((ends AT TIME ZONE tz)::time is a grid time)
--   (c) null-anchor chat: value byte-identical to what the writer computed
--       (the engine is a TRUE no-op without an anchor)
--
-- Negative controls (spec-mandated: prove the assertions CAN fail):
--   NC1 stale-start: re-create the snap fn with the pre-hotfix
--       v_from := COALESCE(NEW.phase_started_at, now()) inside this test's
--       transaction -> the extendTimer writer pins the deadline in the PAST
--       (the v1 expire->extend->re-pin loop); restore the real fn -> future.
--   NC2 runway: re-create the snap fn WITHOUT the minimum-runway skip ->
--       a writer near a grid point produces a sliver deadline; restore ->
--       it skips to the following grid point.
--
-- Chats:
--   CAD  anchor = now()+2h, tz America/New_York, 12h phases. Within this
--        transaction every snap reference is now(), and the anchor is the
--        first grid instant after now() (2h > 1h runway) — so every CAD
--        writer must land EXACTLY on the anchor instant. Instant equality
--        is DST-proof.
--   NUL  identical settings, anchor NULL — writer values must survive
--        byte-identical.
--   CADR anchor = now()+30min, tz UTC, 12h phases — the next grid point is
--        INSIDE the 1h runway, so real writers must skip to anchor+12h.
--
-- NOTE: now() is transaction_timestamp() — constant for this whole BEGIN/
-- ROLLBACK block — so all expectations are deterministic.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(43);

-- -----------------------------------------------------------------------------
-- Setup: chats + hosts + joins (W1 fires on the 3rd join)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_anchor   TIMESTAMPTZ := date_trunc('second', now()) + interval '2 hours';
  v_anchor2  TIMESTAMPTZ := date_trunc('second', now()) + interval '30 minutes';
  v_cad_host UUID := gen_random_uuid();
  v_nul_host UUID := gen_random_uuid();
  v_cadr_host UUID := gen_random_uuid();
  v_u UUID;
  v_cad INT; v_nul INT; v_cadr INT;
  v_pid INT;
  i INT;
BEGIN
  PERFORM set_config('test.anchor',  v_anchor::text,  false);
  PERFORM set_config('test.anchor2', v_anchor2::text, false);
  PERFORM set_config('test.cad_host', v_cad_host::text, false);
  PERFORM set_config('test.nul_host', v_nul_host::text, false);

  INSERT INTO auth.users (id) VALUES (v_cad_host), (v_nul_host), (v_cadr_host);

  -- Defaults intentionally kept: proposing_threshold_percent=100 +
  -- proposing_threshold_count=3 + proposing_minimum=3 (early advance fires
  -- when all 3 participants have submitted); rating_threshold_count=2 (the
  -- per-proposition rating early advance is armed); rating_start_mode='auto'.
  INSERT INTO chats (name, initial_message, creator_session_token, access_method,
                     start_mode, auto_start_participant_count,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('CadenceMatrix', 'Q?', gen_random_uuid(), 'code', 'auto', 3,
          43200, 43200, v_anchor, 'America/New_York')
  RETURNING id INTO v_cad;

  INSERT INTO chats (name, initial_message, creator_session_token, access_method,
                     start_mode, auto_start_participant_count,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('NullAnchorMatrix', 'Q?', gen_random_uuid(), 'code', 'auto', 3,
          43200, 43200, NULL, 'America/New_York')
  RETURNING id INTO v_nul;

  INSERT INTO chats (name, initial_message, creator_session_token, access_method,
                     start_mode, auto_start_participant_count,
                     proposing_duration_seconds, rating_duration_seconds,
                     cadence_anchor_at, schedule_timezone)
  VALUES ('CadenceRunwayMatrix', 'Q?', gen_random_uuid(), 'code', 'auto', 3,
          43200, 43200, v_anchor2, 'UTC')
  RETURNING id INTO v_cadr;

  PERFORM set_config('test.cad',  v_cad::text,  false);
  PERFORM set_config('test.nul',  v_nul::text,  false);
  PERFORM set_config('test.cadr', v_cadr::text, false);

  -- W1: REAL writer — participant joins trip trigger_check_auto_start; the
  -- 3rd active join creates cycle + round (proposing, funded, timed).
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_cad, v_cad_host, 'CadHost', TRUE, 'active');
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_nul, v_nul_host, 'NulHost', TRUE, 'active');
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_cadr, v_cadr_host, 'CadrHost', TRUE, 'active');
  FOR i IN 1..2 LOOP
    v_u := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v_u);
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_cad, v_u, 'CadP' || i, FALSE, 'active');
    v_u := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v_u);
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_nul, v_u, 'NulP' || i, FALSE, 'active');
    v_u := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v_u);
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_cadr, v_u, 'CadrP' || i, FALSE, 'active');
  END LOOP;
END $$;

-- Round-id helpers used throughout (latest round of a chat).
CREATE FUNCTION pg_temp.round_of(p_chat INT) RETURNS BIGINT LANGUAGE sql AS
$$ SELECT r.id FROM rounds r JOIN cycles c ON c.id = r.cycle_id
   WHERE c.chat_id = p_chat ORDER BY r.id DESC LIMIT 1 $$;
CREATE FUNCTION pg_temp.ends_of(p_chat INT) RETURNS TIMESTAMPTZ LANGUAGE sql AS
$$ SELECT r.phase_ends_at FROM rounds r JOIN cycles c ON c.id = r.cycle_id
   WHERE c.chat_id = p_chat ORDER BY r.id DESC LIMIT 1 $$;
-- Invariant (b): the committed end lands on the anchor's wall-clock grid.
CREATE FUNCTION pg_temp.on_grid(p_ends TIMESTAMPTZ, p_anchor TIMESTAMPTZ, p_tz TEXT) RETURNS BOOLEAN LANGUAGE sql AS
$$ SELECT (p_ends AT TIME ZONE p_tz)::time IN
     ((p_anchor AT TIME ZONE p_tz)::time,
      (p_anchor AT TIME ZONE p_tz)::time + interval '12 hours') $$;

-- --- Sanity: W1 created proposing rounds through the real pipeline -------------
SELECT is((SELECT phase FROM rounds WHERE id = pg_temp.round_of(current_setting('test.cad')::int)),
          'proposing', 'S1: CAD — 3rd join auto-started a proposing round (real trigger path)');
SELECT is((SELECT phase FROM rounds WHERE id = pg_temp.round_of(current_setting('test.nul')::int)),
          'proposing', 'S2: NUL — 3rd join auto-started a proposing round');
SELECT is((SELECT phase FROM rounds WHERE id = pg_temp.round_of(current_setting('test.cadr')::int)),
          'proposing', 'S3: CADR — 3rd join auto-started a proposing round');

-- --- W1: auto-start via participant join ---------------------------------------
SELECT is(pg_temp.ends_of(current_setting('test.cad')::int),
          current_setting('test.anchor')::timestamptz,
          'W1 CAD: auto-start deadline snapped exactly to the anchor instant');
SELECT ok(pg_temp.ends_of(current_setting('test.cad')::int) > now(),
          'W1 CAD invariant (a): committed phase_ends_at > now()');
SELECT ok(pg_temp.on_grid(pg_temp.ends_of(current_setting('test.cad')::int),
                          current_setting('test.anchor')::timestamptz, 'America/New_York'),
          'W1 CAD invariant (b): phase_ends_at lands ON the anchor grid (local wall time)');
SELECT is(pg_temp.ends_of(current_setting('test.nul')::int),
          calculate_round_minute_end(43200),
          'W1 NUL invariant (c): byte-identical to what create_round_for_cycle computed (true no-op)');
SELECT ok(pg_temp.ends_of(current_setting('test.nul')::int) > now(),
          'W1 NUL invariant (a): committed phase_ends_at > now()');
-- Runway skip on a REAL writer: CADR's next grid point (anchor2, 30min out)
-- is inside the 1h runway -> auto-start must land on anchor2 + 12h. (UTC, so
-- exact interval arithmetic — no DST wobble.)
SELECT is(pg_temp.ends_of(current_setting('test.cadr')::int),
          current_setting('test.anchor2')::timestamptz + interval '12 hours',
          'W1 CADR: sliver boundary (30min out) skipped to the following grid point');
SELECT ok(pg_temp.ends_of(current_setting('test.cadr')::int) > now() + interval '1 hour',
          'W1 CADR: no sliver phase — deadline beyond the runway');

-- --- W2: waiting -> proposing UPDATE (process-timers advance shape) ------------
DO $$
DECLARE
  v_cad_r BIGINT := pg_temp.round_of(current_setting('test.cad')::int);
  v_nul_r BIGINT := pg_temp.round_of(current_setting('test.nul')::int);
BEGIN
  -- Put both rounds back to waiting (rating_start_mode='manual' pathways do
  -- this in prod), then perform the exact process-timers advance write.
  UPDATE rounds SET phase = 'waiting', phase_started_at = NULL, phase_ends_at = NULL
  WHERE id IN (v_cad_r, v_nul_r);
  UPDATE rounds SET phase = 'proposing', phase_started_at = now(),
                    phase_ends_at = now() + interval '12 hours'
  WHERE id IN (v_cad_r, v_nul_r);
END $$;

SELECT is(pg_temp.ends_of(current_setting('test.cad')::int),
          current_setting('test.anchor')::timestamptz,
          'W2 CAD: waiting->proposing advance snapped to the anchor instant');
SELECT ok(pg_temp.ends_of(current_setting('test.cad')::int) > now(),
          'W2 CAD invariant (a): phase_ends_at > now()');
SELECT ok(pg_temp.on_grid(pg_temp.ends_of(current_setting('test.cad')::int),
                          current_setting('test.anchor')::timestamptz, 'America/New_York'),
          'W2 CAD invariant (b): on the grid');
SELECT is(pg_temp.ends_of(current_setting('test.nul')::int), now() + interval '12 hours',
          'W2 NUL invariant (c): byte-identical to the writer''s now()+duration');
SELECT ok(pg_temp.ends_of(current_setting('test.nul')::int) > now(),
          'W2 NUL invariant (a): phase_ends_at > now()');

-- --- W3: proposing -> rating early advance via REAL proposition inserts --------
-- All 3 participants submit; the 3rd insert trips
-- check_early_advance_on_proposition (percent=100 + count=3 + minimum=3 all
-- met) which flips the phase and writes a fresh rating deadline.
DO $$
DECLARE
  v_chat INT; v_round BIGINT; v_p RECORD;
BEGIN
  FOREACH v_chat IN ARRAY ARRAY[current_setting('test.cad')::int, current_setting('test.nul')::int] LOOP
    v_round := pg_temp.round_of(v_chat);
    FOR v_p IN SELECT id FROM participants WHERE chat_id = v_chat AND status = 'active' ORDER BY id LOOP
      INSERT INTO propositions (round_id, participant_id, content)
      VALUES (v_round, v_p.id, 'Idea of participant ' || v_p.id);
    END LOOP;
  END LOOP;
END $$;

SELECT is((SELECT phase FROM rounds WHERE id = pg_temp.round_of(current_setting('test.cad')::int)),
          'rating', 'W3 CAD: real proposition inserts early-advanced the round to rating');
SELECT is(pg_temp.ends_of(current_setting('test.cad')::int),
          current_setting('test.anchor')::timestamptz,
          'W3 CAD: rating deadline snapped to the anchor instant');
SELECT ok(pg_temp.ends_of(current_setting('test.cad')::int) > now(),
          'W3 CAD invariant (a): phase_ends_at > now()');
SELECT ok(pg_temp.on_grid(pg_temp.ends_of(current_setting('test.cad')::int),
                          current_setting('test.anchor')::timestamptz, 'America/New_York'),
          'W3 CAD invariant (b): on the grid');
SELECT is((SELECT phase FROM rounds WHERE id = pg_temp.round_of(current_setting('test.nul')::int)),
          'rating', 'W3 NUL: early advance fired too');
-- Byte-identical to the early-advance trigger's own minute-rounding formula.
-- Since 20260811160000 the trigger delegates to calculate_round_minute_end(),
-- so this compares against the shared helper directly.
SELECT is(pg_temp.ends_of(current_setting('test.nul')::int),
          calculate_round_minute_end(43200),
          'W3 NUL invariant (c): byte-identical to check_early_advance_on_proposition''s computation');

-- --- W4 + NC1: extendTimer shape (stale phase_started_at) ----------------------
-- process-timers extendTimer re-arms phase_ends_at = now() + duration WITHOUT
-- touching phase_started_at. NEGATIVE CONTROL first: swap in the pre-hotfix
-- variant (reference = phase_started_at, no GREATEST(now())) and prove it
-- pins the deadline into the PAST — the v1 expire->extend->re-pin loop.
DO $$
DECLARE
  v_cad_r BIGINT := pg_temp.round_of(current_setting('test.cad')::int);
  v_nul_r BIGINT := pg_temp.round_of(current_setting('test.nul')::int);
  v_real_def TEXT := pg_get_functiondef('public.snap_phase_end_to_cadence()'::regprocedure);
BEGIN
  -- Make the phase start stale: 26h ago, i.e. several grid boundaries back.
  -- (UPDATE of phase_started_at only — does not fire the snap trigger.)
  UPDATE rounds SET phase_started_at = now() - interval '26 hours'
  WHERE id IN (v_cad_r, v_nul_r);

  -- NC1a: deliberately-BROKEN variant — v_from := COALESCE(NEW.phase_started_at, now())
  CREATE OR REPLACE FUNCTION public.snap_phase_end_to_cadence()
  RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
  DECLARE
    v_anchor TIMESTAMPTZ; v_tz_raw TEXT; v_prop INT; v_rate INT;
    v_tz TEXT; v_local TIME; v_from TIMESTAMPTZ; v_next TIMESTAMPTZ;
  BEGIN
    IF NEW.phase_ends_at IS NULL THEN RETURN NEW; END IF;
    SELECT c.cadence_anchor_at, c.schedule_timezone,
           c.proposing_duration_seconds, c.rating_duration_seconds
      INTO v_anchor, v_tz_raw, v_prop, v_rate
    FROM public.cycles cy JOIN public.chats c ON c.id = cy.chat_id
    WHERE cy.id = NEW.cycle_id;
    IF v_anchor IS NULL OR v_prop IS DISTINCT FROM v_rate
       OR v_prop IS NULL OR v_prop <= 0 OR 86400 % v_prop <> 0 THEN RETURN NEW; END IF;
    v_tz := public.safe_timezone(v_tz_raw);
    v_local := (v_anchor AT TIME ZONE v_tz)::time;
    v_from := COALESCE(NEW.phase_started_at, now());  -- THE v1 BUG (no GREATEST(now()))
    v_next := public.next_cadence_boundary(v_from, v_tz, v_local, v_prop);
    IF v_next - v_from < LEAST(make_interval(secs => v_prop / 4.0), INTERVAL '1 hour') THEN
      v_next := public.next_cadence_boundary(v_next, v_tz, v_local, v_prop);
    END IF;
    NEW.phase_ends_at := v_next;
    RETURN NEW;
  END; $fn$;

  -- The extendTimer write under the broken variant:
  UPDATE rounds SET phase_ends_at = now() + interval '12 hours' WHERE id = v_cad_r;
  PERFORM set_config('test.nc1_broken_ends',
    (SELECT phase_ends_at::text FROM rounds WHERE id = v_cad_r), false);

  -- Restore the REAL function and redo the writer on both chats.
  EXECUTE v_real_def;
  UPDATE rounds SET phase_ends_at = now() + interval '12 hours' WHERE id IN (v_cad_r, v_nul_r);
END $$;

SELECT ok(current_setting('test.nc1_broken_ends')::timestamptz < now(),
          'NC1: NEGATIVE CONTROL — pre-hotfix stale-start variant pins the extension into the PAST (assertion would fail without GREATEST(now()))');
SELECT is(pg_temp.ends_of(current_setting('test.cad')::int),
          current_setting('test.anchor')::timestamptz,
          'W4 CAD: real engine holds the extension over to the next grid point after now()');
SELECT ok(pg_temp.ends_of(current_setting('test.cad')::int) > now(),
          'W4 CAD invariant (a): phase_ends_at > now()');
SELECT ok(pg_temp.on_grid(pg_temp.ends_of(current_setting('test.cad')::int),
                          current_setting('test.anchor')::timestamptz, 'America/New_York'),
          'W4 CAD invariant (b): on the grid');
SELECT is(pg_temp.ends_of(current_setting('test.nul')::int), now() + interval '12 hours',
          'W4 NUL invariant (c): extendTimer value byte-identical (no cadence interference)');
SELECT ok(pg_temp.ends_of(current_setting('test.nul')::int) > now(),
          'W4 NUL invariant (a): phase_ends_at > now()');

-- --- W5: host_pause_chat / host_resume_chat across a boundary ------------------
-- The pause banks remaining time and NULLs phase_ends_at; the resume re-arms
-- from the bank WITHOUT touching phase_started_at (still 26h stale = "the
-- boundary passed while paused"). The snap must land the resume in the
-- future, on-grid — never on the stale start's past boundary.
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.cad_host'))::text, true);
SELECT host_pause_chat(current_setting('test.cad')::bigint);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.nul_host'))::text, true);
SELECT host_pause_chat(current_setting('test.nul')::bigint);
RESET ROLE;

SELECT ok(pg_temp.ends_of(current_setting('test.cad')::int) IS NULL,
          'W5 CAD: pause write (phase_ends_at = NULL) passes through the snap untouched');

SET ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.cad_host'))::text, true);
SELECT host_resume_chat(current_setting('test.cad')::bigint);
SELECT set_config('request.jwt.claims', json_build_object('sub', current_setting('test.nul_host'))::text, true);
SELECT host_resume_chat(current_setting('test.nul')::bigint);
RESET ROLE;

SELECT is(pg_temp.ends_of(current_setting('test.cad')::int),
          current_setting('test.anchor')::timestamptz,
          'W5 CAD: resume across a boundary lands on the next grid point (banked-time write overridden by the cadence)');
SELECT ok(pg_temp.ends_of(current_setting('test.cad')::int) > now(),
          'W5 CAD invariant (a): phase_ends_at > now()');
SELECT ok(pg_temp.on_grid(pg_temp.ends_of(current_setting('test.cad')::int),
                          current_setting('test.anchor')::timestamptz, 'America/New_York'),
          'W5 CAD invariant (b): on the grid');
-- NUL banked exactly 43200s at pause (ends was now()+12h in the same tx), so
-- resume must write exactly calculate_round_minute_end(43200).
SELECT is(pg_temp.ends_of(current_setting('test.nul')::int),
          calculate_round_minute_end(43200),
          'W5 NUL invariant (c): resume value byte-identical to host_resume_chat''s computation');
SELECT ok(pg_temp.ends_of(current_setting('test.nul')::int) > now(),
          'W5 NUL invariant (a): phase_ends_at > now()');

-- --- W6: rating completion -> next-round creation -------------------------------
-- Real grid_rankings inserts: each participant rates the other two
-- propositions (per-proposition threshold = min(7, max(3-1,1)) = 2), the 3rd
-- statement trips check_early_advance_on_rating -> complete_round_with_winner
-- -> on_round_winner_set -> create_round_for_cycle (next proposing round).
DO $$
DECLARE
  v_chat INT; v_round BIGINT; v_p RECORD; v_prop RECORD; v_pos INT;
BEGIN
  FOREACH v_chat IN ARRAY ARRAY[current_setting('test.cad')::int, current_setting('test.nul')::int] LOOP
    v_round := pg_temp.round_of(v_chat);
    PERFORM set_config('test.rating_round_' || v_chat, v_round::text, false);
    FOR v_p IN SELECT id FROM participants WHERE chat_id = v_chat AND status = 'active' ORDER BY id LOOP
      v_pos := 90;
      FOR v_prop IN SELECT id FROM propositions
                    WHERE round_id = v_round AND participant_id <> v_p.id ORDER BY id LOOP
        INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
        VALUES (v_prop.id, v_p.id, v_round, v_pos);
        v_pos := v_pos - 40;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;

SELECT ok((SELECT completed_at IS NOT NULL FROM rounds
           WHERE id = current_setting('test.rating_round_' || current_setting('test.cad'))::bigint),
          'W6 CAD: rating completion closed the round (real early-advance path)');
SELECT is((SELECT phase FROM rounds WHERE id = pg_temp.round_of(current_setting('test.cad')::int)),
          'proposing', 'W6 CAD: next round created in proposing');
SELECT ok(pg_temp.round_of(current_setting('test.cad')::int)
          <> current_setting('test.rating_round_' || current_setting('test.cad'))::bigint,
          'W6 CAD: the latest round IS a new round');
SELECT is(pg_temp.ends_of(current_setting('test.cad')::int),
          current_setting('test.anchor')::timestamptz,
          'W6 CAD: next round''s deadline snapped to the anchor instant');
SELECT ok(pg_temp.ends_of(current_setting('test.cad')::int) > now(),
          'W6 CAD invariant (a): phase_ends_at > now()');
SELECT ok(pg_temp.on_grid(pg_temp.ends_of(current_setting('test.cad')::int),
                          current_setting('test.anchor')::timestamptz, 'America/New_York'),
          'W6 CAD invariant (b): on the grid');
SELECT is(pg_temp.ends_of(current_setting('test.nul')::int),
          calculate_round_minute_end(43200),
          'W6 NUL invariant (c): next round deadline byte-identical to create_round_for_cycle''s computation');
SELECT ok(pg_temp.ends_of(current_setting('test.nul')::int) > now(),
          'W6 NUL invariant (a): phase_ends_at > now()');

-- --- NC2: runway negative control on CADR --------------------------------------
-- Swap in a variant WITHOUT the minimum-runway skip: a waiting->proposing
-- advance on CADR (whose next grid point is 30min out) lands on the sliver
-- boundary. Restore the real fn -> it skips to anchor2 + 12h.
DO $$
DECLARE
  v_r BIGINT := pg_temp.round_of(current_setting('test.cadr')::int);
  v_real_def TEXT := pg_get_functiondef('public.snap_phase_end_to_cadence()'::regprocedure);
BEGIN
  -- Broken variant: NO runway skip.
  CREATE OR REPLACE FUNCTION public.snap_phase_end_to_cadence()
  RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
  DECLARE
    v_anchor TIMESTAMPTZ; v_tz_raw TEXT; v_prop INT; v_rate INT;
    v_tz TEXT; v_local TIME; v_from TIMESTAMPTZ; v_next TIMESTAMPTZ;
  BEGIN
    IF NEW.phase_ends_at IS NULL THEN RETURN NEW; END IF;
    SELECT c.cadence_anchor_at, c.schedule_timezone,
           c.proposing_duration_seconds, c.rating_duration_seconds
      INTO v_anchor, v_tz_raw, v_prop, v_rate
    FROM public.cycles cy JOIN public.chats c ON c.id = cy.chat_id
    WHERE cy.id = NEW.cycle_id;
    IF v_anchor IS NULL OR v_prop IS DISTINCT FROM v_rate
       OR v_prop IS NULL OR v_prop <= 0 OR 86400 % v_prop <> 0 THEN RETURN NEW; END IF;
    v_tz := public.safe_timezone(v_tz_raw);
    v_local := (v_anchor AT TIME ZONE v_tz)::time;
    v_from := GREATEST(now(), COALESCE(NEW.phase_started_at, now()));
    v_next := public.next_cadence_boundary(v_from, v_tz, v_local, v_prop);
    -- (runway skip deliberately REMOVED)
    NEW.phase_ends_at := v_next;
    RETURN NEW;
  END; $fn$;

  -- Writer under the broken variant (waiting->proposing advance shape).
  UPDATE rounds SET phase = 'waiting', phase_started_at = NULL, phase_ends_at = NULL WHERE id = v_r;
  UPDATE rounds SET phase = 'proposing', phase_started_at = now(),
                    phase_ends_at = now() + interval '12 hours' WHERE id = v_r;
  PERFORM set_config('test.nc2_broken_ends',
    (SELECT phase_ends_at::text FROM rounds WHERE id = v_r), false);

  -- Restore the REAL function and redo the writer.
  EXECUTE v_real_def;
  UPDATE rounds SET phase = 'waiting', phase_started_at = NULL, phase_ends_at = NULL WHERE id = v_r;
  UPDATE rounds SET phase = 'proposing', phase_started_at = now(),
                    phase_ends_at = now() + interval '12 hours' WHERE id = v_r;
END $$;

SELECT is(current_setting('test.nc2_broken_ends')::timestamptz,
          current_setting('test.anchor2')::timestamptz,
          'NC2: NEGATIVE CONTROL — without the runway skip the writer lands on the 30min sliver boundary (assertion would fail)');
SELECT is(pg_temp.ends_of(current_setting('test.cadr')::int),
          current_setting('test.anchor2')::timestamptz + interval '12 hours',
          'NC2: restored engine skips the sliver to the following grid point');

SELECT * FROM finish();
ROLLBACK;
