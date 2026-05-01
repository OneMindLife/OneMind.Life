-- =============================================================================
-- TESTS: Auto-skip stranded raters when a round enters rating phase
--   Migration: supabase/migrations/20260501050000_auto_skip_stranded_raters.sql
--
-- Coverage:
--   T1  Carry author (also submitted fresh) auto-skipped when their rateable
--       count is below rating_minimum
--   T2  Non-carry-author submitters NOT auto-skipped
--   T3  Trigger does not fire on phases other than rating
--   T4  Trigger is idempotent — re-running phase-update is safe
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(4);

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000b01'::uuid, 'authenticated', 'strand_p1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000b02'::uuid, 'authenticated', 'strand_p2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000b03'::uuid, 'authenticated', 'strand_p3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

-- -----------------------------------------------------------------------------
-- SETUP: 3-person chat, rating_minimum=2, R1 won by P1, R2 in proposing
-- with carry of P1's R1 win. P1 (carry author) ALSO submits a fresh prop in
-- R2; P2 submits a fresh prop; P3 affirms (no submission). Round 2's
-- propositions: 1 carry (author P1) + 2 fresh (one each by P1 and P2).
-- Active raters when R2 enters rating:
--   - P1: rateable = 1 (P2's fresh; carry + own fresh excluded) → STRANDED
--   - P2: rateable = 2 (carry + P1's fresh) → OK
--   - P3: rateable = 3 (everything) → OK
-- -----------------------------------------------------------------------------

DO $$
DECLARE
  v_chat INT; v_cy INT; v_r1 INT; v_r2 INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_p1_r1_prop INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     allow_skip_proposing,
                     proposing_minimum, rating_minimum)
  VALUES ('Stranded Test Chat', 'Q?', gen_random_uuid(),
          TRUE, 3, 2)
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000b01'::uuid, 'P1', 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000b02'::uuid, 'P2', 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-000000000b03'::uuid, 'P3', 'active') RETURNING id INTO v_p3;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cy, 1, 'rating', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '5 minutes')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, 'P1 R1 winner') RETURNING id INTO v_p1_r1_prop;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'P2 R1');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p3, 'P3 R1');
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_r1, v_p1_r1_prop, 1);
  UPDATE rounds SET winning_proposition_id = v_p1_r1_prop, is_sole_winner = TRUE WHERE id = v_r1;

  -- R2 created by the on_round_winner_set trigger; place it in proposing.
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cy AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing',
                    phase_started_at = NOW(),
                    phase_ends_at = NOW() + INTERVAL '5 minutes'
  WHERE id = v_r2;

  -- Fresh submissions: P1 (carry author) AND P2.
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r2, v_p1, 'P1 R2 fresh');
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r2, v_p2, 'P2 R2 fresh');

  PERFORM set_config('test.r2_id', v_r2::TEXT, TRUE);
  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- T3 first (test the no-op case before we transition to rating).
-- The trigger should not fire on a non-rating phase update.
-- -----------------------------------------------------------------------------
UPDATE rounds SET phase_ends_at = NOW() + INTERVAL '10 minutes'
WHERE id = current_setting('test.r2_id')::INT;

SELECT is(
  (SELECT COUNT(*)::INT FROM rating_skips
    WHERE round_id = current_setting('test.r2_id')::INT),
  0,
  'T3 trigger does NOT fire on non-rating phase updates'
);

-- -----------------------------------------------------------------------------
-- Transition R2 to rating. The trigger should now run and mark P1 as
-- stranded.
-- -----------------------------------------------------------------------------
UPDATE rounds SET phase = 'rating',
                  phase_started_at = NOW(),
                  phase_ends_at = NOW() + INTERVAL '5 minutes'
WHERE id = current_setting('test.r2_id')::INT;

-- -----------------------------------------------------------------------------
-- T1: P1 (carry author + fresh-submitter) was auto-skipped.
-- -----------------------------------------------------------------------------
SELECT is(
  (SELECT COUNT(*)::INT FROM rating_skips
    WHERE round_id = current_setting('test.r2_id')::INT
      AND participant_id = current_setting('test.p1')::INT),
  1,
  'T1 carry author with insufficient rateable props is auto-skipped'
);

-- -----------------------------------------------------------------------------
-- T2: P2 and P3 were NOT auto-skipped (they have ≥ rating_minimum to rate).
-- -----------------------------------------------------------------------------
SELECT is(
  (SELECT COUNT(*)::INT FROM rating_skips
    WHERE round_id = current_setting('test.r2_id')::INT
      AND participant_id IN (
        current_setting('test.p2')::INT,
        current_setting('test.p3')::INT)),
  0,
  'T2 non-stranded participants are not marked as rating-skipped'
);

-- -----------------------------------------------------------------------------
-- T4: re-running the phase update is idempotent (no duplicate rows for P1).
-- -----------------------------------------------------------------------------
UPDATE rounds SET phase = 'rating' -- same phase update — should not create dups
WHERE id = current_setting('test.r2_id')::INT;

SELECT is(
  (SELECT COUNT(*)::INT FROM rating_skips
    WHERE round_id = current_setting('test.r2_id')::INT),
  1,
  'T4 trigger is idempotent — no duplicate rating_skips for stranded user'
);

SELECT * FROM finish();
ROLLBACK;
