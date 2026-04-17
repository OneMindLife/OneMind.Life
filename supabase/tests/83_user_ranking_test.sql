-- =============================================================================
-- TEST: User Ranking Functions
-- Tests calculate_round_ranks penalizes missing rank components with 0
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(6);

-- =============================================================================
-- SETUP
-- =============================================================================

-- Create test users
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000c01'::uuid, 'authenticated', 'rank_test1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000c02'::uuid, 'authenticated', 'rank_test2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000c03'::uuid, 'authenticated', 'rank_test3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

-- Create chat (uses auto-generated IDs)
INSERT INTO chats (name, initial_message, creator_id)
VALUES ('Rank Test Chat', 'Test ranking?', '00000000-0000-0000-0000-000000000c01'::uuid);

DO $$
DECLARE
  v_chat_id BIGINT;
  v_cycle_id BIGINT;
  v_round_id BIGINT;
  v_p1 BIGINT;
  v_p2 BIGINT;
  v_p3 BIGINT;
  v_prop1 BIGINT;
  v_prop2 BIGINT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Rank Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

  -- Create cycle and round
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle_id, 1, 'rating', now(), now() + interval '5 minutes')
  RETURNING id INTO v_round_id;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);

  -- Create participants
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000c01'::uuid, 'User1', TRUE, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000c02'::uuid, 'User2', FALSE, 'active')
  RETURNING id INTO v_p2;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000c03'::uuid, 'User3', FALSE, 'active')
  RETURNING id INTO v_p3;

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);

  -- User1 and User2 proposed, User3 did NOT propose
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_p1, 'Prop from User1') RETURNING id INTO v_prop1;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_p2, 'Prop from User2') RETURNING id INTO v_prop2;

  PERFORM set_config('test.prop1', v_prop1::TEXT, TRUE);
  PERFORM set_config('test.prop2', v_prop2::TEXT, TRUE);

  -- Global scores: User1's prop scored higher
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score)
  VALUES
    (v_round_id, v_prop1, 80.0),
    (v_round_id, v_prop2, 40.0);

  -- All 3 users voted:
  -- User1: prop1=80, prop2=40 (matches global ordering perfectly)
  -- User2: prop1=30, prop2=70 (opposite of global ordering)
  -- User3: prop1=80, prop2=40 (matches global, but did NOT propose)
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  VALUES
    (v_round_id, v_p1, v_prop1, 80),
    (v_round_id, v_p1, v_prop2, 40),
    (v_round_id, v_p2, v_prop1, 30),
    (v_round_id, v_p2, v_prop2, 70),
    (v_round_id, v_p3, v_prop1, 80),
    (v_round_id, v_p3, v_prop2, 40);
END $$;

-- =============================================================================
-- Test 1: All 3 participants get ranks
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::int FROM calculate_round_ranks(current_setting('test.round_id')::bigint)),
  3,
  'All 3 participants get ranks'
);

-- =============================================================================
-- Test 2: User3 (voted but didn't propose) has NULL proposing_rank
-- =============================================================================
SELECT is(
  (SELECT proposing_rank FROM calculate_round_ranks(current_setting('test.round_id')::bigint)
   WHERE participant_id = current_setting('test.p3')::bigint),
  NULL::real,
  'User who only voted has NULL proposing_rank'
);

-- =============================================================================
-- Test 3: User3 (vote only, proposing=0) ranks lower than User1 (both)
-- =============================================================================
SELECT ok(
  (SELECT rank FROM calculate_round_ranks(current_setting('test.round_id')::bigint)
   WHERE participant_id = current_setting('test.p3')::bigint)
  <
  (SELECT rank FROM calculate_round_ranks(current_setting('test.round_id')::bigint)
   WHERE participant_id = current_setting('test.p1')::bigint),
  'Vote-only user ranks lower than user who both voted and proposed well'
);

-- =============================================================================
-- Test 4: User1 has both voting_rank and proposing_rank
-- =============================================================================
SELECT ok(
  (SELECT voting_rank IS NOT NULL AND proposing_rank IS NOT NULL
   FROM calculate_round_ranks(current_setting('test.round_id')::bigint)
   WHERE participant_id = current_setting('test.p1')::bigint),
  'Full participant has both voting_rank and proposing_rank'
);

-- =============================================================================
-- Test 5: Best overall performer (User1) gets rank 100
-- =============================================================================
SELECT is(
  (SELECT rank FROM calculate_round_ranks(current_setting('test.round_id')::bigint)
   WHERE participant_id = current_setting('test.p1')::bigint),
  100.0::real,
  'Best performer (perfect voter + best proposer) gets rank 100'
);

-- =============================================================================
-- Test 6: Worst overall performer (User2) gets rank 0
-- =============================================================================
SELECT is(
  (SELECT rank FROM calculate_round_ranks(current_setting('test.round_id')::bigint)
   WHERE participant_id = current_setting('test.p2')::bigint),
  0.0::real,
  'Worst performer (wrong voter + worst proposer) gets rank 0'
);

SELECT * FROM finish();
ROLLBACK;
