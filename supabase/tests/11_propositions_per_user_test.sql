-- Propositions per user limit tests
-- Tests for the configurable propositions_per_user setting
BEGIN;
SET search_path TO public, extensions;
SELECT plan(20);

-- =============================================================================
-- DEFAULT VALUES
-- =============================================================================

-- Test 1: Default propositions_per_user is 1
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Default Limit Chat', 'Testing defaults', gen_random_uuid());

SELECT is(
  (SELECT propositions_per_user FROM chats WHERE name = 'Default Limit Chat'),
  1,
  'Default propositions_per_user is 1'
);

-- =============================================================================
-- CUSTOM VALUES
-- =============================================================================

-- Test 2: Can set propositions_per_user to 3
INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
VALUES ('Three Props Chat', 'Three per user', gen_random_uuid(), 3);

SELECT is(
  (SELECT propositions_per_user FROM chats WHERE name = 'Three Props Chat'),
  3,
  'propositions_per_user can be set to 3'
);

-- Test 3: Can set propositions_per_user to 10
INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
VALUES ('Ten Props Chat', 'Ten per user', gen_random_uuid(), 10);

SELECT is(
  (SELECT propositions_per_user FROM chats WHERE name = 'Ten Props Chat'),
  10,
  'propositions_per_user can be set to 10'
);

-- =============================================================================
-- CONSTRAINT: propositions_per_user >= 1
-- =============================================================================

-- Test 4: Cannot set propositions_per_user to 0
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
    VALUES ('Bad Chat', 'Zero props', gen_random_uuid(), 0)$$,
  '23514',  -- check_violation
  NULL,
  'propositions_per_user cannot be 0'
);

-- Test 5: Cannot set propositions_per_user to negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
    VALUES ('Bad Chat', 'Negative props', gen_random_uuid(), -1)$$,
  '23514',
  NULL,
  'propositions_per_user cannot be negative'
);

-- =============================================================================
-- LIMIT ENFORCEMENT WITH DEFAULT (1)
-- =============================================================================

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Default Limit Chat';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_round_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Tester', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  PERFORM set_config('test.default_chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.default_round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.default_participant_id', v_participant_id::TEXT, TRUE);
END $$;

-- Test 6: Can submit first proposition (limit=1)
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.default_round_id')::INT,
  current_setting('test.default_participant_id')::INT,
  'First Idea'
);

SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.default_round_id')::INT),
  1::bigint,
  'First proposition submitted successfully'
);

-- Test 7: Helper function returns correct count
SELECT is(
  public.count_participant_propositions_in_round(
    current_setting('test.default_participant_id')::INT,
    current_setting('test.default_round_id')::INT
  ),
  1,
  'count_participant_propositions_in_round returns 1'
);

-- Test 8: Helper function returns correct limit
SELECT is(
  public.get_propositions_limit_for_round(current_setting('test.default_round_id')::INT),
  1,
  'get_propositions_limit_for_round returns 1 for default chat'
);

-- =============================================================================
-- LIMIT ENFORCEMENT WITH CUSTOM (3)
-- =============================================================================

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Three Props Chat';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'proposing')
  RETURNING id INTO v_round_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat_id, gen_random_uuid(), 'Three Tester', TRUE, 'active')
  RETURNING id INTO v_participant_id;

  PERFORM set_config('test.three_chat_id', v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.three_round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.three_participant_id', v_participant_id::TEXT, TRUE);
END $$;

-- Test 9: Helper function returns correct limit for custom chat
SELECT is(
  public.get_propositions_limit_for_round(current_setting('test.three_round_id')::INT),
  3,
  'get_propositions_limit_for_round returns 3 for custom chat'
);

-- Test 10: Can submit first proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.three_round_id')::INT,
  current_setting('test.three_participant_id')::INT,
  'Idea One'
);

SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.three_round_id')::INT),
  1::bigint,
  'First of 3 propositions submitted'
);

-- Test 11: Can submit second proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.three_round_id')::INT,
  current_setting('test.three_participant_id')::INT,
  'Idea Two'
);

SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.three_round_id')::INT),
  2::bigint,
  'Second of 3 propositions submitted'
);

-- Test 12: Can submit third proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.three_round_id')::INT,
  current_setting('test.three_participant_id')::INT,
  'Idea Three'
);

SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.three_round_id')::INT),
  3::bigint,
  'Third of 3 propositions submitted'
);

-- Test 13: Count returns 3
SELECT is(
  public.count_participant_propositions_in_round(
    current_setting('test.three_participant_id')::INT,
    current_setting('test.three_round_id')::INT
  ),
  3,
  'count_participant_propositions_in_round returns 3 after 3 submissions'
);

-- =============================================================================
-- MULTIPLE PARTICIPANTS IN SAME ROUND
-- =============================================================================

DO $$
DECLARE
  v_participant2_id INT;
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (
    current_setting('test.three_chat_id')::INT,
    gen_random_uuid(),
    'Second User',
    FALSE,
    'active'
  )
  RETURNING id INTO v_participant2_id;

  PERFORM set_config('test.three_participant2_id', v_participant2_id::TEXT, TRUE);
END $$;

-- Test 14: Second participant can also submit (independent limits)
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.three_round_id')::INT,
  current_setting('test.three_participant2_id')::INT,
  'Second User Idea'
);

SELECT is(
  public.count_participant_propositions_in_round(
    current_setting('test.three_participant2_id')::INT,
    current_setting('test.three_round_id')::INT
  ),
  1,
  'Second participant has independent count (1)'
);

-- Test 15: Total propositions in round = 4 (3 from first, 1 from second)
SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.three_round_id')::INT),
  4::bigint,
  'Total 4 propositions in round (3 + 1 from different participants)'
);

-- =============================================================================
-- LIMIT RESETS PER ROUND
-- =============================================================================

DO $$
DECLARE
  v_cycle_id INT;
  v_round2_id INT;
BEGIN
  SELECT cycle_id INTO v_cycle_id FROM rounds WHERE id = current_setting('test.three_round_id')::INT;

  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 2, 'proposing')
  RETURNING id INTO v_round2_id;

  PERFORM set_config('test.three_round2_id', v_round2_id::TEXT, TRUE);
END $$;

-- Test 16: Count is 0 in new round (limit resets per round)
SELECT is(
  public.count_participant_propositions_in_round(
    current_setting('test.three_participant_id')::INT,
    current_setting('test.three_round2_id')::INT
  ),
  0,
  'Proposition count resets to 0 in new round'
);

-- Test 17: Can submit in new round
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.three_round2_id')::INT,
  current_setting('test.three_participant_id')::INT,
  'Round 2 Idea'
);

SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.three_round2_id')::INT),
  1::bigint,
  'Can submit propositions in new round'
);

-- =============================================================================
-- UPDATE LIMIT MID-CHAT
-- =============================================================================

-- Test 18: Can update propositions_per_user
UPDATE chats SET propositions_per_user = 5 WHERE name = 'Three Props Chat';

SELECT is(
  public.get_propositions_limit_for_round(current_setting('test.three_round2_id')::INT),
  5,
  'Limit updates when chat setting is changed'
);

-- Test 19: Can submit more after limit increased
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  current_setting('test.three_round2_id')::INT,
  current_setting('test.three_participant_id')::INT,
  'Round 2 Idea 2'
);

SELECT is(
  (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.three_round2_id')::INT),
  2::bigint,
  'Can submit more after limit increased'
);

-- =============================================================================
-- EDGE CASE: NULL PARTICIPANT
-- =============================================================================

-- Test 20: Count returns 0 for null participant
SELECT is(
  public.count_participant_propositions_in_round(
    NULL,
    current_setting('test.three_round_id')::INT
  ),
  0,
  'count_participant_propositions_in_round returns 0 for NULL participant'
);

SELECT * FROM finish();
ROLLBACK;
