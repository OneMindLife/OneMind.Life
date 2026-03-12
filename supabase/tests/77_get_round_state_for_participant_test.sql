-- Tests for get_round_state_for_participant RPC
-- Combined query replacing 4 separate RLS-evaluated PostgREST calls.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- SETUP
-- =============================================================================

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000d01'::uuid, 'authenticated', 'state_test1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000d02'::uuid, 'authenticated', 'state_test2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Round State RPC Test', 'Test combined state RPC', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1 INT;
  v_p2 INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Round State RPC Test';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

  -- Create participants
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000d01'::uuid, 'State User 1', FALSE, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_id, '00000000-0000-0000-0000-000000000d02'::uuid, 'State User 2', FALSE, 'active')
  RETURNING id INTO v_p2;

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);

  -- Create cycle and round in proposing phase
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- Test 1: Function exists
-- =============================================================================
SELECT has_function('public', 'get_round_state_for_participant', ARRAY['bigint', 'bigint'],
  'get_round_state_for_participant(bigint, bigint) function exists');

-- =============================================================================
-- Test 2: Function is SECURITY DEFINER
-- =============================================================================
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'get_round_state_for_participant'),
  TRUE,
  'get_round_state_for_participant is SECURITY DEFINER'
);

-- =============================================================================
-- Test 3: Returns correct phase
-- =============================================================================
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000d01';

SELECT is(
  (SELECT phase FROM get_round_state_for_participant(
    current_setting('test.chat_id')::bigint,
    current_setting('test.p1')::bigint
  )),
  'proposing',
  'Returns correct phase (proposing)'
);

-- =============================================================================
-- Test 4: Returns correct cycle_id
-- =============================================================================
SELECT is(
  (SELECT cycle_id FROM get_round_state_for_participant(
    current_setting('test.chat_id')::bigint,
    current_setting('test.p1')::bigint
  ))::text,
  current_setting('test.cycle_id'),
  'Returns correct cycle_id'
);

-- =============================================================================
-- Test 5: No proposition submitted yet
-- =============================================================================
SELECT is(
  (SELECT has_submitted_proposition FROM get_round_state_for_participant(
    current_setting('test.chat_id')::bigint,
    current_setting('test.p1')::bigint
  )),
  FALSE,
  'has_submitted_proposition is false before submitting'
);

-- =============================================================================
-- Test 6: No ratings submitted yet
-- =============================================================================
SELECT is(
  (SELECT has_submitted_ratings FROM get_round_state_for_participant(
    current_setting('test.chat_id')::bigint,
    current_setting('test.p1')::bigint
  )),
  FALSE,
  'has_submitted_ratings is false before rating'
);

-- =============================================================================
-- Test 7: After submitting proposition, flag is true
-- =============================================================================
RESET role;

INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  (current_setting('test.round_id'))::bigint,
  (current_setting('test.p1'))::bigint,
  'Test proposition'
);

SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000d01';

SELECT is(
  (SELECT has_submitted_proposition FROM get_round_state_for_participant(
    current_setting('test.chat_id')::bigint,
    current_setting('test.p1')::bigint
  )),
  TRUE,
  'has_submitted_proposition is true after submitting'
);

-- =============================================================================
-- Test 8: After submitting rating, flag is true
-- =============================================================================
RESET role;

-- Add a proposition from user 2 and a rating from user 1
DO $$
DECLARE
  v_prop2 INT;
BEGIN
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (
    current_setting('test.round_id')::bigint,
    current_setting('test.p2')::bigint,
    'Other proposition'
  ) RETURNING id INTO v_prop2;

  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  VALUES (
    current_setting('test.round_id')::bigint,
    current_setting('test.p1')::bigint,
    v_prop2,
    75.0
  );
END $$;

SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000d01';

SELECT is(
  (SELECT has_submitted_ratings FROM get_round_state_for_participant(
    current_setting('test.chat_id')::bigint,
    current_setting('test.p1')::bigint
  )),
  TRUE,
  'has_submitted_ratings is true after rating'
);

-- =============================================================================
-- Test 9: User 2 sees different submission status
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000d02';

SELECT is(
  (SELECT has_submitted_ratings FROM get_round_state_for_participant(
    current_setting('test.chat_id')::bigint,
    current_setting('test.p2')::bigint
  )),
  FALSE,
  'User 2 has not submitted ratings'
);

-- =============================================================================
-- Test 10: Non-participant gets rejected
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000999';

SELECT throws_ok(
  format(
    $$SELECT * FROM get_round_state_for_participant(%s::bigint, %s::bigint)$$,
    current_setting('test.chat_id'),
    current_setting('test.p1')
  ),
  'P0001',
  'Not an active participant in this chat',
  'Non-participant gets rejected'
);

-- =============================================================================
-- Test 11: Wrong participant for user gets rejected
-- =============================================================================
RESET role;
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000d02';

SELECT throws_ok(
  format(
    $$SELECT * FROM get_round_state_for_participant(%s::bigint, %s::bigint)$$,
    current_setting('test.chat_id'),
    current_setting('test.p1')
  ),
  'P0001',
  'Not an active participant in this chat',
  'User 2 cannot query as User 1 participant'
);

-- =============================================================================
-- Test 12: Returns empty when no cycle exists
-- =============================================================================
RESET role;

-- Create a chat with no cycles
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Empty State Test', 'No cycles', gen_random_uuid());

DO $$
DECLARE
  v_empty_chat_id INT;
  v_empty_p INT;
BEGIN
  SELECT id INTO v_empty_chat_id FROM chats WHERE name = 'Empty State Test';

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_empty_chat_id, '00000000-0000-0000-0000-000000000d01'::uuid, 'Empty User', FALSE, 'active')
  RETURNING id INTO v_empty_p;

  PERFORM set_config('test.empty_chat_id', v_empty_chat_id::TEXT, TRUE);
  PERFORM set_config('test.empty_p', v_empty_p::TEXT, TRUE);
END $$;

SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000d01';

SELECT is(
  (SELECT count(*)::int FROM get_round_state_for_participant(
    current_setting('test.empty_chat_id')::bigint,
    current_setting('test.empty_p')::bigint
  )),
  0,
  'Returns empty result when no cycle exists'
);

-- =============================================================================
-- CLEANUP
-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
