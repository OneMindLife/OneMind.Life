-- ============================================================================
-- Cadence anchor engine (Design C) — replaces the v1 "clock_aligned" feature
-- ============================================================================
-- Spec: docs/CADENCE_ANCHOR_SPEC.md (APPROVED 2026-07-02). Supersedes
--   20260629191918_clock_aligned_phase_cadence.sql  (v1 engine)
--   20260702170358_snap_phase_end_from_now.sql      (v1 hotfix, GREATEST(now()))
--
-- v1 post-mortem (why this exists):
--   * silent override of the user's stated durations (hidden 3am/3pm grid)
--   * hidden 43200-only gating the user never saw
--   * extension/resume writers pinned deadlines into the past (hotfixed)
--   * adaptive durations silently disarmed the grid
--   * a garbage timezone raised inside the trigger and aborted ALL rounds
--     writes for the chat
--
-- Design C: the cadence is EXPLICIT USER DATA. `chats.cadence_anchor_at`
-- (nullable) is the user-chosen end of the FIRST phase; the repeating grid is
-- {anchor's local time-of-day + n × duration} in `schedule_timezone`.
-- NULL anchor (the default) = no cadence: phases chain plainly.
-- `chats.clock_aligned` is KEPT but DEPRECATED (iOS build 20.2.0 in App Store
-- review still inserts it — a compat shim translates old-client inserts).
--
-- This migration must work BOTH applied on top of a DB that already ran the
-- v1 migrations AND in a fresh full replay — hence IF EXISTS / OR REPLACE.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: the anchor column — stored user intent, default NULL (no cadence).
-- ----------------------------------------------------------------------------
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS cadence_anchor_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.chats.cadence_anchor_at IS
  'User-chosen end of the FIRST phase. Non-null = phase ends snap to the '
  'repeating grid {anchor local time-of-day + n x phase duration} in '
  'schedule_timezone. NULL (default) = no cadence; phases chain plainly '
  '(end = start + duration). Requires equal proposing/rating durations that '
  'divide 24h, and adaptive_duration_enabled = false (enforced loudly by '
  'chats_cadence_guard_trg + chats_cadence_adaptive_excl).';

COMMENT ON COLUMN public.chats.clock_aligned IS
  'DEPRECATED (v1 clock-aligned feature). The engine ignores this column; it '
  'is kept only because the iOS build 20.2.0 in App Store review inserts it. '
  'chats_cadence_compat_shim_trg translates old-client inserts into '
  'cadence_anchor_at. Removable once pre-cadence clients age out.';

-- ----------------------------------------------------------------------------
-- STEP 2: safe_timezone() — never raise on a garbage tz (v1 tz-crash fix).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.safe_timezone(p TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_tz TEXT := COALESCE(NULLIF(p, ''), 'UTC');
BEGIN
  -- Probe: PostgreSQL raises on unknown zone names. A garbage tz must
  -- degrade to UTC, never abort the caller (v1 aborted ALL rounds writes
  -- for the chat, including user rating inserts).
  BEGIN
    PERFORM now() AT TIME ZONE v_tz;
    RETURN v_tz;
  EXCEPTION WHEN OTHERS THEN
    RETURN 'UTC';
  END;
END;
$$;

COMMENT ON FUNCTION public.safe_timezone(TEXT) IS
  'Returns p if PostgreSQL accepts it as a time zone (NULL/empty -> UTC), '
  'else UTC. Never raises — a garbage tz must not abort trigger callers.';

-- ----------------------------------------------------------------------------
-- STEP 3: next_cadence_boundary() — generalization of v1 next_clock_boundary.
-- ----------------------------------------------------------------------------
-- Grid = the anchor''s local time-of-day stepped by p_step_seconds, wrapping
-- mod 24h, evaluated as LOCAL WALL TIME in p_tz. Wall-clock construction
-- keeps the grid DST-stable: the same local times year-round; DST transition
-- days produce one 11h/13h phase — accepted and documented.
CREATE OR REPLACE FUNCTION public.next_cadence_boundary(
  p_after        TIMESTAMPTZ,
  p_tz           TEXT,
  p_anchor_local TIME,
  p_step_seconds INT
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_tz          TEXT := public.safe_timezone(p_tz);
  v_local_day   DATE := (p_after AT TIME ZONE v_tz)::date;
  v_anchor_secs INT  := EXTRACT(EPOCH FROM p_anchor_local)::INT;
  v_n           INT;
  v_day         DATE;
  v_k           INT;
  v_cand        TIMESTAMPTZ;
  v_best        TIMESTAMPTZ := NULL;
BEGIN
  IF p_after IS NULL OR p_anchor_local IS NULL
     OR p_step_seconds IS NULL OR p_step_seconds <= 0 THEN
    RETURN NULL;
  END IF;

  v_n := GREATEST(86400 / p_step_seconds, 1);

  -- Candidates: local days d and d+1, each carrying the full day's grid
  -- times {(anchor + k*step) mod 24h : k in [0, N)}. The mod-wrap keeps
  -- pre-anchor times of day in the set (e.g. anchor 15:00, step 12h ->
  -- {03:00, 15:00} on BOTH days), and day d+1 guarantees a candidate
  -- strictly after any p_after with local day d.
  FOR v_day IN SELECT unnest(ARRAY[v_local_day, v_local_day + 1]) LOOP
    FOR v_k IN 0 .. v_n - 1 LOOP
      v_cand := (v_day::TIMESTAMP
                 + make_interval(secs => (v_anchor_secs + v_k * p_step_seconds) % 86400)
                ) AT TIME ZONE v_tz;
      IF v_cand > p_after AND (v_best IS NULL OR v_cand < v_best) THEN
        v_best := v_cand;
      END IF;
    END LOOP;
  END LOOP;

  -- Unreachable in practice (day d+1 always yields a candidate > p_after);
  -- keep the engine moving if a tz edge slips through.
  RETURN COALESCE(v_best, p_after + make_interval(secs => p_step_seconds));
END;
$$;

COMMENT ON FUNCTION public.next_cadence_boundary(TIMESTAMPTZ, TEXT, TIME, INT) IS
  'Next grid instant strictly after p_after, where the grid is the anchor '
  'local time-of-day stepped by p_step_seconds (mod 24h) as wall time in '
  'p_tz. DST-stable: same local times year-round (transition days produce '
  'one shorter/longer phase).';

-- ----------------------------------------------------------------------------
-- STEP 4: drop the three v1 objects (engine replaced wholesale).
-- ----------------------------------------------------------------------------
DROP TRIGGER  IF EXISTS snap_phase_end_to_clock_trg ON public.rounds;
DROP FUNCTION IF EXISTS public.snap_phase_end_to_clock();
DROP FUNCTION IF EXISTS public.next_clock_boundary(TIMESTAMPTZ, TEXT);

-- ----------------------------------------------------------------------------
-- STEP 5: the rewritten snap trigger — single interception point on rounds.
-- ----------------------------------------------------------------------------
-- SECURITY DEFINER: it must read chats/cycles when fired from user-DML
-- contexts under RLS (same reason as v1). It performs NO cross-table DML —
-- it only rewrites NEW.phase_ends_at.
CREATE OR REPLACE FUNCTION public.snap_phase_end_to_cadence()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_anchor TIMESTAMPTZ;
  v_tz_raw TEXT;
  v_prop   INT;
  v_rate   INT;
  v_tz     TEXT;
  v_local  TIME;
  v_from   TIMESTAMPTZ;
  v_next   TIMESTAMPTZ;
BEGIN
  -- Nothing to snap if this write doesn't set an active phase end
  -- (host pause / waiting phases write NULL).
  IF NEW.phase_ends_at IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.cadence_anchor_at, c.schedule_timezone,
         c.proposing_duration_seconds, c.rating_duration_seconds
    INTO v_anchor, v_tz_raw, v_prop, v_rate
  FROM public.cycles cy
  JOIN public.chats  c ON c.id = cy.chat_id
  WHERE cy.id = NEW.cycle_id;

  -- Gate: no anchor = no cadence (true no-op — the writer's value survives
  -- byte-identical). Incoherent durations also no-op defensively: the guard
  -- trigger makes them unreachable, but the engine must never divide by zero
  -- or emit a wandering grid if a path slips through.
  IF v_anchor IS NULL
     OR v_prop IS DISTINCT FROM v_rate
     OR v_prop IS NULL OR v_prop <= 0
     OR 86400 % v_prop <> 0 THEN
    RETURN NEW;
  END IF;

  v_tz    := public.safe_timezone(v_tz_raw);
  v_local := (v_anchor AT TIME ZONE v_tz)::time;

  -- Reference instant = GREATEST(now(), phase_started_at): a deadline being
  -- written now must land strictly in the future (the v1 hotfix, kept).
  -- Writers that update phase_ends_at without touching phase_started_at
  -- (timer extension on unmet minimums, host/schedule resume) would
  -- otherwise re-derive an ALREADY-PAST boundary from the stale start and
  -- pin the round expired forever.
  v_from := GREATEST(now(), COALESCE(NEW.phase_started_at, now()));
  v_next := public.next_cadence_boundary(v_from, v_tz, v_local, v_prop);

  -- Minimum-runway skip: never create sliver phases (early advance landing
  -- moments before a grid point). Does NOT fight user choice: the wizard
  -- enforces anchor >= now + runway at creation (spec section 5.3).
  IF v_next - v_from < LEAST(make_interval(secs => v_prop / 4.0), INTERVAL '1 hour') THEN
    v_next := public.next_cadence_boundary(v_next, v_tz, v_local, v_prop);
  END IF;

  NEW.phase_ends_at := v_next;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.snap_phase_end_to_cadence() IS
  'BEFORE-row trigger on rounds: for chats with a cadence_anchor_at, snaps '
  'NEW.phase_ends_at to the next anchor-grid boundary strictly after '
  'GREATEST(now(), phase_started_at), skipping boundaries closer than '
  'LEAST(duration/4, 1h) (sliver-phase runway). True no-op when the anchor '
  'is NULL or durations are incoherent.';

DROP TRIGGER IF EXISTS snap_phase_end_to_cadence_trg ON public.rounds;
CREATE TRIGGER snap_phase_end_to_cadence_trg
  BEFORE INSERT OR UPDATE OF phase_ends_at ON public.rounds
  FOR EACH ROW
  EXECUTE FUNCTION public.snap_phase_end_to_cadence();

COMMENT ON TRIGGER snap_phase_end_to_cadence_trg ON public.rounds IS
  'Snaps phase ends to the user-chosen cadence grid (cadence_anchor_at); '
  'no-op for chats without an anchor (the default).';

-- ----------------------------------------------------------------------------
-- STEP 6: coherence enforcement — VISIBLY, never silent (v1 sin #1).
-- ----------------------------------------------------------------------------
-- 6a. CHECK: adaptive durations and a cadence anchor are mutually exclusive
--     (adaptive mutates durations and would silently kill the grid — the v1
--     "silent disarm" bug class).
ALTER TABLE public.chats
  DROP CONSTRAINT IF EXISTS chats_cadence_adaptive_excl;
ALTER TABLE public.chats
  ADD CONSTRAINT chats_cadence_adaptive_excl
  CHECK (NOT (COALESCE(adaptive_duration_enabled, false)
              AND cadence_anchor_at IS NOT NULL));

-- 6b. Guard trigger: a non-null anchor requires equal phase durations that
--     divide 24h. Fires on INSERT and UPDATE, so post-create duration edits
--     that would break the grid fail LOUDLY instead of wandering silently.
--     Plain function (no SECURITY DEFINER): it only inspects NEW and RAISEs —
--     zero cross-table DML (allowlisted in 107_trigger_security_audit_test).
CREATE OR REPLACE FUNCTION public.chats_cadence_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.cadence_anchor_at IS NOT NULL THEN
    IF NEW.proposing_duration_seconds IS DISTINCT FROM NEW.rating_duration_seconds THEN
      RAISE EXCEPTION
        'cadence_anchor_at requires equal proposing and rating durations (got % s / % s). Clear the anchor or make the phases equal.',
        NEW.proposing_duration_seconds, NEW.rating_duration_seconds
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.proposing_duration_seconds IS NULL
       OR NEW.proposing_duration_seconds <= 0
       OR 86400 % NEW.proposing_duration_seconds <> 0 THEN
      RAISE EXCEPTION
        'cadence_anchor_at requires a phase duration that divides 24h evenly (1/2/3/4/6/8/12/24h); got % s. Clear the anchor or pick a dividing duration.',
        NEW.proposing_duration_seconds
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.chats_cadence_guard() IS
  'BEFORE-row guard on chats: a non-null cadence_anchor_at requires equal '
  'phase durations dividing 24h. RAISEs loudly (never silently disarms) — '
  'also blocks post-create duration edits that would break the grid.';

DROP TRIGGER IF EXISTS chats_cadence_guard_trg ON public.chats;
CREATE TRIGGER chats_cadence_guard_trg
  BEFORE INSERT OR UPDATE ON public.chats
  FOR EACH ROW
  EXECUTE FUNCTION public.chats_cadence_guard();

-- ----------------------------------------------------------------------------
-- STEP 7: old-client compat shim (BEFORE INSERT, fires before the guard —
--         Postgres fires same-event triggers alphabetically and
--         'chats_cadence_compat_shim_trg' < 'chats_cadence_guard_trg').
-- ----------------------------------------------------------------------------
-- The shipped iOS/Android build (20.2.0) still inserts clock_aligned = true
-- for 12h ambient chats. Translate that into the new engine's ambient
-- 3am/3pm anchor so those clients keep their behavior. Removable once
-- pre-cadence clients age out.
CREATE OR REPLACE FUNCTION public.chats_cadence_compat_shim()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.clock_aligned IS TRUE
     AND NEW.cadence_anchor_at IS NULL
     AND NEW.proposing_duration_seconds = 43200
     AND NEW.rating_duration_seconds = 43200
     -- Old clients could combine clock_aligned with adaptive (v1 silently
     -- disarmed). Setting an anchor here would trip
     -- chats_cadence_adaptive_excl and break their create — leave the
     -- anchor NULL instead (plain honest durations).
     AND NOT COALESCE(NEW.adaptive_duration_enabled, false) THEN
    NEW.cadence_anchor_at := public.next_cadence_boundary(
      now(),
      public.safe_timezone(NEW.schedule_timezone),
      TIME '03:00',
      43200
    );
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.chats_cadence_compat_shim() IS
  'BEFORE INSERT shim on chats: translates old-client (iOS 20.2.0) '
  'clock_aligned=true 12h inserts into cadence_anchor_at = next ambient '
  '3am/3pm boundary. Only inspects/sets NEW — no cross-table DML. Removable '
  'once pre-cadence clients age out.';

DROP TRIGGER IF EXISTS chats_cadence_compat_shim_trg ON public.chats;
CREATE TRIGGER chats_cadence_compat_shim_trg
  BEFORE INSERT ON public.chats
  FOR EACH ROW
  EXECUTE FUNCTION public.chats_cadence_compat_shim();

-- ----------------------------------------------------------------------------
-- STEP 8: data migration — existing clock_aligned 12h chats get the ambient
--         anchor they were already living on (2 chats in prod today; chat
--         1138 is 43200/86400 and correctly stays NULL). Idempotent: the
--         cadence_anchor_at IS NULL predicate makes re-runs no-ops.
-- ----------------------------------------------------------------------------
UPDATE public.chats
SET cadence_anchor_at = public.next_cadence_boundary(
      now(), public.safe_timezone(schedule_timezone), TIME '03:00', 43200)
WHERE clock_aligned IS TRUE
  AND proposing_duration_seconds = 43200
  AND rating_duration_seconds  = 43200
  AND cadence_anchor_at IS NULL
  -- v1 never gated on adaptive; an adaptive+clock_aligned row would violate
  -- chats_cadence_adaptive_excl. Such rows keep NULL (plain durations).
  AND NOT COALESCE(adaptive_duration_enabled, false);
