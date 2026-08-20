-- =============================================================================
-- Does matches-mode rating auto-advance honor the wizard "auto-advance OFF"
-- toggle (NULL rating thresholds)?  Empirical answer for two chat shapes.
-- =============================================================================
-- Context: the create wizard's Rating auto-advance toggle, when OFF, writes
-- rating_threshold_percent = NULL AND rating_threshold_count = NULL.
--
-- Two independent rating-advance paths exist:
--   * check_early_advance_on_rating — GRID mode; fires on grid_rankings; and
--     RETURNs early when both rating thresholds are NULL (honors the toggle).
--     Matches votes never touch grid_rankings, so it never fires for matches.
--   * matches_preview_maybe_finalize — MATCHES mode; fires on rating_completions
--     / rating_skips; finalizes on full participation. BUT it is gated to
--     `max_cycles = 1` (quick chats) and does NOT read the threshold columns.
--
-- Hypothesis under test:
--   A) Continuous matches chat (max_cycles = NULL, like prod chat 1185):
--      full participation does NOT auto-advance — no path fires. Toggle-OFF is
--      effectively honored (round waits for the timer).
--   B) Quick matches chat (max_cycles = 1): full participation DOES auto-advance
--      even though the toggle is OFF — matches_preview ignores the thresholds.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- Helper values reused per chat.
-- =============================================================================
-- SCENARIO A — continuous matches chat (max_cycles = NULL), thresholds NULL.
-- =============================================================================
DO $$
DECLARE
  v_chat INT; v_cyc INT; v_round INT;
  v_p1 INT; v_p2 INT; v_prop1 INT; v_prop2 INT;
  v_u1 UUID := '00000000-0000-0000-0000-0000000d0001';
  v_u2 UUID := '00000000-0000-0000-0000-0000000d0002';
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_u1,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_u2,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  -- Continuous (max_cycles left NULL), matches mode, rating auto-advance OFF.
  -- start_mode='auto' so the ONLY reason it can't advance is the NULL thresholds
  -- (the table default 'manual' would independently block auto-advance).
  INSERT INTO chats (name, initial_message, creator_session_token,
                     rating_mode, start_mode, rating_threshold_percent, rating_threshold_count)
  VALUES ('Matches continuous, auto-advance OFF', 'Q', gen_random_uuid(),
          'matches', 'auto', NULL, NULL)
  RETURNING id INTO v_chat;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cyc;
  -- Insert the round already in rating (INSERT-as-rating avoids the
  -- proposing→rating stranded-rater trigger; with 2 props it's a no-op anyway).
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cyc, 1, 'rating', NOW()) RETURNING id INTO v_round;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), v_u1, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), v_u2, 'P2', FALSE, 'active') RETURNING id INTO v_p2;

  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_p1, 'A-prop1') RETURNING id INTO v_prop1;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_p2, 'A-prop2') RETURNING id INTO v_prop2;

  -- Both voters cast a real pairwise vote AND mark completion → full turnout.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p1, v_prop1, v_prop2);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p1);

  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p2, v_prop1, v_prop2);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p2);

  PERFORM set_config('t.a_round', v_round::TEXT, TRUE);
  PERFORM set_config('t.a_elig',  get_rating_eligible_count(v_chat)::TEXT, TRUE);
END $$;

-- Sanity: both humans were eligible (denominator = 2).
SELECT is(current_setting('t.a_elig')::INT, 2,
  '1: continuous chat — 2 eligible raters');

-- The crux: with full participation and the toggle OFF, a CONTINUOUS matches
-- round must NOT auto-advance (no finalize path fires).
SELECT is(
  (SELECT completed_at FROM rounds WHERE id = current_setting('t.a_round')::INT),
  NULL::TIMESTAMPTZ,
  '2: continuous matches + auto-advance OFF → round NOT completed on full turnout'
);
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('t.a_round')::INT),
  'rating',
  '3: continuous matches + auto-advance OFF → still in rating (waits for timer)'
);

-- =============================================================================
-- SCENARIO B — quick matches chat (max_cycles = 1), thresholds STILL NULL.
-- Demonstrates the toggle is IGNORED on this path: full turnout finalizes.
-- =============================================================================
DO $$
DECLARE
  v_chat INT; v_cyc INT; v_round INT;
  v_p1 INT; v_p2 INT; v_prop1 INT; v_prop2 INT;
  v_u1 UUID := '00000000-0000-0000-0000-0000000d0011';
  v_u2 UUID := '00000000-0000-0000-0000-0000000d0012';
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_u1,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_u2,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO chats (name, initial_message, creator_session_token,
                     rating_mode, max_cycles, rating_threshold_percent, rating_threshold_count)
  VALUES ('Matches quick, auto-advance OFF', 'Q', gen_random_uuid(),
          'matches', 1, NULL, NULL)
  RETURNING id INTO v_chat;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cyc, 1, 'rating', NOW()) RETURNING id INTO v_round;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), v_u1, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), v_u2, 'P2', FALSE, 'active') RETURNING id INTO v_p2;

  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_p1, 'B-prop1') RETURNING id INTO v_prop1;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_p2, 'B-prop2') RETURNING id INTO v_prop2;

  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p1, v_prop1, v_prop2);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p1);

  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p2, v_prop1, v_prop2);
  -- This completion is the one that tips done>=eligible → should finalize.
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p2);

  PERFORM set_config('t.b_round', v_round::TEXT, TRUE);
  PERFORM set_config('t.b_elig',  get_rating_eligible_count(v_chat)::TEXT, TRUE);
END $$;

SELECT is(current_setting('t.b_elig')::INT, 2,
  '4: quick chat — 2 eligible raters');

-- The contrast: same toggle-OFF thresholds, but max_cycles=1 → matches_preview
-- finalizes regardless of the NULL thresholds.
SELECT isnt(
  (SELECT completed_at FROM rounds WHERE id = current_setting('t.b_round')::INT),
  NULL::TIMESTAMPTZ,
  '5: quick matches + auto-advance OFF → round IS completed on full turnout (toggle ignored)'
);
SELECT ok(
  (SELECT COUNT(*) FROM round_winners WHERE round_id = current_setting('t.b_round')::INT) > 0,
  '6: quick matches finalize recorded a winner'
);

-- NOTE: Scenario B (quick matches finalize on full turnout) is also covered
-- canonically by 119_backend_auto_advance_test (R1) and
-- 123_stranded_rater_finalize_test. It is repeated here only to frame the
-- max_cycles axis of the finding against the same NULL thresholds.

-- =============================================================================
-- SCENARIO C — continuous matches chat with rating auto-advance turned ON
-- (thresholds SET) DOES early-advance on full turnout, after the fix in
-- 20260706170000_matches_continuous_rating_auto_advance.sql. Before that fix
-- this was the red anchor: matches_preview was gated to max_cycles = 1 and the
-- grid path never fires for matches, so a continuous matches chat could never
-- honor its own auto-advance toggle. Now it does (opt-in via the toggle;
-- Scenario A proves toggle-OFF still stays timer-only).
-- =============================================================================
DO $$
DECLARE
  v_chat INT; v_cyc INT; v_round INT;
  v_p1 INT; v_p2 INT; v_prop1 INT; v_prop2 INT;
  v_u1 UUID := '00000000-0000-0000-0000-0000000d0021';
  v_u2 UUID := '00000000-0000-0000-0000-0000000d0022';
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_u1,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_u2,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  -- Continuous (max_cycles NULL), matches, auto-advance ON (100%/2), start auto.
  -- This is prod chat 1185's shape if its Rating toggle were turned on.
  INSERT INTO chats (name, initial_message, creator_session_token,
                     rating_mode, start_mode, rating_threshold_percent, rating_threshold_count)
  VALUES ('Matches continuous, auto-advance ON', 'Q', gen_random_uuid(),
          'matches', 'auto', 100, 2)
  RETURNING id INTO v_chat;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cyc, 1, 'rating', NOW()) RETURNING id INTO v_round;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), v_u1, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), v_u2, 'P2', FALSE, 'active') RETURNING id INTO v_p2;

  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_p1, 'C-prop1') RETURNING id INTO v_prop1;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_p2, 'C-prop2') RETURNING id INTO v_prop2;

  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p1, v_prop1, v_prop2);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p1);
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p2, v_prop1, v_prop2);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p2);

  PERFORM set_config('t.c_round', v_round::TEXT, TRUE);
END $$;

SELECT isnt(
  (SELECT completed_at FROM rounds WHERE id = current_setting('t.c_round')::INT),
  NULL::TIMESTAMPTZ,
  '7: continuous matches + auto-advance ON → round IS completed on full turnout (fix: toggle now reaches matches)'
);
SELECT ok(
  (SELECT COUNT(*) FROM round_winners WHERE round_id = current_setting('t.c_round')::INT) > 0,
  '8: continuous matches auto-advance recorded a winner'
);

SELECT * FROM finish();
ROLLBACK;
