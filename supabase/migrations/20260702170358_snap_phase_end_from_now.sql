-- ============================================================================
-- HOTFIX: snap_phase_end_to_clock must never produce a deadline in the past
-- ============================================================================
-- Bug (found 2026-07-02 by an adversarial review of the clock-aligned design;
-- see the "clock-aligned redesign" Notion task):
--
--   The snap trigger computed the boundary as
--       next_clock_boundary(COALESCE(NEW.phase_started_at, now()), tz)
--   i.e. "the next 3am/3pm strictly after the PHASE START". Two live writers
--   update phase_ends_at WITHOUT touching phase_started_at:
--
--   1. process-timers extendTimer (supabase/functions/process-timers/
--      index.ts): when a phase expires with its minimum unmet, it re-arms
--      phase_ends_at = now() + full duration. On a clock-aligned chat the
--      snap recomputed the boundary from the UNCHANGED phase_started_at —
--      which is the boundary that just passed. Result: the "extension" was
--      overridden to an already-past instant, the round stayed expired, and
--      the expire→extend→re-pin loop repeated EVERY CRON MINUTE (a rounds
--      UPDATE + Realtime broadcast to every viewer, forever).
--
--   2. host_resume_chat: restores phase_ends_at from the banked
--      phase_time_remaining_seconds but leaves phase_started_at at its
--      original pre-pause value. Resuming after a boundary passed pinned the
--      deadline into the past — banked time destroyed, phase instantly
--      expired (then entered loop #1 if the minimum was unmet).
--
-- Fix (one clause): compute the boundary from
--       GREATEST(now(), COALESCE(NEW.phase_started_at, now()))
-- A deadline's reference instant is "no earlier than now" by definition — a
-- freshly written phase end must land in the future. Semantics per writer:
--   * Normal advances (phase_started_at = now() in the same tx): unchanged.
--   * Extensions: become "held over to the NEXT boundary" — one write per
--     12h window instead of one per minute, and the timer reads correctly.
--   * Host/schedule resume across a boundary: lands on the NEXT boundary
--     (the ambient-cadence interpretation of "resume") instead of the past.
--
-- This is deliberately the smallest safe change: the fuller redesign
-- (explicit user-chosen cadence anchor replacing the hardcoded 3am/3pm and
-- the hidden 43200 gate) is specced in the Notion task and subsumes this.
-- Tests: supabase/tests/131_clock_aligned_phase_cadence_test.sql (T7 made
-- deterministic against transaction now(); T11-T13 pin the regression).
-- ============================================================================

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
    -- Reference instant = GREATEST(now(), phase_started_at): a deadline being
    -- written now must land strictly in the future. Writers that update
    -- phase_ends_at without touching phase_started_at (timer extension on
    -- unmet minimums, host/schedule resume) previously re-derived the
    -- ALREADY-PAST boundary from the stale start and pinned the round
    -- expired forever. (GREATEST ignores NULLs, but keep COALESCE for
    -- explicitness.)
    NEW.phase_ends_at := public.next_clock_boundary(
      GREATEST(now(), COALESCE(NEW.phase_started_at, now())),
      v_tz
    );
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.snap_phase_end_to_clock IS
  'BEFORE-row trigger: for clock_aligned 12h chats, snaps NEW.phase_ends_at to the next 3 AM/3 PM boundary strictly after GREATEST(now(), phase_started_at) — never into the past (extension/resume writers leave phase_started_at stale). No-op otherwise.';
