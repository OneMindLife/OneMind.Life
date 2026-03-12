-- Tests for upsert_grid_ranking RPC
-- This function bypasses per-row RLS evaluation for better concurrency.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(9);

-- =============================================================================
-- SETUP
-- =============================================================================

-- Create test users in auth.users
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000b01'::uuid, 'authenticated', 'grid_test1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000b02'::uuid, 'authenticated', 'grid_test2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

-- Create chat
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Grid RPC Test Chat', 'Test grid ranking RPC', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1 INT;
  v_p2 INT;
  v_prop1 INT;
  v_prop2 INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Grid RPC Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

  -- Create cycle and round
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);

  -- Create participants
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000b01'::uuid, 'Grid User 1', FALSE, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000b02'::uuid, 'Grid User 2', FALSE, 'active')
  RETURNING id INTO v_p2;

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);

  -- Create propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_p1, 'Prop A') RETURNING id INTO v_prop1;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_p2, 'Prop B') RETURNING id INTO v_prop2;

  PERFORM set_config('test.prop1', v_prop1::TEXT, TRUE);
  PERFORM set_config('test.prop2', v_prop2::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: Function exists
-- =============================================================================
SELECT has_function('public', 'upsert_grid_ranking', ARRAY['bigint', 'bigint', 'bigint', 'real'],
  'upsert_grid_ranking(bigint, bigint, bigint, real) function exists');

-- =============================================================================
-- Test 2: Function is SECURITY DEFINER
-- =============================================================================
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'upsert_grid_ranking'),
  TRUE,
  'upsert_grid_ranking is SECURITY DEFINER'
);

-- =============================================================================
-- Test 3: User 1 can insert a rating
-- =============================================================================
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000b01';

SELECT lives_ok(
  format(
    $$SELECT upsert_grid_ranking(%s::bigint, %s::bigint, %s::bigint, 75.0::real)$$,
    current_setting('test.round_id'),
    current_setting('test.p1'),
    current_setting('test.prop2')
  ),
  'User 1 can upsert a grid ranking'
);

-- =============================================================================
-- Test 4: Rating was inserted correctly
-- =============================================================================
SELECT is(
  (SELECT grid_position FROM grid_rankings
   WHERE round_id = current_setting('test.round_id')::bigint
     AND participant_id = current_setting('test.p1')::bigint
     AND proposition_id = current_setting('test.prop2')::bigint),
  75.0::real,
  'Grid ranking was inserted with correct position'
);

-- =============================================================================
-- Test 5: User 1 can update (upsert) the same rating
-- =============================================================================
SELECT lives_ok(
  format(
    $$SELECT upsert_grid_ranking(%s::bigint, %s::bigint, %s::bigint, 25.0::real)$$,
    current_setting('test.round_id'),
    current_setting('test.p1'),
    current_setting('test.prop2')
  ),
  'User 1 can update existing grid ranking'
);

-- =============================================================================
-- Test 6: Rating was updated correctly
-- =============================================================================
SELECT is(
  (SELECT grid_position FROM grid_rankings
   WHERE round_id = current_setting('test.round_id')::bigint
     AND participant_id = current_setting('test.p1')::bigint
     AND proposition_id = current_setting('test.prop2')::bigint),
  25.0::real,
  'Grid ranking was updated to new position'
);

-- =============================================================================
-- Test 7: User 2 cannot rate as user 1's participant
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000b02';

SELECT throws_ok(
  format(
    $$SELECT upsert_grid_ranking(%s::bigint, %s::bigint, %s::bigint, 50.0::real)$$,
    current_setting('test.round_id'),
    current_setting('test.p1'),
    current_setting('test.prop2')
  ),
  'P0001',
  'Not the owner of this participant',
  'User 2 cannot rate as User 1'
);

-- =============================================================================
-- Test 8: Non-participant cannot rate
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000999';

SELECT throws_ok(
  $$SELECT upsert_grid_ranking(1::bigint, 9999::bigint, 1::bigint, 50.0::real)$$,
  'P0001',
  'Not the owner of this participant',
  'Non-participant gets rejected'
);

-- =============================================================================
-- Test 9: Invalid round_id returns error
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000b01';

SELECT throws_ok(
  format(
    $$SELECT upsert_grid_ranking(999999::bigint, %s::bigint, %s::bigint, 50.0::real)$$,
    current_setting('test.p1'),
    current_setting('test.prop2')
  ),
  'P0001',
  'Participant cannot access this round',
  'Invalid round_id raises exception'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
