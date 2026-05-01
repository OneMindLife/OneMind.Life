-- =============================================================================
-- TESTS: Affirmation feature
--   Migration: supabase/migrations/20260430180000_add_affirmations.sql
--   Plan:      docs/planning/AFFIRMATION_FEATURE.md
--
-- Coverage:
--   T1   schema present
--   T2   affirm_round happy path (R2+, carried-forward exists)
--   T3   affirm_round rejects phase != proposing
--   T4   affirm_round rejects when no carried-forward (R1)
--   T5   affirm_round rejects when allow_skip_proposing = false
--   T6   affirm_round rejects when user already submitted
--   T7   affirm_round rejects when user already skipped
--   T8   affirm_round rejects when caller is not an active participant
--   T9   double-affirm raises P0007
--   T10  RLS: SELECT visible to participants of the chat
--   T11  RLS: SELECT blocked for non-participants
--   T12  RLS: direct INSERT blocked (must go through RPC)
--   T13  Auto-resolve fires when all-affirm + zero subs + carried
--   T14  Auto-resolve does NOT fire while ≥1 NEW submission exists
--   T15  Auto-resolve does NOT fire while ≥1 active participant has not acted
--   T16  Convergence: auto-resolved repeat winner counts toward sealing
--   T17  Mixed affirm + skip (≥1 affirm, no subs, all accounted for) → auto-resolve
--   T18  All-skip (zero affirms) → does NOT auto-resolve
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(18);

-- -----------------------------------------------------------------------------
-- SETUP: shared state used across tests via current_setting('test.*')
-- -----------------------------------------------------------------------------

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000a01'::uuid, 'authenticated', 'aff_u1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000a02'::uuid, 'authenticated', 'aff_u2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000a03'::uuid, 'authenticated', 'aff_u3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000a04'::uuid, 'authenticated', 'aff_outsider@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_r1_id INT;
  v_r2_id INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_other_chat_id INT;
  v_other_cycle_id INT;
  v_other_round_id INT;
  v_outsider_id INT;
  v_p1_r1_prop INT;
  v_carried_into_r2 INT;
BEGIN
  -- Main chat: 3 active participants, skips allowed, R1 already won by p1's
  -- proposition. R2 is in proposing phase with the R1 winner carried forward.
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent, proposing_threshold_count,
                     proposing_duration_seconds, rating_duration_seconds)
  VALUES ('Affirm Test Chat', 'Q?', gen_random_uuid(),
          TRUE,
          3, 2,
          100, NULL,
          300, 300)
  RETURNING id INTO v_chat_id;
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1', 'active')
  RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000a02'::uuid, 'P2', 'active')
  RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000a03'::uuid, 'P3', 'active')
  RETURNING id INTO v_p3;
  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- R1: completed, p1's prop won. Carry-forward trigger will create R2
  -- with p1's prop carried over when we set R1's winning_proposition_id.
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cycle_id, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1_id;
  PERFORM set_config('test.r1_id', v_r1_id::TEXT, TRUE);

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1_id, v_p1, 'P1 wins R1') RETURNING id INTO v_p1_r1_prop;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1_id, v_p2, 'P2 R1');
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1_id, v_p3, 'P3 R1');

  -- Insert into round_winners FIRST — the carry-forward trigger reads
  -- from this table when on_round_winner_set fires on the rounds UPDATE.
  INSERT INTO round_winners (round_id, proposition_id, rank)
  VALUES (v_r1_id, v_p1_r1_prop, 1);

  -- Mark R1 winner. on_round_winner_set creates R2 in waiting phase and
  -- carry-forward triggers run on the new round to copy p1's prop in.
  UPDATE rounds SET winning_proposition_id = v_p1_r1_prop, is_sole_winner = TRUE
  WHERE id = v_r1_id;

  SELECT id INTO v_r2_id FROM rounds
   WHERE cycle_id = v_cycle_id AND custom_id = 2;
  -- Force R2 into proposing phase for the tests (the winning trigger set it
  -- to 'waiting' as the auto-start fallback expects).
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
  WHERE id = v_r2_id;
  PERFORM set_config('test.r2_id', v_r2_id::TEXT, TRUE);

  SELECT id INTO v_carried_into_r2 FROM propositions
   WHERE round_id = v_r2_id AND carried_from_id IS NOT NULL
   LIMIT 1;
  PERFORM set_config('test.carried_id', v_carried_into_r2::TEXT, TRUE);

  -- Outsider chat: a separate chat with a different participant. Used to
  -- verify SELECT RLS denies cross-chat reads.
  INSERT INTO chats (name, initial_message, creator_session_token, allow_skip_proposing)
  VALUES ('Affirm Outsider Chat', 'Q?', gen_random_uuid(), TRUE)
  RETURNING id INTO v_other_chat_id;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_other_chat_id, '00000000-0000-0000-0000-000000000a04'::uuid, 'Outsider', 'active')
  RETURNING id INTO v_outsider_id;
  INSERT INTO cycles (chat_id) VALUES (v_other_chat_id) RETURNING id INTO v_other_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_other_cycle_id, 1, 'proposing')
  RETURNING id INTO v_other_round_id;
  PERFORM set_config('test.outsider_round_id', v_other_round_id::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- T1: schema present
-- -----------------------------------------------------------------------------
SELECT is(
  (SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'affirmations')),
  TRUE,
  'T1 affirmations table exists'
);

-- -----------------------------------------------------------------------------
-- T2: happy path — P2 affirms in R2, an affirmation row appears
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a02"}', TRUE);
SELECT lives_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.r2_id')),
  'T2 affirm_round happy path returns without error'
);
RESET ROLE;
SELECT is(
  (SELECT COUNT(*)::INT FROM affirmations
    WHERE round_id = current_setting('test.r2_id')::INT
      AND participant_id = current_setting('test.p2')::INT),
  1,
  'T2b exactly one affirmation row recorded'
);

-- -----------------------------------------------------------------------------
-- T3: phase != proposing → P0002
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_paused_round INT;
BEGIN
  -- Move R2 to rating temporarily to test the phase guard, then revert.
  UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.r2_id')::INT;
  PERFORM set_config('test.skip_revert', '1', TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a03"}', TRUE);
SELECT throws_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.r2_id')),
  'P0002',
  NULL,
  'T3 affirm rejects when phase != proposing'
);
RESET ROLE;

UPDATE rounds SET phase = 'proposing' WHERE id = current_setting('test.r2_id')::INT;

-- -----------------------------------------------------------------------------
-- T4: no carried-forward (R1) → P0004
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_solo_chat INT; v_solo_cycle INT; v_solo_round INT; v_solo_p INT;
BEGIN
  -- Fresh chat / R1 / no carried-forward.
  INSERT INTO chats (name, initial_message, creator_session_token, allow_skip_proposing)
  VALUES ('Affirm R1 Chat', 'Q?', gen_random_uuid(), TRUE)
  RETURNING id INTO v_solo_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_solo_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1 Solo', 'active')
  RETURNING id INTO v_solo_p;
  INSERT INTO cycles (chat_id) VALUES (v_solo_chat) RETURNING id INTO v_solo_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_solo_cycle, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
  RETURNING id INTO v_solo_round;
  PERFORM set_config('test.r1_solo_round', v_solo_round::TEXT, TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a01"}', TRUE);
SELECT throws_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.r1_solo_round')),
  'P0004',
  NULL,
  'T4 affirm rejects when no carried-forward (R1)'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T5: chat with allow_skip_proposing=FALSE — affirm should now succeed
-- (decoupled by migration 20260501070000_decouple_affirm_from_skip_config).
-- Hosts who disable skip-proposing want forced engagement; affirm IS
-- engagement, so it stays available.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_no_skip_chat INT; v_cy INT; v_r1 INT; v_r2 INT; v_p INT; v_prop INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum)
  VALUES ('Affirm No-Skip Chat', 'Q?', gen_random_uuid(), FALSE, 3, 2)
  RETURNING id INTO v_no_skip_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_no_skip_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P', 'active')
  RETURNING id INTO v_p;
  INSERT INTO cycles (chat_id) VALUES (v_no_skip_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p, 'P r1') RETURNING id INTO v_prop;
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_r1;
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
   WHERE id = v_r2;
  PERFORM set_config('test.no_skip_r2', v_r2::TEXT, TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a01"}', TRUE);
SELECT lives_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.no_skip_r2')),
  'T5 affirm succeeds even when chat allow_skip_proposing = false'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T6: user already submitted → P0005 (use P3 so other tests are unaffected)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (current_setting('test.r2_id')::INT,
          current_setting('test.p3')::INT,
          'P3 submitted R2');
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a03"}', TRUE);
SELECT throws_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.r2_id')),
  'P0005',
  NULL,
  'T6 affirm rejects when user already submitted'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T7: user already skipped → P0006
--     Use a fresh user/chat to keep tests independent.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_chat INT; v_cy INT; v_r1 INT; v_r2 INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_prop INT;
BEGIN
  -- Use 3 participants so a single skip doesn't trip the early-advance
  -- thresholds. P1 is the test subject; P2 and P3 just sit there.
  INSERT INTO chats (name, initial_message, creator_session_token, allow_skip_proposing,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent)
  VALUES ('Affirm Skipped Chat', 'Q?', gen_random_uuid(), TRUE, 3, 2, 100)
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a02'::uuid, 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a03'::uuid, 'P3', 'active') RETURNING id INTO v_p3;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, 'P1 prop') RETURNING id INTO v_prop;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'B');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p3, 'C');
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_r1;
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
   WHERE id = v_r2;
  -- Insert the skip directly (bypass RLS as the test session). With 3
  -- active participants and proposing_minimum=3 the early-advance won't
  -- fire on a single skip.
  INSERT INTO round_skips (round_id, participant_id) VALUES (v_r2, v_p1);
  PERFORM set_config('test.skipped_r2', v_r2::TEXT, TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a01"}', TRUE);
SELECT throws_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.skipped_r2')),
  'P0006',
  NULL,
  'T7 affirm rejects when user already skipped'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T8: caller not an active participant → P0001
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a04"}', TRUE);
SELECT throws_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.r2_id')),
  'P0001',
  NULL,
  'T8 affirm rejects when caller is not an active participant'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T9: double-affirm → P0007 (P2 already affirmed in T2)
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a02"}', TRUE);
SELECT throws_ok(
  format($$SELECT public.affirm_round(%s::bigint)$$, current_setting('test.r2_id')),
  'P0007',
  NULL,
  'T9 double-affirm rejected with unique-violation mapping'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T10: RLS — participant of the chat can SELECT affirmation rows
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a03"}', TRUE);
SELECT is(
  (SELECT COUNT(*)::INT FROM affirmations
    WHERE round_id = current_setting('test.r2_id')::INT),
  1,
  'T10 RLS: chat participant can SELECT affirmations in their chat'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T11: RLS — user not in the chat sees zero rows
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a04"}', TRUE);
SELECT is(
  (SELECT COUNT(*)::INT FROM affirmations
    WHERE round_id = current_setting('test.r2_id')::INT),
  0,
  'T11 RLS: outsider cannot SELECT affirmations for chats they are not in'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- T12: RLS — direct INSERT blocked (must go through RPC)
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a02"}', TRUE);
SELECT throws_ok(
  format(
    $$INSERT INTO affirmations (round_id, participant_id, user_id) VALUES (%s::bigint, %s::bigint, '00000000-0000-0000-0000-000000000a02'::uuid)$$,
    current_setting('test.r2_id'),
    current_setting('test.p2')
  ),
  NULL, NULL,
  'T12 RLS: direct INSERT blocked for anon (must go via affirm_round RPC)'
);
RESET ROLE;

-- -----------------------------------------------------------------------------
-- SETUP for T13-T16: a fresh chat where we can drive the auto-resolve path.
-- 3 active participants. R1 won by P1. R2 in proposing with carried-forward.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_chat INT; v_cy INT; v_r1 INT; v_r2 INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_prop INT; v_carried INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent, proposing_threshold_count)
  VALUES ('Affirm Auto-Resolve Chat', 'Q?', gen_random_uuid(),
          TRUE, 3, 2, 100, NULL)
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a02'::uuid, 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a03'::uuid, 'P3', 'active') RETURNING id INTO v_p3;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, 'WINNER P1 R1') RETURNING id INTO v_prop;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'B');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p3, 'C');
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_r1;

  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
  WHERE id = v_r2;
  SELECT id INTO v_carried FROM propositions
    WHERE round_id = v_r2 AND carried_from_id IS NOT NULL LIMIT 1;

  PERFORM set_config('test.ar_chat', v_chat::TEXT, TRUE);
  PERFORM set_config('test.ar_cy', v_cy::TEXT, TRUE);
  PERFORM set_config('test.ar_r2', v_r2::TEXT, TRUE);
  PERFORM set_config('test.ar_p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.ar_p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.ar_p3', v_p3::TEXT, TRUE);
  PERFORM set_config('test.ar_carried', v_carried::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- T13: auto-resolve fires when all-affirm + zero subs + carried exists.
--      Three users each affirm; after the third, the round should have
--      a winning_proposition_id pointing at the carried prop.
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a01"}', TRUE);
SELECT public.affirm_round(current_setting('test.ar_r2')::bigint);
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a02"}', TRUE);
SELECT public.affirm_round(current_setting('test.ar_r2')::bigint);
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a03"}', TRUE);
SELECT public.affirm_round(current_setting('test.ar_r2')::bigint);
RESET ROLE;

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.ar_r2')::INT),
  current_setting('test.ar_carried')::INT::BIGINT,
  'T13 auto-resolve: round winner = carried-forward proposition'
);

-- -----------------------------------------------------------------------------
-- T14: auto-resolve does NOT fire when ≥1 NEW submission exists.
--      Build the scenario fresh so prior tests don''t pollute.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_chat INT; v_cy INT; v_r1 INT; v_r2 INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_prop INT; v_carried INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent)
  VALUES ('Affirm Mixed Chat', 'Q?', gen_random_uuid(),
          TRUE, 3, 2, 100)
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a02'::uuid, 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a03'::uuid, 'P3', 'active') RETURNING id INTO v_p3;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, 'WINNER R1') RETURNING id INTO v_prop;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'B');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p3, 'C');
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_r1;
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
  WHERE id = v_r2;
  -- One user submits a new prop, two affirm. Auto-resolve must NOT fire.
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r2, v_p1, 'P1 new R2');

  PERFORM set_config('test.mixed_r2', v_r2::TEXT, TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a02"}', TRUE);
SELECT public.affirm_round(current_setting('test.mixed_r2')::bigint);
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a03"}', TRUE);
SELECT public.affirm_round(current_setting('test.mixed_r2')::bigint);
RESET ROLE;

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.mixed_r2')::INT),
  NULL::BIGINT,
  'T14 auto-resolve does NOT fire when ≥1 NEW submission exists'
);

-- -----------------------------------------------------------------------------
-- T15: auto-resolve does NOT fire while ≥1 active participant has not acted.
--      Two of three affirm; third does nothing. No auto-resolve.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_chat INT; v_cy INT; v_r1 INT; v_r2 INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_prop INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent)
  VALUES ('Affirm Partial Chat', 'Q?', gen_random_uuid(),
          TRUE, 3, 2, 100)
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a02'::uuid, 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a03'::uuid, 'P3', 'active') RETURNING id INTO v_p3;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, 'WINNER R1') RETURNING id INTO v_prop;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'B');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p3, 'C');
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_r1;
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
  WHERE id = v_r2;
  PERFORM set_config('test.partial_r2', v_r2::TEXT, TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a01"}', TRUE);
SELECT public.affirm_round(current_setting('test.partial_r2')::bigint);
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a02"}', TRUE);
SELECT public.affirm_round(current_setting('test.partial_r2')::bigint);
RESET ROLE;

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.partial_r2')::INT),
  NULL::BIGINT,
  'T15 auto-resolve does NOT fire while a participant has not acted'
);

-- -----------------------------------------------------------------------------
-- T16: convergence integration. The auto-resolve path made R2 winner =
--      same prop content as R1 (carried-forward), so the cycle should be
--      sealed with that winning_proposition_id. The on_round_winner_set
--      trigger drives this — we verify by inspecting the cycle.
-- -----------------------------------------------------------------------------
SELECT is(
  (SELECT winning_proposition_id IS NOT NULL FROM cycles
     WHERE id = current_setting('test.ar_cy')::INT),
  TRUE,
  'T16 convergence: cycle sealed after auto-resolved R2 confirms R1 winner'
);

-- -----------------------------------------------------------------------------
-- T17: mixed affirm + skip with no submissions and ≥1 affirmation auto-resolves.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_chat INT; v_cy INT; v_r1 INT; v_r2 INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_prop INT; v_carried INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent)
  VALUES ('Affirm Mixed Resolve Chat', 'Q?', gen_random_uuid(),
          TRUE, 3, 2, 100)
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a02'::uuid, 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a03'::uuid, 'P3', 'active') RETURNING id INTO v_p3;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, 'WIN R1') RETURNING id INTO v_prop;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'B');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p3, 'C');
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_r1;
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
  WHERE id = v_r2;
  SELECT id INTO v_carried FROM propositions
   WHERE round_id = v_r2 AND carried_from_id IS NOT NULL LIMIT 1;
  PERFORM set_config('test.t17_r2', v_r2::TEXT, TRUE);
  PERFORM set_config('test.t17_carried', v_carried::TEXT, TRUE);
  PERFORM set_config('test.t17_p3', v_p3::TEXT, TRUE);
  -- Two skips first (P1, P2), then one affirmation (P3) — order matters because
  -- only the affirmation trigger runs the auto-resolve. With ≥1 affirm and the
  -- last actor's check seeing affirms+skips ≥ active, the resolve must fire.
  INSERT INTO round_skips (round_id, participant_id) VALUES (v_r2, v_p1);
  INSERT INTO round_skips (round_id, participant_id) VALUES (v_r2, v_p2);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000a03"}', TRUE);
SELECT public.affirm_round(current_setting('test.t17_r2')::bigint);
RESET ROLE;

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.t17_r2')::INT),
  current_setting('test.t17_carried')::INT::BIGINT,
  'T17 mixed affirm + skip with ≥1 affirm auto-resolves to carried winner'
);

-- -----------------------------------------------------------------------------
-- T18: all-skip (zero affirmations) — auto-resolve must NOT fire from the
--      affirmation trigger (it never runs without an INSERT). We assert the
--      round still has no winner after all three users skip.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_chat INT; v_cy INT; v_r1 INT; v_r2 INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_prop INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent)
  VALUES ('Affirm All-Skip Chat', 'Q?', gen_random_uuid(),
          TRUE, 3, 2, 100)
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a01'::uuid, 'P1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a02'::uuid, 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000a03'::uuid, 'P3', 'active') RETURNING id INTO v_p3;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, 'WIN R1') RETURNING id INTO v_prop;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'B');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p3, 'C');
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_r1;
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
  WHERE id = v_r2;
  INSERT INTO round_skips (round_id, participant_id) VALUES (v_r2, v_p1);
  INSERT INTO round_skips (round_id, participant_id) VALUES (v_r2, v_p2);
  INSERT INTO round_skips (round_id, participant_id) VALUES (v_r2, v_p3);
  PERFORM set_config('test.t18_r2', v_r2::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.t18_r2')::INT),
  NULL::BIGINT,
  'T18 all-skip with zero affirmations does NOT auto-resolve via affirm trigger'
);

SELECT * FROM finish();
ROLLBACK;
