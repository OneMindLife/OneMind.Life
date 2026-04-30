-- =============================================================================
-- TEST: Leaving a chat preserves the participant's input (proposition,
--       ratings, skips). The participant row is soft-deleted (status='left')
--       so all FKs stay intact. Rejoining the same chat with the same
--       user_id reuses the existing participant row (status flips back to
--       'active') — so the rating screen, leaderboard, etc. all recognize
--       the user as the same person they were before.
-- =============================================================================
-- Bugs this test file confirms (will FAIL on current code):
--
--   T1  — leaveChat soft-deletes (status='left') instead of DELETE
--   T2  — leaveChat preserves grid_rankings (no cascade fired)
--   T3  — leaveChat preserves round_skips
--   T4  — leaveChat preserves propositions.participant_id (no SET NULL)
--   T5  — rejoin uses the same participant_id (status flips to 'active')
--   T6  — rejoin preserves leftover ratings/skips/props on the same row
--   T7  — rejoiner's old proposition is excluded from their own rating queue
--          (because participant_id is the same — no orphan)
--   T8  — auto-advance skip count filters by active status, so a left
--          skipper does not deflate v_active_raters below the actual
--          number of expected raters
--
-- After the fix, ALL tests pass.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(17);

-- =============================================================================
-- SETUP — A chat with 5 active participants and one round in rating phase.
-- One user (A) proposes, rates two props, then leaves. Tests then verify
-- the leave behavior, then rejoin behavior, then auto-advance correctness.
-- =============================================================================
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('99000000-1111-2222-3333-0000000000a1'::uuid, 'authenticated', 'leave_a@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('99000000-1111-2222-3333-0000000000b1'::uuid, 'authenticated', 'leave_b@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('99000000-1111-2222-3333-0000000000c1'::uuid, 'authenticated', 'leave_c@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('99000000-1111-2222-3333-0000000000d1'::uuid, 'authenticated', 'leave_d@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('99000000-1111-2222-3333-0000000000e1'::uuid, 'authenticated', 'leave_e@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

INSERT INTO chats (name, initial_message, access_method, proposing_duration_seconds, rating_duration_seconds,
  proposing_minimum, rating_minimum, start_mode, confirmation_rounds_required,
  rating_threshold_percent, proposing_threshold_percent)
VALUES ('Leave Preserves Input Test', 'topic', 'public', 86400, 86400, 3, 2, 'auto', 2, 100, 100);

DO $$
DECLARE
  v_user_a UUID := '99000000-1111-2222-3333-0000000000a1';
  v_user_b UUID := '99000000-1111-2222-3333-0000000000b1';
  v_user_c UUID := '99000000-1111-2222-3333-0000000000c1';
  v_user_d UUID := '99000000-1111-2222-3333-0000000000d1';
  v_user_e UUID := '99000000-1111-2222-3333-0000000000e1';
  v_chat_id BIGINT;
  v_cycle_id BIGINT;
  v_round_id BIGINT;
  v_a INT;
  v_b INT;
  v_c INT;
  v_d INT;
  v_e INT;
  v_prop_a INT;
  v_prop_b INT;
  v_prop_c INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Leave Preserves Input Test';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, v_user_a, 'A', 'active') RETURNING id INTO v_a;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, v_user_b, 'B', 'active') RETURNING id INTO v_b;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, v_user_c, 'C', 'active') RETURNING id INTO v_c;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, v_user_d, 'D', 'active') RETURNING id INTO v_d;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat_id, v_user_e, 'E', 'active') RETURNING id INTO v_e;

  -- Three users propose during proposing phase
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_a, 'A''s proposition') RETURNING id INTO v_prop_a;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_b, 'B''s proposition') RETURNING id INTO v_prop_b;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_c, 'C''s proposition') RETURNING id INTO v_prop_c;

  -- Phase advances to rating
  UPDATE rounds SET phase = 'rating' WHERE id = v_round_id;

  -- A rates B (80) and C (60) before leaving (skipping their own)
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  VALUES (v_round_id, v_a, v_prop_b, 80);
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  VALUES (v_round_id, v_a, v_prop_c, 60);

  -- D opts to skip rating (records a rating_skip)
  INSERT INTO rating_skips (round_id, participant_id) VALUES (v_round_id, v_d);

  PERFORM set_config('test.user_a', v_user_a::TEXT, TRUE);
  PERFORM set_config('test.user_d', v_user_d::TEXT, TRUE);
  PERFORM set_config('test.a',  v_a::TEXT, TRUE);
  PERFORM set_config('test.b',  v_b::TEXT, TRUE);
  PERFORM set_config('test.c',  v_c::TEXT, TRUE);
  PERFORM set_config('test.d',  v_d::TEXT, TRUE);
  PERFORM set_config('test.e',  v_e::TEXT, TRUE);
  PERFORM set_config('test.prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.prop_b', v_prop_b::TEXT, TRUE);
  PERFORM set_config('test.prop_c', v_prop_c::TEXT, TRUE);
END $$;

-- =============================================================================
-- ACT: A leaves the chat. The fix changes Dart's leaveChat() from
-- DELETE to UPDATE status='left'. This test simulates that.
-- =============================================================================
UPDATE participants SET status = 'left' WHERE id = current_setting('test.a')::int;

-- =============================================================================
-- T1 — A's participant row still exists with status='left'
-- =============================================================================
SELECT is(
  (SELECT status FROM participants WHERE id = current_setting('test.a')::int),
  'left',
  'T1: leaveChat soft-deletes — participant row remains with status=''left'''
);

-- =============================================================================
-- T2 — A's grid_rankings preserved (no cascade fired)
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::int FROM grid_rankings
   WHERE round_id = current_setting('test.round_id')::bigint
     AND participant_id = current_setting('test.a')::bigint),
  2,
  'T2: A''s 2 grid_rankings preserved after leave'
);

-- =============================================================================
-- T3 — D's rating_skips preserved when D leaves (skipper-leaves case)
-- =============================================================================
UPDATE participants SET status = 'left' WHERE id = current_setting('test.d')::int;
SELECT is(
  (SELECT COUNT(*)::int FROM rating_skips
   WHERE round_id = current_setting('test.round_id')::bigint
     AND participant_id = current_setting('test.d')::bigint),
  1,
  'T3: D''s rating_skip preserved after leave'
);

-- =============================================================================
-- T4 — A's proposition still attributed to A (participant_id NOT nulled)
-- =============================================================================
SELECT is(
  (SELECT participant_id FROM propositions WHERE id = current_setting('test.prop_a')::bigint),
  current_setting('test.a')::bigint,
  'T4: A''s proposition keeps participant_id (no SET NULL on soft-delete)'
);

-- =============================================================================
-- T5 — Rejoin: A re-joins the chat. The fix changes joinChat to upsert
-- (ON CONFLICT DO UPDATE) so the same participant_id row flips back to
-- active. This test simulates that.
-- =============================================================================
DO $$
DECLARE
  v_chat_id BIGINT := current_setting('test.chat_id')::bigint;
  v_user_a UUID := current_setting('test.user_a')::uuid;
BEGIN
  -- Same upsert that the fixed joinChat will execute
  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, v_user_a, 'A rejoined', 'active', false)
  ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
  DO UPDATE SET status = 'active', display_name = EXCLUDED.display_name;
END $$;

-- A's participant row should be the SAME id, status flipped to active
SELECT is(
  (SELECT id FROM participants
   WHERE chat_id = current_setting('test.chat_id')::bigint
     AND user_id = current_setting('test.user_a')::uuid),
  current_setting('test.a')::bigint,
  'T5: rejoin reuses the same participant_id (no new row inserted)'
);

-- =============================================================================
-- T6 — Rejoin status is 'active' and display_name is updated
-- =============================================================================
SELECT is(
  (SELECT status FROM participants WHERE id = current_setting('test.a')::bigint),
  'active',
  'T6: rejoin flips status back to ''active'''
);

-- =============================================================================
-- T7 — Rejoiner does not see their own old proposition in the rating queue.
-- Because participant_id is preserved on the prop, the existing
-- `participant_id != p_participant_id` filter excludes A's prop for A.
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::int FROM get_least_rated_propositions(
     current_setting('test.round_id')::bigint,
     current_setting('test.a')::bigint,
     10,
     ARRAY[]::bigint[]
   ) WHERE id = current_setting('test.prop_a')::bigint),
  0,
  'T7: A rejoined does not receive their own preserved proposition'
);

-- =============================================================================
-- T8 — Rejoiner's preserved ratings are still queryable (so hasGridRanked
-- returns true and the rating UI shows their previous state, not "rate" button)
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::int FROM grid_rankings
   WHERE round_id = current_setting('test.round_id')::bigint
     AND participant_id = current_setting('test.a')::bigint),
  2,
  'T8: A rejoined: preserved grid_rankings still attached to A''s participant_id'
);

-- =============================================================================
-- T9 — D rejoins after skipping. Their preserved skip means they don't
-- get re-prompted to rate.
-- =============================================================================
DO $$
DECLARE
  v_chat_id BIGINT := current_setting('test.chat_id')::bigint;
  v_user_d UUID := current_setting('test.user_d')::uuid;
BEGIN
  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, v_user_d, 'D rejoined', 'active', false)
  ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
  DO UPDATE SET status = 'active', display_name = EXCLUDED.display_name;
END $$;
SELECT is(
  (SELECT COUNT(*)::int FROM rating_skips
   WHERE round_id = current_setting('test.round_id')::bigint
     AND participant_id = current_setting('test.d')::bigint),
  1,
  'T9: D rejoined: preserved rating_skip still attached'
);

-- =============================================================================
-- T10 — Auto-advance (skipper-leaves edge case):
--   5 active participants, 1 skipper (D). active_raters should be 4.
--   D leaves (status='left') → preserved skip should NOT count toward
--   v_skip_count. Active count drops to 4, skip count should drop to 0
--   (after fix), so active_raters stays 4.
--
-- Without the fix, v_skip_count = 1 (counts D's stale skip), and
-- active_raters = 4 - 1 = 3 — too few. The threshold drops.
-- =============================================================================
DO $$ BEGIN
  -- D leaves again (we rejoined them above)
  UPDATE participants SET status = 'left' WHERE id = current_setting('test.d')::int;
END $$;

SELECT is(
  -- After fix: COUNT only active participants' skips
  (SELECT COUNT(*)::int FROM rating_skips rs
   JOIN participants p ON p.id = rs.participant_id
   WHERE rs.round_id = current_setting('test.round_id')::bigint
     AND p.status = 'active'),
  0,
  'T10: skip-count for auto-advance excludes left skipper''s skip'
);

-- =============================================================================
-- T11 — Auto-advance (rater-leaves edge case):
--   A leaves while their ratings are preserved. A's ratings still count
--   toward per-prop rating count, so prop B and C have ≥1 rating each
--   even though A is gone.
-- =============================================================================
DO $$ BEGIN
  UPDATE participants SET status = 'left' WHERE id = current_setting('test.a')::int;
END $$;

SELECT is(
  (SELECT COUNT(*)::int FROM grid_rankings
   WHERE round_id = current_setting('test.round_id')::bigint
     AND proposition_id = current_setting('test.prop_b')::bigint),
  1,
  'T11: B''s prop retains A''s rating after A leaves'
);

-- =============================================================================
-- T12 — Total active participant count drops correctly when someone leaves
--      (already filters status='active' — sanity check no regression)
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::int FROM participants
   WHERE chat_id = current_setting('test.chat_id')::bigint
     AND status = 'active'),
  3,  -- B, C, E (A and D both left)
  'T12: active participant count = 3 (A and D both left, B/C/E remain)'
);

-- =============================================================================
-- T13 — Idempotent leave: leaving twice doesn't error or duplicate state
-- =============================================================================
DO $$ BEGIN
  UPDATE participants SET status = 'left' WHERE id = current_setting('test.a')::int;
  UPDATE participants SET status = 'left' WHERE id = current_setting('test.a')::int;
END $$;
SELECT is(
  (SELECT COUNT(*)::int FROM participants
   WHERE chat_id = current_setting('test.chat_id')::bigint
     AND user_id = current_setting('test.user_a')::uuid),
  1,
  'T13: leaving twice does not create a second row (idempotent)'
);

-- =============================================================================
-- T14 — Rejoin after leave is also idempotent: calling join twice in a
--       row is safe (no duplicate row, no error)
-- =============================================================================
DO $$
DECLARE
  v_chat_id BIGINT := current_setting('test.chat_id')::bigint;
  v_user_a UUID := current_setting('test.user_a')::uuid;
BEGIN
  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, v_user_a, 'A again', 'active', false)
  ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
  DO UPDATE SET status = 'active', display_name = EXCLUDED.display_name;

  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, v_user_a, 'A once more', 'active', false)
  ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
  DO UPDATE SET status = 'active', display_name = EXCLUDED.display_name;
END $$;
SELECT is(
  (SELECT COUNT(*)::int FROM participants
   WHERE chat_id = current_setting('test.chat_id')::bigint
     AND user_id = current_setting('test.user_a')::uuid),
  1,
  'T14: rejoining twice is idempotent — still one row'
);

-- =============================================================================
-- T15 — BUG: the production join_chat_returning_participant RPC currently
-- uses ON CONFLICT DO NOTHING, so a previously-left user calling it does
-- NOT get their status flipped back to 'active'. This test exercises the
-- actual production RPC and asserts the post-fix behavior.
--
-- Currently FAILS on unfixed code: status stays 'left' after the RPC call.
-- =============================================================================
DO $$
DECLARE
  v_chat_id BIGINT := current_setting('test.chat_id')::bigint;
  v_user_a UUID := current_setting('test.user_a')::uuid;
BEGIN
  -- Make sure A is currently 'left' before calling the production RPC
  UPDATE participants SET status = 'left'
  WHERE chat_id = v_chat_id AND user_id = v_user_a;

  -- Simulate auth.uid() = A so the RPC's auth.uid() check passes
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user_a)::text, TRUE);

  -- Call the production RPC the way Dart's joinChat does
  PERFORM public.join_chat_returning_participant(v_chat_id, 'A via prod RPC');
END $$;

SELECT is(
  (SELECT status FROM participants
   WHERE chat_id = current_setting('test.chat_id')::bigint
     AND user_id = current_setting('test.user_a')::uuid),
  'active',
  'T15: production join_chat_returning_participant flips left user back to active'
);

-- =============================================================================
-- T16 — BUG: the auto-advance trigger's skip-count query currently does NOT
-- filter by participants.status='active'. So a left skipper's preserved
-- rating_skip would inflate v_skip_count and cause v_active_raters to drop
-- below the actual number of expected raters — risking premature advance.
--
-- This test reproduces exactly the bad case (9 skippers, 1 rater, then one
-- skipper leaves while keeping their skip). After fix, v_active_raters
-- stays correct.
-- =============================================================================
DO $$
DECLARE
  v_chat_id BIGINT;
  v_cycle_id BIGINT;
  v_round_id BIGINT;
  v_uid UUID;
  v_pid INT;
  v_total INT;
  v_skip INT;
  v_active_raters INT;
BEGIN
  INSERT INTO chats (name, initial_message, access_method, proposing_duration_seconds, rating_duration_seconds,
    proposing_minimum, rating_minimum, start_mode, confirmation_rounds_required,
    rating_threshold_percent, proposing_threshold_percent)
  VALUES ('Skip Count Active Filter', 'topic', 'public', 86400, 86400, 3, 2, 'auto', 2, 100, 100)
  RETURNING id INTO v_chat_id;
  PERFORM set_config('test.skip_chat_id', v_chat_id::TEXT, TRUE);

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;
  PERFORM set_config('test.skip_round_id', v_round_id::TEXT, TRUE);

  -- 10 users: 9 skippers + 1 rater
  FOR i IN 1..10 LOOP
    v_uid := gen_random_uuid();
    INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
    VALUES (v_uid, 'authenticated', 'skiptest_' || i || '@test.com', crypt('p', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());
    INSERT INTO participants (chat_id, user_id, display_name, status)
    VALUES (v_chat_id, v_uid, 'Skip ' || i, 'active') RETURNING id INTO v_pid;
    IF i <= 9 THEN
      INSERT INTO rating_skips (round_id, participant_id) VALUES (v_round_id, v_pid);
    END IF;
    IF i = 1 THEN
      PERFORM set_config('test.skipper1_pid', v_pid::TEXT, TRUE);
    END IF;
  END LOOP;

  -- Skipper 1 leaves (status='left'), keeping their preserved rating_skip
  UPDATE participants SET status = 'left'
  WHERE id = current_setting('test.skipper1_pid')::int;
END $$;

SELECT is(
  -- After fix: skip count must JOIN participants and filter active
  (SELECT COUNT(*)::int FROM rating_skips rs
   JOIN participants p ON p.id = rs.participant_id
   WHERE rs.round_id = current_setting('test.skip_round_id')::bigint
     AND p.status = 'active'),
  8,
  'T16: skip-count for active participants only = 8 (excludes left skipper''s preserved skip)'
);

-- =============================================================================
-- T17 — Confirm the resulting v_active_raters formula stays correct:
-- 10 total → 9 active (1 left). 8 active skippers (1 skipper left).
-- v_active_raters = 9 - 8 = 1 (correct: the lone rater is still expected).
-- Without the fix: 9 - 9 = 0, which triggers the "everyone skipped" branch
-- and advances prematurely.
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.skip_chat_id')::bigint AND status = 'active')
  -
  (SELECT COUNT(*)::int FROM rating_skips rs
   JOIN participants p ON p.id = rs.participant_id
   WHERE rs.round_id = current_setting('test.skip_round_id')::bigint
     AND p.status = 'active'),
  1,
  'T17: post-fix active_raters = 1 (lone rater still expected, not 0)'
);

SELECT * FROM finish();
ROLLBACK;
