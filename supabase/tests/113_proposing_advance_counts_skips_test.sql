-- =============================================================================
-- Tests for the PROPOSING early-advance "count acted, not just submitters" change.
-- Migration: 20260530120000_proposing_advance_counts_skips.sql
--
-- The migration changed check_early_advance_on_proposition() and
-- check_early_advance_on_skip() so the COUNT threshold (proposing_threshold_count)
-- counts participants who have ACTED — submitted OR skipped OR affirmed — rather than
-- only unique submitters. The PERCENT threshold already counted skips/affirms; this
-- aligns the count threshold to the same "has acted" set.
--
--   v_count_met := (unique_submitters + skips + affirms) >= effective_count_threshold
--
-- v_minimum_met (real new propositions >= proposing_minimum) is UNCHANGED and still
-- independently gates, so this cannot advance with fewer real ideas than before.
--
-- =============================================================================
-- Coverage:
--   1. KEY DISCRIMINATING TEST. proposing_threshold_count=4, percent=NULL, funded=5,
--      proposing_minimum=3. With 3 submitters + 0 skips, OLD logic would NOT advance
--      (3 >= 4 is false) — assert round stays 'proposing'. Then a 4th DISTINCT
--      participant SKIPS: acted = 3 submitters + 1 skip = 4 >= 4 → count_met; minimum
--      still met (3 real props); percent threshold NULL → required 0 → met. Round
--      SHOULD advance to 'rating'. This only passes under the new (counts-skips) logic.
--   2. GUARD: minimum still gates. A separate chat/round with 0 real propositions and
--      a couple of skips — proposition_count (0) < proposing_minimum (3) →
--      minimum_met false → does NOT advance to rating regardless of count threshold.
--
-- Funded participants: the triggers compute v_funded_count via
-- get_funded_participant_count(round_id), which is COUNT(*) over round_funding for
-- that round. We insert one round_funding row per participant so v_funded_count is
-- exact (and never falls back to the active-participant count branch).
--
-- The skip trigger is driven by INSERT INTO round_skips; the proposition trigger by
-- INSERT INTO propositions. Both fire SECURITY DEFINER, so a plain superuser INSERT
-- exercises them faithfully.
--
-- pgtap gotchas honored: proposing_minimum >= 3 and rating_minimum >= 2 constraints;
-- grid rating mode; rating_start_mode='auto' so the advance lands on 'rating'.
--
-- Runs inside BEGIN/ROLLBACK with unique names; prod data untouched.
-- =============================================================================

BEGIN;
SELECT plan(4);

-- =============================================================================
-- SETUP (Test 1 — discriminating chat):
--   5 funded participants, proposing_threshold_count=4, percent=NULL, minimum=3.
--   Round created directly in 'proposing'. 3 distinct participants submit NEW props.
-- =============================================================================

DO $$
DECLARE
    v_chat_id   INT;
    v_cycle_id  INT;
    v_round_id  INT;
    v_p1 INT; v_p2 INT; v_p3 INT; v_p4 INT; v_p5 INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode,
        proposing_threshold_percent, proposing_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum,
        rating_start_mode
    ) VALUES (
        '113 ProposingAdvanceCountsSkips Key', 'Pick the best idea', gen_random_uuid(),
        'manual',
        NULL, 4,        -- percent NULL → count threshold is the deciding gate; count=4
        300, 60,
        3, 2,
        'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P1', 'active', gen_random_uuid()) RETURNING id INTO v_p1;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P2', 'active', gen_random_uuid()) RETURNING id INTO v_p2;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P3', 'active', gen_random_uuid()) RETURNING id INTO v_p3;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P4', 'active', gen_random_uuid()) RETURNING id INTO v_p4;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'P5', 'active', gen_random_uuid()) RETURNING id INTO v_p5;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Fund all 5 participants for this round → get_funded_participant_count = 5.
    INSERT INTO public.round_funding (round_id, participant_id) VALUES
        (v_round_id, v_p1),
        (v_round_id, v_p2),
        (v_round_id, v_p3),
        (v_round_id, v_p4),
        (v_round_id, v_p5);

    -- 3 NEW propositions from 3 distinct participants (carried_from_id NULL,
    -- participant_id set) → unique_submitters=3, proposition_count=3 (>= minimum 3).
    -- effective_count_threshold = LEAST(4, max_possible=5) = 4; acted = 3 < 4 → no advance.
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1, 'Idea A');
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2, 'Idea B');
    INSERT INTO public.propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3, 'Idea C');

    PERFORM set_config('test.key.round_id', v_round_id::TEXT, TRUE);
    PERFORM set_config('test.key.p4',       v_p4::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- TEST 1a: With 3 submitters and 0 skips, the count threshold (4) is NOT met by
-- submitters. Round must still be 'proposing' (no early advance). This matches OLD
-- behavior and confirms the third proposition INSERT did not spuriously advance.
-- -----------------------------------------------------------------------------
SELECT is(
    (SELECT phase::TEXT FROM public.rounds WHERE id = current_setting('test.key.round_id')::INT),
    'proposing',
    '1a: 3 submitters (< count threshold 4) does NOT advance — stays proposing'
);

-- -----------------------------------------------------------------------------
-- Drive the skip trigger: a 4th DISTINCT participant skips. acted = 3 + 1 = 4 >= 4.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO public.round_skips (round_id, participant_id)
    VALUES (
        current_setting('test.key.round_id')::INT,
        current_setting('test.key.p4')::INT
    );
END $$;

-- -----------------------------------------------------------------------------
-- TEST 1b: After the 4th participant skips, acted (3 submitters + 1 skip) = 4 meets
-- the count threshold; minimum (3 real props) still met; percent threshold NULL →
-- required 0 → met. Round SHOULD advance to 'rating'. Only passes under new logic.
-- -----------------------------------------------------------------------------
SELECT is(
    (SELECT phase::TEXT FROM public.rounds WHERE id = current_setting('test.key.round_id')::INT),
    'rating',
    '1b: a 4th participant SKIPPING makes acted=4 (>=count 4) → advances to rating'
);

-- -----------------------------------------------------------------------------
-- TEST 1c: phase_ends_at was set when advancing to rating (sanity on the auto path).
-- -----------------------------------------------------------------------------
SELECT isnt(
    (SELECT phase_ends_at FROM public.rounds WHERE id = current_setting('test.key.round_id')::INT),
    NULL,
    '1c: phase_ends_at is set after advancing to rating'
);

-- =============================================================================
-- TEST 2 (GUARD): minimum still gates. Fresh chat/round: 0 real propositions, only
-- skips. proposition_count (0) < proposing_minimum (3) → minimum_met false → no
-- advance, even though skips alone would otherwise satisfy the count threshold.
-- =============================================================================

DO $$
DECLARE
    v_chat_id   INT;
    v_cycle_id  INT;
    v_round_id  INT;
    v_p1 INT; v_p2 INT; v_p3 INT; v_p4 INT; v_p5 INT;
BEGIN
    INSERT INTO public.chats (
        name, initial_message, creator_session_token,
        start_mode,
        proposing_threshold_percent, proposing_threshold_count,
        proposing_duration_seconds, rating_duration_seconds,
        proposing_minimum, rating_minimum,
        rating_start_mode
    ) VALUES (
        '113 ProposingAdvanceCountsSkips Guard', 'Pick the best idea', gen_random_uuid(),
        'manual',
        NULL, 3,        -- count threshold 3 (DB constraint >= 3); skips alone could meet it if minimum did not gate
        300, 60,
        3, 2,           -- proposing_minimum=3 is the gate under test
        'auto'
    ) RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'G1', 'active', gen_random_uuid()) RETURNING id INTO v_p1;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'G2', 'active', gen_random_uuid()) RETURNING id INTO v_p2;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'G3', 'active', gen_random_uuid()) RETURNING id INTO v_p3;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'G4', 'active', gen_random_uuid()) RETURNING id INTO v_p4;
    INSERT INTO public.participants (chat_id, display_name, status, session_token)
    VALUES (v_chat_id, 'G5', 'active', gen_random_uuid()) RETURNING id INTO v_p5;

    INSERT INTO public.cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    INSERT INTO public.rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    INSERT INTO public.round_funding (round_id, participant_id) VALUES
        (v_round_id, v_p1),
        (v_round_id, v_p2),
        (v_round_id, v_p3),
        (v_round_id, v_p4),
        (v_round_id, v_p5);

    -- No propositions submitted. Three distinct participants skip → acted = 0 + 3 = 3,
    -- which MEETS count threshold 3, but proposition_count = 0 < minimum 3, so the
    -- minimum gate must still hold it in proposing.
    INSERT INTO public.round_skips (round_id, participant_id) VALUES (v_round_id, v_p1);
    INSERT INTO public.round_skips (round_id, participant_id) VALUES (v_round_id, v_p2);
    INSERT INTO public.round_skips (round_id, participant_id) VALUES (v_round_id, v_p3);

    PERFORM set_config('test.guard.round_id', v_round_id::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- TEST 2: With 0 real propositions and 3 skips, minimum_met is false → stays
-- 'proposing'. Confirms counting skips toward the count threshold did NOT bypass the
-- real-proposition minimum gate.
-- -----------------------------------------------------------------------------
SELECT is(
    (SELECT phase::TEXT FROM public.rounds WHERE id = current_setting('test.guard.round_id')::INT),
    'proposing',
    '2: 0 real props + skips (minimum 3 unmet) does NOT advance — minimum still gates'
);

SELECT * FROM finish();
ROLLBACK;
