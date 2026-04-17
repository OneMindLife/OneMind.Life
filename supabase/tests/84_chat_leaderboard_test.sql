-- =============================================================================
-- TEST: Chat Leaderboard (get_chat_leaderboard RPC)
-- Tests per-chat ranking aggregation across rounds
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(7);

-- =============================================================================
-- SETUP
-- =============================================================================

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000d01'::uuid, 'authenticated', 'lb_user1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000d02'::uuid, 'authenticated', 'lb_user2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000d03'::uuid, 'authenticated', 'lb_user3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now() + interval '1 hour', now());

-- Create chat
INSERT INTO chats (name, initial_message, creator_id)
VALUES ('Leaderboard Test Chat', 'Test?', '00000000-0000-0000-0000-000000000d01'::uuid);

DO $$
DECLARE
  v_chat_id BIGINT;
  v_cycle_id BIGINT;
  v_round1_id BIGINT;
  v_round2_id BIGINT;
  v_p1 BIGINT;
  v_p2 BIGINT;
  v_p3 BIGINT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Leaderboard Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

  -- Create cycle with two rounds
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at, created_at)
  VALUES (v_cycle_id, 1, 'rating', now(), now() + interval '5 minutes', now())
  RETURNING id INTO v_round1_id;

  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at, created_at)
  VALUES (v_cycle_id, 2, 'rating', now(), now() + interval '5 minutes', now() + interval '30 minutes')
  RETURNING id INTO v_round2_id;

  PERFORM set_config('test.round1_id', v_round1_id::TEXT, TRUE);
  PERFORM set_config('test.round2_id', v_round2_id::TEXT, TRUE);

  -- User1 and User2 joined at start, User3 joined late (after round 1)
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status, created_at)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000d01'::uuid, 'User1', TRUE, 'active', now() - interval '1 hour')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status, created_at)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000d02'::uuid, 'User2', FALSE, 'active', now() - interval '1 hour')
  RETURNING id INTO v_p2;

  -- User3 joined AFTER round 1 was created (so round 1 shouldn't count for them)
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status, created_at)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000d03'::uuid, 'User3', FALSE, 'active', now() + interval '15 minutes')
  RETURNING id INTO v_p3;

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);

  -- Round 1 rankings: User1=80, User2=40 (User3 not yet joined)
  INSERT INTO user_round_ranks (round_id, participant_id, rank, voting_rank, proposing_rank)
  VALUES
    (v_round1_id, v_p1, 80.0, 90.0, 70.0),
    (v_round1_id, v_p2, 40.0, 30.0, 50.0);

  -- Round 2 rankings: all 3 participated
  INSERT INTO user_round_ranks (round_id, participant_id, rank, voting_rank, proposing_rank)
  VALUES
    (v_round2_id, v_p1, 60.0, 50.0, 70.0),
    (v_round2_id, v_p2, 80.0, 90.0, 70.0),
    (v_round2_id, v_p3, 50.0, 40.0, 60.0);
END $$;

-- =============================================================================
-- Test 1: Returns all 3 active participants
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::int FROM get_chat_leaderboard(current_setting('test.chat_id')::bigint)),
  3,
  'Leaderboard returns all 3 active participants'
);

-- =============================================================================
-- Test 2: User1 has avg of rounds 1+2 = (80+60)/2 = 70
-- =============================================================================
SELECT is(
  (SELECT avg_rank FROM get_chat_leaderboard(current_setting('test.chat_id')::bigint)
   WHERE participant_id = current_setting('test.p1')::bigint),
  70.0::real,
  'User1 avg rank is (80+60)/2 = 70'
);

-- =============================================================================
-- Test 3: User2 has avg of rounds 1+2 = (40+80)/2 = 60
-- =============================================================================
SELECT is(
  (SELECT avg_rank FROM get_chat_leaderboard(current_setting('test.chat_id')::bigint)
   WHERE participant_id = current_setting('test.p2')::bigint),
  60.0::real,
  'User2 avg rank is (40+80)/2 = 60'
);

-- =============================================================================
-- Test 4: User3 only has round 2 (joined late) = 50
-- =============================================================================
SELECT is(
  (SELECT avg_rank FROM get_chat_leaderboard(current_setting('test.chat_id')::bigint)
   WHERE participant_id = current_setting('test.p3')::bigint),
  50.0::real,
  'User3 avg rank is 50 (only round 2, joined after round 1)'
);

-- =============================================================================
-- Test 5: User1 participated in 2 rounds
-- =============================================================================
SELECT is(
  (SELECT rounds_participated FROM get_chat_leaderboard(current_setting('test.chat_id')::bigint)
   WHERE participant_id = current_setting('test.p1')::bigint),
  2,
  'User1 participated in 2 rounds'
);

-- =============================================================================
-- Test 6: User3 has total_rounds = 1 (only round 2 eligible)
-- =============================================================================
SELECT is(
  (SELECT total_rounds FROM get_chat_leaderboard(current_setting('test.chat_id')::bigint)
   WHERE participant_id = current_setting('test.p3')::bigint),
  1,
  'User3 has 1 eligible round (joined after round 1)'
);

-- =============================================================================
-- Test 7: Results ordered by avg_rank DESC (User1=70 first)
-- =============================================================================
SELECT is(
  (SELECT display_name FROM get_chat_leaderboard(current_setting('test.chat_id')::bigint) LIMIT 1),
  'User1',
  'Leaderboard ordered by avg_rank DESC (User1 first with 70)'
);

SELECT * FROM finish();
ROLLBACK;
