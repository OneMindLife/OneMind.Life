-- Backend auto-advance for quick chats.
--
-- Auto-advance used to live in the host's BROWSER (Voting.tsx autoEndedRef,
-- LeaderChallenge.tsx autoAdvancedRef) — which means the round only advances
-- while the host's tab is open. If the host closes it, the group is stranded
-- (the exact failure that killed chat 817's 15-person group). This moves the
-- logic to backend triggers so a round advances regardless of who's looking.
--
-- Design (per the assembly rule in docs/AUTO_ADVANCE_DESIGN.md):
--   • R1 proposing stays HOST-PACED — the host's "Start voting" is the
--     "we're all here now" signal while the group is still assembling.
--   • Every phase after that AUTO-advances once everyone present is done:
--       - RATING → finalize when all eligible have voted (and ≥1 real vote).
--       - R2+ PROPOSING → when everyone has responded (challenge/affirm/skip):
--           no challengers → the carried leader wins unchallenged (converge);
--           ≥1 challenger  → open rating.
--
-- Only QUICK chats (max_cycles = 1) are affected. Continuous chats keep their
-- existing timer/threshold flow untouched.

-- 1. RATING auto-finalize. Generalize the old preview-only finalize to all quick
--    chats, and add the "≥1 real vote" guard (a round where everyone could only
--    see their own idea must not finalize into a meaningless winner — mirrors
--    the host's manual end-gate).
CREATE OR REPLACE FUNCTION public.matches_preview_maybe_finalize()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_round_id    BIGINT := NEW.round_id;
  v_phase       TEXT;
  v_completed   TIMESTAMPTZ;
  v_chat_id     BIGINT;
  v_rating_mode TEXT;
  v_max_cycles  INTEGER;
  v_is_preview  BOOLEAN;
  v_done        INTEGER;
  v_eligible    INTEGER;
  v_votes       INTEGER;
BEGIN
  -- Serialize concurrent completions so two simultaneous "last" raters don't
  -- both race into complete_round_with_winner.
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, c.chat_id, ch.rating_mode, ch.max_cycles, ch.is_preview
    INTO v_phase, v_completed, v_chat_id, v_rating_mode, v_max_cycles, v_is_preview
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  -- Quick-chat (max_cycles = 1) matches RATING rounds, still open.
  IF v_phase <> 'rating'
     OR v_completed IS NOT NULL
     OR v_rating_mode <> 'matches'
     OR v_max_cycles IS DISTINCT FROM 1 THEN
    RETURN NEW;
  END IF;

  -- done = distinct raters across all three completion signals.
  SELECT COUNT(*) INTO v_done FROM (
    SELECT participant_id FROM rating_completions WHERE round_id = v_round_id AND participant_id IS NOT NULL
    UNION
    SELECT gr.participant_id FROM grid_rankings gr
      JOIN propositions p ON p.id = gr.proposition_id
      WHERE p.round_id = v_round_id
    UNION
    SELECT participant_id FROM rating_skips WHERE round_id = v_round_id
  ) u;

  v_eligible := get_rating_eligible_count(v_chat_id);

  -- Real (non-skip) votes cast this round.
  SELECT COUNT(*) INTO v_votes
  FROM pairwise_comparisons
  WHERE round_id = v_round_id AND COALESCE(is_skip, false) = false;

  -- A REAL multi-user round needs ≥1 real vote to finalize (a 0-vote round —
  -- everyone could only see their own idea — must not crown a meaningless
  -- winner). A solo PREVIEW self-test keeps finalizing on completion as before.
  IF v_eligible > 0 AND v_done >= v_eligible
     AND (v_is_preview IS TRUE OR v_votes >= 1) THEN
    PERFORM complete_round_with_winner(v_round_id);
  END IF;

  RETURN NEW;
END;
$function$;

-- 2. R2+ PROPOSING auto-advance. New trigger: for quick chats in proposing with
--    custom_id > 1 (R1 is host-paced), once everyone present has responded,
--    converge (no challengers) or open rating (≥1 challenger).
CREATE OR REPLACE FUNCTION public.maybe_auto_advance_quick_proposing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_round_id   BIGINT := NEW.round_id;
  v_phase      TEXT;
  v_completed  TIMESTAMPTZ;
  v_custom_id  INTEGER;
  v_chat_id    BIGINT;
  v_max_cycles INTEGER;
  v_active     INTEGER;
  v_challenges INTEGER;
  v_affirms    INTEGER;
  v_skips      INTEGER;
  v_responses  INTEGER;
  v_carried_id BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(v_round_id);

  SELECT r.phase, r.completed_at, r.custom_id, c.chat_id, ch.max_cycles
    INTO v_phase, v_completed, v_custom_id, v_chat_id, v_max_cycles
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = v_round_id;

  -- Quick chats only; proposing; NOT round 1 (assembly = host-paced); still open.
  IF v_max_cycles IS DISTINCT FROM 1
     OR v_phase <> 'proposing'
     OR v_custom_id <= 1
     OR v_completed IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- A sibling transaction may have already resolved the round.
  IF EXISTS (SELECT 1 FROM round_winners WHERE round_id = v_round_id) THEN
    RETURN NEW;
  END IF;

  v_active := get_rating_eligible_count(v_chat_id);  -- active participants

  -- A "response" = a new challenger idea, a keep (affirmation), or a skip.
  SELECT COUNT(*) INTO v_challenges
  FROM propositions
  WHERE round_id = v_round_id AND carried_from_id IS NULL AND participant_id IS NOT NULL;
  SELECT COUNT(*) INTO v_affirms FROM affirmations WHERE round_id = v_round_id;
  SELECT COUNT(*) INTO v_skips   FROM round_skips  WHERE round_id = v_round_id;
  v_responses := v_challenges + v_affirms + v_skips;

  -- Everyone present has responded, and the ≥2 floor is met (a lone host doesn't
  -- advance — mirrors the frontend NEED_RESPONSES gate).
  IF v_active < 1 OR v_responses < v_active OR v_responses < 2 THEN
    RETURN NEW;
  END IF;

  IF v_challenges = 0 THEN
    -- Nobody challenged → the carried leader wins unchallenged → converge.
    SELECT id INTO v_carried_id
    FROM propositions
    WHERE round_id = v_round_id AND carried_from_id IS NOT NULL
    ORDER BY created_at ASC
    LIMIT 1;
    IF v_carried_id IS NOT NULL THEN
      PERFORM resolve_carried_winner_for_round(v_round_id, v_carried_id);
    END IF;
  ELSE
    -- At least one challenger → open rating.
    UPDATE rounds
    SET phase = 'rating', phase_started_at = NOW()
    WHERE id = v_round_id AND phase = 'proposing';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_auto_advance_quick_prop_proposition ON public.propositions;
CREATE TRIGGER trg_auto_advance_quick_prop_proposition
  AFTER INSERT ON public.propositions
  FOR EACH ROW EXECUTE FUNCTION public.maybe_auto_advance_quick_proposing();

DROP TRIGGER IF EXISTS trg_auto_advance_quick_prop_affirmation ON public.affirmations;
CREATE TRIGGER trg_auto_advance_quick_prop_affirmation
  AFTER INSERT ON public.affirmations
  FOR EACH ROW EXECUTE FUNCTION public.maybe_auto_advance_quick_proposing();

DROP TRIGGER IF EXISTS trg_auto_advance_quick_prop_skip ON public.round_skips;
CREATE TRIGGER trg_auto_advance_quick_prop_skip
  AFTER INSERT ON public.round_skips
  FOR EACH ROW EXECUTE FUNCTION public.maybe_auto_advance_quick_proposing();
