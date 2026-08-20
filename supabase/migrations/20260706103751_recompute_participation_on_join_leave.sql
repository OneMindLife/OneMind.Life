-- =============================================================================
-- Recompute rounds.participation_percent when a participant joins or leaves.
-- =============================================================================
-- Background
-- ----------
-- rounds.participation_percent is a denormalized progress column maintained by
-- recompute_round_participation_percent(round_id). Its DENOMINATOR is
--   v_total = COUNT(*) FROM participants WHERE chat_id = X AND status = 'active'
-- (see 20260502170000 / CSI-aware body in 20260704160000).
--
-- The recompute already fires on every event that changes the NUMERATOR
-- (propositions, round_skips, rating_skips, affirmations, rating_count) and on
-- phase change. But nothing fired when the DENOMINATOR changed — i.e. when a
-- participant joined (status → active) or left (status → left / row deleted).
--
-- Symptom observed on prod chat 1185 (2026-07-06): 5 of 6 had proposed → column
-- read 83%; a 7th participant then JOINED, making the real rate 5/7 = 71%, but
-- the column stayed at 83% until the next proposition/skip/affirm event fired a
-- recompute. The progress bar showed a stale, too-high number.
--
-- Fix
-- ---
-- Add a trigger on participants that recomputes the chat's currently-tracked
-- round (phase proposing|rating, not yet completed) on:
--   * INSERT               — a new joiner (or a re-join that INSERTs a row)
--   * UPDATE OF status     — active↔left↔kicked↔pending (denominator changes)
--   * DELETE               — hard leave
--
-- This is DISPLAY-ONLY: it updates the participation_percent column. It does NOT
-- decide phase advancement (that lives in check_early_advance_* / process-timers
-- and is unaffected). Joins/leaves are low-frequency relative to grid placements,
-- so this does not reintroduce the rating cascade — the recompute is a single
-- indexed count over the active round, gated to at most one tracked round.
--
-- SECURITY DEFINER (SET search_path) is REQUIRED: the trigger's cross-table
-- UPDATE on rounds runs from user-initiated participants DML (join = INSERT as
-- authenticated). Without DEFINER the UPDATE is silently RLS-filtered to zero
-- rows (rounds has no UPDATE policy for authenticated) — the exact silent no-op
-- documented in feedback_trigger_security_definer.md. The recompute helper it
-- calls is itself DEFINER; this wrapper mirrors the sibling refresh_* wrappers.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.refresh_round_participation_from_participant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_chat_id BIGINT := COALESCE(NEW.chat_id, OLD.chat_id);
BEGIN
  -- Recompute every non-completed proposing/rating round for this chat.
  -- Normally there is exactly one such round; PERFORM ... FROM invokes the
  -- helper once per matching row (zero rows = no-op, e.g. chat not started).
  PERFORM public.recompute_round_participation_percent(r.id)
  FROM public.rounds r
  JOIN public.cycles cy ON cy.id = r.cycle_id
  WHERE cy.chat_id = v_chat_id
    AND r.completed_at IS NULL
    AND r.phase IN ('proposing', 'rating');
  RETURN NULL;
END;
$$;

-- INSERT (join) + DELETE (hard leave): always recompute.
DROP TRIGGER IF EXISTS sync_round_participation_participant_ins_del ON public.participants;
CREATE TRIGGER sync_round_participation_participant_ins_del
AFTER INSERT OR DELETE ON public.participants
FOR EACH ROW EXECUTE FUNCTION public.refresh_round_participation_from_participant();

-- UPDATE OF status (leave / kick / approve): recompute only when status actually
-- changed, so unrelated column updates (display_name, viewing_language_code,
-- agent_role, …) don't trigger needless recomputes.
DROP TRIGGER IF EXISTS sync_round_participation_participant_status ON public.participants;
CREATE TRIGGER sync_round_participation_participant_status
AFTER UPDATE OF status ON public.participants
FOR EACH ROW
WHEN (NEW.status IS DISTINCT FROM OLD.status)
EXECUTE FUNCTION public.refresh_round_participation_from_participant();

-- =============================================================================
-- Backfill: recompute every currently-tracked round so any round whose column
-- drifted from a past join/leave (like chat 1185) is corrected on rollout.
-- =============================================================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT id FROM public.rounds
    WHERE completed_at IS NULL AND phase IN ('proposing', 'rating')
  LOOP
    PERFORM public.recompute_round_participation_percent(r.id);
  END LOOP;
END $$;
