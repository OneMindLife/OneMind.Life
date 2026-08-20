-- =============================================================================
-- Tests for rounds.participation_percent denormalized column + triggers.
-- =============================================================================
-- Migration: 20260502170000_denormalize_round_participation_percent.sql
--
-- Coverage:
--   1.  Column shape (INT, nullable for non-tracked phases)
--   2.  Helper recompute fn exists
--   3.  All 6 triggers attached + SECURITY DEFINER
--   4.  Proposing phase: 0 acted → 0%
--   5.  Proposing: 1 of 4 proposed → 25%
--   6.  Proposing: 2 proposed + 1 skip → 75%
--   7.  Proposing: 1 proposed + 1 affirm → 50%
--   8.  Proposing: deleting a proposition decrements percent
--   9.  Rating phase: 0 ratings → 0%
--   10. Rating phase: min ratings ≥ threshold → 100%
--   11. Phase change: percent recomputes on proposing→rating
--   12. **REGRESSION**: trigger fires from authenticated role under RLS.
--       Catches the silent-no-op trap from feedback_trigger_security_definer.md.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- SETUP
-- =============================================================================
DO $$
DECLARE
  v_chat_id   INT;
  v_cycle_id  INT;
  v_round_id  INT;
  v_p1 INT; v_p2 INT; v_p3 INT; v_p4 INT;
  v_uid1 UUID := '00000000-0000-0000-0000-0000000b0001';
  v_uid2 UUID := '00000000-0000-0000-0000-0000000b0002';
  v_uid3 UUID := '00000000-0000-0000-0000-0000000b0003';
  v_uid4 UUID := '00000000-0000-0000-0000-0000000b0004';
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_uid1, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_uid2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_uid3, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_uid4, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO chats (name, initial_message, creator_session_token)
  VALUES ('Round Participation % Test', 'Test', gen_random_uuid())
  RETURNING id INTO v_chat_id;

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_uid1, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_uid2, 'P2', FALSE, 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_uid3, 'P3', FALSE, 'active') RETURNING id INTO v_p3;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_uid4, 'P4', FALSE, 'active') RETURNING id INTO v_p4;

  PERFORM set_config('test.rpp.chat_id',  v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.rpp.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.rpp.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.rpp.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.rpp.p3', v_p3::TEXT, TRUE);
  PERFORM set_config('test.rpp.p4', v_p4::TEXT, TRUE);
  PERFORM set_config('test.rpp.uid2', v_uid2::TEXT, TRUE);

  -- Force initial recompute (no events yet → 0%)
  PERFORM recompute_round_participation_percent(v_round_id);
END $$;

-- =============================================================================
-- 1. Column shape
-- =============================================================================
SELECT col_type_is(
  'public', 'rounds', 'participation_percent', 'integer',
  '1: rounds.participation_percent is integer'
);

-- =============================================================================
-- 2. Helper exists
-- =============================================================================
SELECT has_function(
  'public', 'recompute_round_participation_percent', ARRAY['bigint'],
  '2: recompute_round_participation_percent(bigint) exists'
);

-- =============================================================================
-- 3. All triggers attached and DEFINER
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM pg_trigger t
   JOIN pg_proc p ON p.oid = t.tgfoid
   WHERE NOT t.tgisinternal
     AND t.tgname IN (
       'sync_round_participation_proposition',
       'sync_round_participation_proposition_rating_count',
       'sync_round_participation_round_skip',
       'sync_round_participation_rating_skip',
       'sync_round_participation_affirmation',
       'sync_round_participation_phase_change')
     AND p.prosecdef = TRUE),
  6,
  '3: all 6 participation-percent triggers exist and are SECURITY DEFINER'
);

-- =============================================================================
-- 4. Proposing 0 acted → 0%
-- =============================================================================
SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  0,
  '4: 0 acted of 4 → 0%'
);

-- =============================================================================
-- 5. 1 proposition INSERT → 25%
-- =============================================================================
INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.rpp.round_id')::INT,
        current_setting('test.rpp.p1')::INT, 'Prop 1');

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  25,
  '5: 1 proposition by 1 of 4 participants → 25%'
);

-- =============================================================================
-- 6. 2 proposed + 1 skip = 3 of 4 → 75%
-- =============================================================================
INSERT INTO propositions (round_id, participant_id, content)
  VALUES (current_setting('test.rpp.round_id')::INT,
          current_setting('test.rpp.p2')::INT, 'Prop 2');
INSERT INTO round_skips (round_id, participant_id)
  VALUES (current_setting('test.rpp.round_id')::INT,
          current_setting('test.rpp.p3')::INT);

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  75,
  '6: 2 proposed + 1 propose-skip = 3 of 4 → 75%'
);

-- =============================================================================
-- 7. Reset — 1 prop + 1 affirm = 2 of 4 → 50%
-- =============================================================================
DELETE FROM propositions
  WHERE round_id = current_setting('test.rpp.round_id')::INT;
DELETE FROM round_skips
  WHERE round_id = current_setting('test.rpp.round_id')::INT;

INSERT INTO propositions (round_id, participant_id, content)
  VALUES (current_setting('test.rpp.round_id')::INT,
          current_setting('test.rpp.p1')::INT, 'Prop A');
INSERT INTO affirmations (round_id, participant_id, user_id)
  VALUES (current_setting('test.rpp.round_id')::INT,
          current_setting('test.rpp.p2')::INT,
          current_setting('test.rpp.uid2')::UUID);

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  50,
  '7: 1 propose + 1 affirm = 2 of 4 → 50%'
);

-- =============================================================================
-- 8. DELETE proposition → percent drops
-- =============================================================================
DELETE FROM propositions
  WHERE round_id = current_setting('test.rpp.round_id')::INT
    AND participant_id = current_setting('test.rpp.p1')::INT;

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  25,
  '8: deleting a proposition decrements percent (1 affirm of 4 → 25%)'
);

-- Restore + add 3 more props so rating phase has 4 propositions.
-- With 4 participants and 4 propositions (one each), every participant
-- has 3 rateable propositions ≥ rating_minimum (2), so the
-- maybe_mark_stranded_raters trigger does NOT fire on phase change —
-- isolating this test to participation_percent behaviour.
INSERT INTO propositions (round_id, participant_id, content) VALUES
  (current_setting('test.rpp.round_id')::INT, current_setting('test.rpp.p1')::INT, 'Prop A2'),
  (current_setting('test.rpp.round_id')::INT, current_setting('test.rpp.p2')::INT, 'Prop B'),
  (current_setting('test.rpp.round_id')::INT, current_setting('test.rpp.p3')::INT, 'Prop C'),
  (current_setting('test.rpp.round_id')::INT, current_setting('test.rpp.p4')::INT, 'Prop D');
DELETE FROM affirmations
  WHERE round_id = current_setting('test.rpp.round_id')::INT;

-- =============================================================================
-- 9. Phase change to rating → percent recomputes (formula switches)
-- =============================================================================
UPDATE rounds SET phase = 'rating'
  WHERE id = current_setting('test.rpp.round_id')::INT;

-- After phase flip with 0 grid_rankings, min_ratings = 0.
-- active_raters=4 (no auto-skip since rateable=3 ≥ rating_minimum=2),
-- threshold = LEAST(10, MAX(3, 1)) = 3, percent = 0/3 = 0.
SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  0,
  '9: phase=rating, no ratings yet → 0%'
);

-- =============================================================================
-- 10. Rating phase: each prop gets 3 ratings → min ≥ threshold → 100%
-- Insert grid_rankings so EVERY proposition reaches rating_count = 3.
-- =============================================================================
DO $$
DECLARE r RECORD; v_round INT := current_setting('test.rpp.round_id')::INT;
BEGIN
  FOR r IN SELECT id FROM propositions WHERE round_id = v_round LOOP
    INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES
      (v_round, current_setting('test.rpp.p2')::INT, r.id, 50.0),
      (v_round, current_setting('test.rpp.p3')::INT, r.id, 51.0),
      (v_round, current_setting('test.rpp.p4')::INT, r.id, 52.0)
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  100,
  '10: rating, every prop reaches rating_count = 3 = threshold → 100%'
);

-- =============================================================================
-- 11. rating_skip insert recomputes (trigger fires).
-- threshold drops from 3 to 2; min_ratings stays at 3 → still 100%.
-- =============================================================================
INSERT INTO rating_skips (round_id, participant_id)
VALUES (current_setting('test.rpp.round_id')::INT,
        current_setting('test.rpp.p1')::INT)
ON CONFLICT DO NOTHING;

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.round_id')::INT),
  100,
  '11: rating_skip insertion fires trigger; min_ratings still ≥ threshold → 100%'
);

-- =============================================================================
-- 12. REGRESSION — trigger fires correctly when source INSERT is from
-- the authenticated role under RLS. Catches the SECURITY DEFINER trap.
-- The trigger UPDATE on rounds requires DEFINER; without it the trigger
-- silently no-ops because rounds has no UPDATE policy for authenticated.
-- =============================================================================
DO $$
DECLARE
  v_chat2_id    INT;
  v_cycle2_id   INT;
  v_round2_id   INT;
  v_p_host      INT;
  v_p_other     INT;
  v_uid_host    UUID := '00000000-0000-0000-0000-0000000b0011';
  v_uid_other   UUID := '00000000-0000-0000-0000-0000000b0012';
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_uid_host,  'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_uid_other, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO chats (name, initial_message, creator_session_token)
  VALUES ('Participation % RLS regression', 'Test', gen_random_uuid())
  RETURNING id INTO v_chat2_id;
  INSERT INTO cycles (chat_id) VALUES (v_chat2_id) RETURNING id INTO v_cycle2_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle2_id, 1, 'proposing') RETURNING id INTO v_round2_id;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat2_id, gen_random_uuid(), v_uid_host, 'H', TRUE, 'active')
    RETURNING id INTO v_p_host;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat2_id, gen_random_uuid(), v_uid_other, 'O', FALSE, 'active')
    RETURNING id INTO v_p_other;

  PERFORM set_config('test.rpp.r2_round',  v_round2_id::TEXT, TRUE);
  PERFORM set_config('test.rpp.r2_part',   v_p_other::TEXT,   TRUE);
  PERFORM set_config('test.rpp.r2_uid',    v_uid_other::TEXT, TRUE);

  PERFORM recompute_round_participation_percent(v_round2_id);
END $$;

-- Snapshot baseline
SELECT set_config('test.rpp.r2_baseline',
  (SELECT participation_percent::TEXT FROM rounds
    WHERE id = current_setting('test.rpp.r2_round')::INT), TRUE);

-- Switch to authenticated as the non-host, INSERT a proposition.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('test.rpp.r2_uid'),
                    'role', 'authenticated')::TEXT, TRUE);

INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.rpp.r2_round')::INT,
        current_setting('test.rpp.r2_part')::INT,
        'Auth-role prop');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.rpp.r2_round')::INT),
  50,
  '12: proposition INSERT from authenticated role updates rounds.participation_percent (1 of 2 → 50%; trigger UPDATE on rounds went through SECURITY DEFINER bypass)'
);

SELECT * FROM finish();
ROLLBACK;
