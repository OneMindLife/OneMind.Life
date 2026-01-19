-- =============================================================================
-- TEST: complete_round_with_winner calculates MOVDA and populates round_winners
-- =============================================================================
BEGIN;
SELECT plan(8);

-- Setup: Create test users
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
VALUES
  ('a1111111-1111-1111-1111-111111111111', 'host@test.com', 'authenticated', 'authenticated', now(), now()),
  ('a2222222-2222-2222-2222-222222222222', 'user2@test.com', 'authenticated', 'authenticated', now(), now()),
  ('a3333333-3333-3333-3333-333333333333', 'user3@test.com', 'authenticated', 'authenticated', now(), now());

-- Create all test data using DO block with variables
DO $$
DECLARE
  v_chat_id BIGINT;
  v_cycle_id BIGINT;
  v_round_id BIGINT;
  v_host_participant_id BIGINT;
  v_user2_participant_id BIGINT;
  v_user3_participant_id BIGINT;
  v_prop_a_id BIGINT;
  v_prop_b_id BIGINT;
  v_prop_c_id BIGINT;
BEGIN
  -- Create chat
  -- IMPORTANT: Set rating_threshold_count to 999 to prevent early advance trigger
  -- from firing when we insert ratings. We want to test complete_round_with_winner manually.
  INSERT INTO chats (
    name, initial_message, creator_id, creator_session_token,
    invite_code, access_method, start_mode,
    rating_threshold_count, confirmation_rounds_required
  ) VALUES (
    'Test Complete Round', 'Test',
    'a1111111-1111-1111-1111-111111111111',
    'a4444444-4444-4444-4444-444444444444',
    'TESTCR', 'code', 'auto', 999, 2
  ) RETURNING id INTO v_chat_id;

  -- Create cycle
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- Create round in rating phase
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  -- Create participants
  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, 'a1111111-1111-1111-1111-111111111111', 'Host', 'active', true)
  RETURNING id INTO v_host_participant_id;

  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, 'a2222222-2222-2222-2222-222222222222', 'User2', 'active', false)
  RETURNING id INTO v_user2_participant_id;

  INSERT INTO participants (chat_id, user_id, display_name, status, is_host)
  VALUES (v_chat_id, 'a3333333-3333-3333-3333-333333333333', 'User3', 'active', false)
  RETURNING id INTO v_user3_participant_id;

  -- Create propositions
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_host_participant_id, 'Proposition A')
  RETURNING id INTO v_prop_a_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_user2_participant_id, 'Proposition B')
  RETURNING id INTO v_prop_b_id;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_user3_participant_id, 'Proposition C')
  RETURNING id INTO v_prop_c_id;

  -- Add ratings
  -- User2 rates: A=100, C=0
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user2_participant_id, v_round_id, v_prop_a_id, 100);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user2_participant_id, v_round_id, v_prop_c_id, 0);

  -- User3 rates: A=100, B=0
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user3_participant_id, v_round_id, v_prop_a_id, 100);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_user3_participant_id, v_round_id, v_prop_b_id, 0);

  -- Host rates: B=100, C=0
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_host_participant_id, v_round_id, v_prop_b_id, 100);
  INSERT INTO grid_rankings (participant_id, round_id, proposition_id, grid_position)
  VALUES (v_host_participant_id, v_round_id, v_prop_c_id, 0);
END $$;

-- TEST 1: proposition_global_scores should be empty before completing
SELECT is(
  (SELECT COUNT(*)::int FROM proposition_global_scores pgs
   JOIN propositions p ON pgs.proposition_id = p.id
   JOIN rounds r ON p.round_id = r.id
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR'),
  0,
  'MOVDA scores should not exist before complete_round_with_winner'
);

-- TEST 2: round_winners should be empty before completing
SELECT is(
  (SELECT COUNT(*)::int FROM round_winners rw
   JOIN rounds r ON rw.round_id = r.id
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR'),
  0,
  'round_winners should be empty before complete_round_with_winner'
);

-- ACTION: Call complete_round_with_winner
SELECT complete_round_with_winner(
  (SELECT r.id FROM rounds r
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR' AND r.custom_id = 1)
);

-- TEST 3: MOVDA scores should now exist
SELECT ok(
  (SELECT COUNT(*) FROM proposition_global_scores pgs
   JOIN propositions p ON pgs.proposition_id = p.id
   JOIN rounds r ON p.round_id = r.id
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR') > 0,
  'MOVDA scores should be calculated after complete_round_with_winner'
);

-- TEST 4: round_winners should be populated
SELECT ok(
  (SELECT COUNT(*) FROM round_winners rw
   JOIN rounds r ON rw.round_id = r.id
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR' AND r.custom_id = 1) > 0,
  'round_winners should be populated after complete_round_with_winner'
);

-- TEST 5: Round should be completed with a winner
SELECT ok(
  (SELECT r.winning_proposition_id IS NOT NULL FROM rounds r
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR' AND r.custom_id = 1),
  'Round should have winning_proposition_id set'
);

-- TEST 6: Round should be marked completed
SELECT ok(
  (SELECT r.completed_at IS NOT NULL FROM rounds r
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR' AND r.custom_id = 1),
  'Round should have completed_at set'
);

-- TEST 7: Next round should be created (since we need 2 wins for consensus)
SELECT is(
  (SELECT COUNT(*)::int FROM rounds r
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR'),
  2,
  'Next round should be created (consensus not yet reached)'
);

-- TEST 8: Carried forward proposition should exist in new round
SELECT ok(
  (SELECT COUNT(*) FROM propositions p
   JOIN rounds r ON p.round_id = r.id
   JOIN cycles cy ON r.cycle_id = cy.id
   JOIN chats c ON cy.chat_id = c.id
   WHERE c.invite_code = 'TESTCR' AND r.custom_id = 2 AND p.carried_from_id IS NOT NULL) > 0,
  'Carried forward proposition should exist in next round'
);

SELECT * FROM finish();
ROLLBACK;
