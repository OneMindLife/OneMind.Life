-- =============================================================================
-- Deadline rules for CONTINUOUS-chat proposing rounds that would otherwise
-- extend forever.
--
-- Today, when a proposing timer expires below proposing_minimum, process-timers
-- extends the phase — indefinitely. In a low-traffic chat a carried leader with
-- affirmations ("No, I can't think of something better") but no/few challengers
-- can never satisfy the minimum, so the round stalls (observed: official chat
-- round stuck 3+ days on 12h phases).
--
-- Quick chats already resolve this ("no challengers → carried leader wins
-- unchallenged", maybe_auto_advance_quick_proposing, 20260624030000) but that
-- trigger requires everyone-present to respond and is gated to max_cycles = 1.
-- The all-affirm trigger (maybe_auto_resolve_affirm_round) covers continuous
-- chats only when EVERY active participant affirms/skips — unreachable with a
-- large dormant roster.
--
-- This adds the deadline-based fallback, called by process-timers at timer
-- expiry INSTEAD of extending, when all gates pass:
--
--   Gates (all required, else 'none' → caller extends as before):
--     • continuous chat (max_cycles IS DISTINCT FROM 1); manual mode excluded
--     • round is proposing, still open, no winner yet
--     • a carried-forward proposition exists (R2+ — R1 keeps strict minimums)
--     • grace elapsed: NOW() >= phase_started_at + 2 × proposing_duration
--       (one full extension window where "Can you beat it?" was visible;
--       extendTimer only moves phase_ends_at, so phase_started_at anchors this)
--
--   Then:
--     • 0 challengers AND >= 1 NON-AUTHOR affirm  → carried leader wins
--       unchallenged (resolve_carried_winner_for_round) — the parliamentary
--       "seconded and unopposed at the deadline" rule. The carried author's own
--       affirm does NOT count (no self-ratified wins in a dead chat).
--     • >= 2 challengers                          → open rating: carried + 2 is
--       a full votable set for everyone even under strict self-exclusion.
--     • 1 challenger AND >= 1 non-author affirm   → open rating: 2 props are
--       votable under conditional self-inclusion, and the affirmer is proof an
--       engaged non-author rater exists (without one, rating would stall at
--       avg 1 rater < rating_minimum).
--     • otherwise                                 → 'none' (dead or author-only
--       round: keep extending; abandonment is auto-pause/cleanup's job).
--
-- "Challenger" = new HUMAN proposition (carried_from_id IS NULL AND
-- participant_id IS NOT NULL) — same definition as checkMinimumMet and the
-- quick-chat trigger.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.maybe_resolve_expired_proposing(p_round_id BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_phase             TEXT;
  v_completed         TIMESTAMPTZ;
  v_phase_started_at  TIMESTAMPTZ;
  v_chat_id           BIGINT;
  v_max_cycles        INTEGER;
  v_start_mode        TEXT;
  v_rating_start_mode TEXT;
  v_proposing_secs    INTEGER;
  v_rating_secs       INTEGER;
  v_carried_id        BIGINT;
  v_carried_author    BIGINT;
  v_challengers       INTEGER;
  v_non_author_affirms INTEGER;
  v_new_ends_at       TIMESTAMPTZ;
BEGIN
  PERFORM pg_advisory_xact_lock(p_round_id);

  SELECT r.phase, r.completed_at, r.phase_started_at, cy.chat_id,
         ch.max_cycles, ch.start_mode, ch.rating_start_mode,
         ch.proposing_duration_seconds, ch.rating_duration_seconds
    INTO v_phase, v_completed, v_phase_started_at, v_chat_id,
         v_max_cycles, v_start_mode, v_rating_start_mode,
         v_proposing_secs, v_rating_secs
  FROM rounds r
  JOIN cycles cy ON cy.id = r.cycle_id
  JOIN chats ch ON ch.id = cy.chat_id
  WHERE r.id = p_round_id;

  IF NOT FOUND
     OR v_max_cycles IS NOT DISTINCT FROM 1   -- quick chats have their own flow
     OR v_start_mode = 'manual'
     OR v_phase <> 'proposing'
     OR v_completed IS NOT NULL THEN
    RETURN 'none';
  END IF;

  -- A sibling transaction may have already resolved the round.
  IF EXISTS (SELECT 1 FROM round_winners WHERE round_id = p_round_id) THEN
    RETURN 'none';
  END IF;

  -- R2+ only: the rules are about a carried leader surviving its challenge
  -- window. R1 (no carried prop) keeps the existing extend-until-minimum flow.
  SELECT id, participant_id INTO v_carried_id, v_carried_author
  FROM propositions
  WHERE round_id = p_round_id AND carried_from_id IS NOT NULL
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_carried_id IS NULL THEN
    RETURN 'none';
  END IF;

  -- Grace: at least one full extension window must have passed.
  IF v_phase_started_at IS NULL
     OR NOW() < v_phase_started_at
        + make_interval(secs => 2 * COALESCE(v_proposing_secs, 0))
     OR COALESCE(v_proposing_secs, 0) <= 0 THEN
    RETURN 'none';
  END IF;

  SELECT COUNT(*) INTO v_challengers
  FROM propositions
  WHERE round_id = p_round_id
    AND carried_from_id IS NULL
    AND participant_id IS NOT NULL;

  -- The carried author's own affirm doesn't count as "the second"
  -- (affirm_round permits it — its my-submissions check ignores carried rows).
  SELECT COUNT(*) INTO v_non_author_affirms
  FROM affirmations a
  WHERE a.round_id = p_round_id
    AND (v_carried_author IS NULL OR a.participant_id <> v_carried_author);

  IF v_challengers = 0 THEN
    IF v_non_author_affirms >= 1 THEN
      -- Seconded and unopposed at the deadline → the leader keeps, recorded as
      -- an unchallenged (sole) win. on_round_winner_set handles convergence
      -- counting and next-round creation.
      PERFORM resolve_carried_winner_for_round(p_round_id, v_carried_id);
      RETURN 'converged';
    END IF;
    RETURN 'none';
  END IF;

  IF v_challengers >= 2 OR v_non_author_affirms >= 1 THEN
    -- Votable set exists (and with a single challenger, the non-author
    -- affirmer proves an engaged rater exists). Open rating; mirror the
    -- early-advance triggers' rating_start_mode handling.
    IF COALESCE(v_rating_start_mode, 'auto') = 'auto' THEN
      -- Snap to the next whole minute for cron alignment.
      v_new_ends_at := to_timestamp(
        CEIL(EXTRACT(EPOCH FROM (NOW() + make_interval(secs => COALESCE(v_rating_secs, 0)))) / 60.0) * 60
      );
      UPDATE rounds
      SET phase = 'rating',
          phase_started_at = NOW(),
          phase_ends_at = v_new_ends_at
      WHERE id = p_round_id AND phase = 'proposing';
    ELSE
      UPDATE rounds
      SET phase = 'waiting',
          phase_started_at = NOW(),
          phase_ends_at = NULL
      WHERE id = p_round_id AND phase = 'proposing';
    END IF;
    RETURN 'advanced';
  END IF;

  RETURN 'none';
END;
$$;

ALTER FUNCTION public.maybe_resolve_expired_proposing(BIGINT) OWNER TO postgres;

COMMENT ON FUNCTION public.maybe_resolve_expired_proposing IS
'Deadline fallback for continuous-chat proposing rounds, called by
process-timers at timer expiry before extending. R2+ only, after a grace of
2x proposing duration since phase start: 0 challengers + >=1 non-author affirm
-> carried leader wins unchallenged (converged); >=2 challengers, or 1
challenger + >=1 non-author affirm -> open rating (advanced); otherwise none
(caller extends as before).';

-- Cron/service path only — not a client-facing RPC.
REVOKE EXECUTE ON FUNCTION public.maybe_resolve_expired_proposing(BIGINT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.maybe_resolve_expired_proposing(BIGINT) TO service_role;
