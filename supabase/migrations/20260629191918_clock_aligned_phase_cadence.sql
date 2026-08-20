-- ============================================================================
-- Clock-aligned phase cadence (3 AM / 3 PM)
-- ============================================================================
-- Goal: for opted-in 12h "ambient" chats, phase flips land on a daily
-- 3 AM / 3 PM cadence in the chat's local timezone — WITHOUT making anyone wait
-- for a future start time (the chat still begins immediately; the first phase is
-- just shorter, ending at the next boundary).
--
-- Design: rather than edit the ~15 places that compute `rounds.phase_ends_at`
-- (the timer-expiry advance, the early-advance trigger variants, auto-start,
-- schedule-resume, host-pause), we intercept at a SINGLE point — a BEFORE
-- INSERT/UPDATE trigger on `rounds` that overrides whatever value was computed
-- with the next 3 AM/3 PM grid boundary. This is:
--   * Contained: touches zero existing timer functions.
--   * Safe by default: `clock_aligned` defaults FALSE, so this is a complete
--     no-op for every existing chat and every non-ambient chat (quick-create,
--     game mode, the wedge, etc.). It only acts on opted-in 12h chats.
--   * Drift-free: every phase re-snaps to the grid, so cron lag never
--     accumulates across flips.
-- ============================================================================

-- STEP 1: opt-in flag. Default FALSE => unchanged behavior everywhere.
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS clock_aligned BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.chats.clock_aligned IS
  'When true (12h ambient chats only), phase ends snap to the next 3 AM/3 PM '
  'boundary in the chat timezone so flips land on a daily cadence. Default '
  'false = no snapping; all other chats are unaffected.';

-- ============================================================================
-- STEP 2: next 3 AM / 3 PM boundary in a timezone, strictly after an instant.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.next_clock_boundary(
  p_after TIMESTAMPTZ,
  p_tz    TEXT
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_tz        TEXT := COALESCE(NULLIF(p_tz, ''), 'UTC');
  v_local_day DATE := (p_after AT TIME ZONE v_tz)::date;
  v_cand      TIMESTAMPTZ;
BEGIN
  -- Candidates (ascending): today 03:00, today 15:00, tomorrow 03:00 — local
  -- wall time converted to a UTC instant. Return the first strictly after
  -- p_after. These three always bracket any p_after.
  FOREACH v_cand IN ARRAY ARRAY[
    ((v_local_day        + TIME '03:00') AT TIME ZONE v_tz),
    ((v_local_day        + TIME '15:00') AT TIME ZONE v_tz),
    (((v_local_day + 1)  + TIME '03:00') AT TIME ZONE v_tz)
  ]
  LOOP
    IF v_cand > p_after THEN
      RETURN v_cand;
    END IF;
  END LOOP;
  -- Unreachable in practice; keep the engine moving if a DST edge slips through.
  RETURN p_after + INTERVAL '12 hours';
END;
$$;

COMMENT ON FUNCTION public.next_clock_boundary IS
  'Next 03:00 or 15:00 boundary (in p_tz local time) strictly after p_after, as a UTC instant.';

-- ============================================================================
-- STEP 3: the single interception trigger on rounds.
-- ============================================================================
-- SECURITY DEFINER so it can read chats regardless of the writer's RLS context
-- (and so the trigger-security audit, which only flags NON-DEFINER cross-table
-- DML, leaves it alone). It performs NO cross-table DML — it only rewrites
-- NEW.phase_ends_at.
CREATE OR REPLACE FUNCTION public.snap_phase_end_to_clock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_aligned BOOLEAN;
  v_tz      TEXT;
  v_prop    INT;
  v_rate    INT;
BEGIN
  -- Nothing to align if this write doesn't set an active phase end.
  IF NEW.phase_ends_at IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.clock_aligned, c.schedule_timezone,
         c.proposing_duration_seconds, c.rating_duration_seconds
    INTO v_aligned, v_tz, v_prop, v_rate
  FROM public.cycles cy
  JOIN public.chats  c ON c.id = cy.chat_id
  WHERE cy.id = NEW.cycle_id;

  -- Only opted-in chats, and only when phases are 12h (the 3 AM/3 PM grid is
  -- defined for 12h). Anything else keeps the value the timer logic computed.
  IF v_aligned IS TRUE
     AND v_prop = 43200
     AND v_rate = 43200 THEN
    NEW.phase_ends_at := public.next_clock_boundary(
      COALESCE(NEW.phase_started_at, now()),
      v_tz
    );
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.snap_phase_end_to_clock IS
  'BEFORE-row trigger: for clock_aligned 12h chats, snaps NEW.phase_ends_at to the next 3 AM/3 PM boundary. No-op otherwise.';

DROP TRIGGER IF EXISTS snap_phase_end_to_clock_trg ON public.rounds;
CREATE TRIGGER snap_phase_end_to_clock_trg
  BEFORE INSERT OR UPDATE OF phase_ends_at ON public.rounds
  FOR EACH ROW
  EXECUTE FUNCTION public.snap_phase_end_to_clock();

COMMENT ON TRIGGER snap_phase_end_to_clock_trg ON public.rounds IS
  'Snaps phase ends to the 3 AM/3 PM grid for opted-in 12h chats; no-op for all others (clock_aligned default false).';
