-- RLS Policy Lockdown Tests
-- Verifies that vulnerable "Service role" USING(true) policies are removed
-- and replaced with properly scoped host/user policies.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(21);

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('11111111-1111-1111-1111-111111111111'::UUID, 'host@test.com', 'pass', NOW(), NOW(), NOW()),
  ('22222222-2222-2222-2222-222222222222'::UUID, 'user2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('33333333-3333-3333-3333-333333333333'::UUID, 'attacker@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
    v_chat_id BIGINT;
    v_host_participant_id BIGINT;
    v_user2_participant_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_prop_id BIGINT;
    v_host_user_id UUID := '11111111-1111-1111-1111-111111111111';
    v_user2_id UUID := '22222222-2222-2222-2222-222222222222';
BEGIN
    -- Create chat owned by host
    INSERT INTO chats (
        name, initial_message, creator_id,
        enable_ai_participant, proposing_minimum,
        proposing_threshold_count, proposing_threshold_percent
    )
    VALUES (
        'Security Test Chat', 'Testing RLS lockdown', v_host_user_id,
        FALSE, 10,
        NULL, NULL
    )
    RETURNING id INTO v_chat_id;

    -- Create host participant
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_host_user_id, 'Host User', TRUE, 'active')
    RETURNING id INTO v_host_participant_id;

    -- Create regular participant
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user2_id, 'User 2', FALSE, 'active')
    RETURNING id INTO v_user2_participant_id;

    -- Create cycle + round
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    -- Create a proposition for round_winners tests
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_participant_id, 'Test proposition')
    RETURNING id INTO v_prop_id;
    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    -- Create a join request for deny tests
    INSERT INTO join_requests (chat_id, user_id, display_name, status)
    VALUES (v_chat_id, v_user2_id, 'User 2', 'pending');

    -- Store IDs for later tests
    PERFORM set_config('test.chat_id', v_chat_id::text, true);
    PERFORM set_config('test.cycle_id', v_cycle_id::text, true);
    PERFORM set_config('test.round_id', v_round_id::text, true);
    PERFORM set_config('test.prop_id', v_prop_id::text, true);
    PERFORM set_config('test.host_participant_id', v_host_participant_id::text, true);
    PERFORM set_config('test.user2_participant_id', v_user2_participant_id::text, true);
END $$;

-- =============================================================================
-- TEST GROUP 1: Anon CANNOT exploit the old vulnerability
-- =============================================================================

-- Test 1: Anon cannot update chats (THE ACTUAL EXPLOIT)
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "33333333-3333-3333-3333-333333333333"}', true);

UPDATE chats SET description = 'Hacked' WHERE id = current_setting('test.chat_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT description FROM chats WHERE id = current_setting('test.chat_id')::bigint),
    NULL,
    'Anon attacker CANNOT update chat description (the exploit that triggered this fix)'
);

-- =============================================================================
-- TEST GROUP 2: Anon CANNOT write to service-role-only tables
-- =============================================================================

-- Test 2: Anon cannot insert into movda_config
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "33333333-3333-3333-3333-333333333333"}', true);

SELECT throws_ok(
    'INSERT INTO movda_config (k_factor, tau, gamma, initial_rating) VALUES (32, 400, 100, 1500)',
    NULL,
    'Anon CANNOT insert into movda_config'
);

-- Test 3: Anon cannot insert into proposition_movda_ratings
SELECT throws_ok(
    format(
        'INSERT INTO proposition_movda_ratings (proposition_id, round_id, initial_rating, final_rating, k_factor)
         VALUES (%s, %s, 1500, 1600, 32)',
        current_setting('test.prop_id'), current_setting('test.round_id')
    ),
    NULL,
    'Anon CANNOT insert into proposition_movda_ratings'
);

-- Test 4: Anon cannot insert into proposition_global_scores
SELECT throws_ok(
    format(
        'INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
         VALUES (%s, %s, 75.0)',
        current_setting('test.prop_id'), current_setting('test.round_id')
    ),
    NULL,
    'Anon CANNOT insert into proposition_global_scores'
);

-- Test 5: Anon cannot insert into user_voting_ranks
SELECT throws_ok(
    format(
        'INSERT INTO user_voting_ranks (round_id, participant_id, correct_pairs, total_pairs)
         VALUES (%s, %s, 5, 10)',
        current_setting('test.round_id'), current_setting('test.host_participant_id')
    ),
    NULL,
    'Anon CANNOT insert into user_voting_ranks'
);

-- Test 6: Anon cannot insert into user_proposing_ranks
SELECT throws_ok(
    format(
        'INSERT INTO user_proposing_ranks (round_id, participant_id, proposition_count)
         VALUES (%s, %s, 1)',
        current_setting('test.round_id'), current_setting('test.host_participant_id')
    ),
    NULL,
    'Anon CANNOT insert into user_proposing_ranks'
);

-- Test 7: Anon cannot insert into user_round_ranks
SELECT throws_ok(
    format(
        'INSERT INTO user_round_ranks (round_id, participant_id, rank)
         VALUES (%s, %s, 50.0)',
        current_setting('test.round_id'), current_setting('test.host_participant_id')
    ),
    NULL,
    'Anon CANNOT insert into user_round_ranks'
);

RESET ROLE;

-- =============================================================================
-- TEST GROUP 3: Non-host CANNOT perform host operations
-- =============================================================================

-- Test 8: Non-host cannot update chats
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

UPDATE chats SET name = 'Hijacked' WHERE id = current_setting('test.chat_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT name FROM chats WHERE id = current_setting('test.chat_id')::bigint),
    'Security Test Chat',
    'Non-host CANNOT update chat name'
);

-- Test 9: Non-host cannot update rounds
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::bigint),
    'proposing',
    'Non-host CANNOT update round phase'
);

-- Test 10: Non-host cannot insert cycles
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

SELECT throws_ok(
    format(
        'INSERT INTO cycles (chat_id) VALUES (%s)',
        current_setting('test.chat_id')
    ),
    NULL,
    'Non-host CANNOT insert cycles'
);

-- Test 11: Non-host cannot kick participants
UPDATE participants SET status = 'kicked'
WHERE id = current_setting('test.host_participant_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT status FROM participants WHERE id = current_setting('test.host_participant_id')::bigint),
    'active',
    'Non-host CANNOT kick other participants'
);

-- =============================================================================
-- TEST GROUP 4: Host CAN perform host operations
-- =============================================================================

-- Test 12: Host can update own chat
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

UPDATE chats SET last_activity_at = NOW() WHERE id = current_setting('test.chat_id')::bigint;

SELECT is(
    (SELECT COUNT(*) FROM chats
     WHERE id = current_setting('test.chat_id')::bigint
     AND last_activity_at IS NOT NULL),
    1::bigint,
    'Host CAN update own chat last_activity_at'
);

RESET ROLE;

-- Test 13: Host can create cycles in own chat
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

INSERT INTO cycles (chat_id) VALUES (current_setting('test.chat_id')::bigint);

RESET ROLE;

SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = current_setting('test.chat_id')::bigint),
    2::bigint,
    'Host CAN create cycles in own chat'
);

-- Test 14: Host can create rounds in own chat
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

-- Get the second cycle's id
DO $$
DECLARE
    v_new_cycle_id BIGINT;
BEGIN
    SELECT id INTO v_new_cycle_id FROM cycles
    WHERE chat_id = current_setting('test.chat_id')::bigint
    ORDER BY id DESC LIMIT 1;
    PERFORM set_config('test.new_cycle_id', v_new_cycle_id::text, true);
END $$;

RESET ROLE;

-- Need to insert as anon with host JWT
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
VALUES (current_setting('test.new_cycle_id')::bigint, 1, 'waiting', NOW());

RESET ROLE;

SELECT is(
    (SELECT COUNT(*) FROM rounds WHERE cycle_id = current_setting('test.new_cycle_id')::bigint),
    1::bigint,
    'Host CAN create rounds in own chat'
);

-- Test 15: Host can update rounds in own chat
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

UPDATE rounds SET phase = 'rating', phase_started_at = NOW()
WHERE id = current_setting('test.round_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::bigint),
    'rating',
    'Host CAN update round phase in own chat'
);

-- Restore phase for other tests
UPDATE rounds SET phase = 'proposing' WHERE id = current_setting('test.round_id')::bigint;

-- Test 16: Host can insert round_winners in own chat
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
VALUES (
    current_setting('test.round_id')::bigint,
    current_setting('test.prop_id')::bigint,
    1,
    85.0
);

RESET ROLE;

SELECT is(
    (SELECT COUNT(*) FROM round_winners WHERE round_id = current_setting('test.round_id')::bigint),
    1::bigint,
    'Host CAN insert round_winners in own chat'
);

-- =============================================================================
-- TEST GROUP 5: Host CAN manage participants and join requests
-- =============================================================================

-- Test 17: Host can kick a participant
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

UPDATE participants SET status = 'kicked'
WHERE id = current_setting('test.user2_participant_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT status FROM participants WHERE id = current_setting('test.user2_participant_id')::bigint),
    'kicked',
    'Host CAN kick participants in own chat'
);

-- Test 18: Host can deny join requests
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

UPDATE join_requests SET status = 'denied', resolved_at = NOW()
WHERE chat_id = current_setting('test.chat_id')::bigint
AND user_id = '22222222-2222-2222-2222-222222222222'::UUID;

RESET ROLE;

SELECT is(
    (SELECT status FROM join_requests
     WHERE chat_id = current_setting('test.chat_id')::bigint
     AND user_id = '22222222-2222-2222-2222-222222222222'::UUID),
    'denied',
    'Host CAN deny join requests for own chat'
);

-- =============================================================================
-- TEST GROUP 6: User CAN update own participant record
-- =============================================================================

-- Restore user2 to kicked so we can test reactivation
RESET ROLE;
UPDATE participants SET status = 'kicked'
WHERE id = current_setting('test.user2_participant_id')::bigint;

-- Test 19: User can update own participant record (reactivation)
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

UPDATE participants SET status = 'active', display_name = 'User 2 Reactivated'
WHERE id = current_setting('test.user2_participant_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT status FROM participants WHERE id = current_setting('test.user2_participant_id')::bigint),
    'active',
    'User CAN update own participant record (reactivation)'
);

-- =============================================================================
-- TEST GROUP 7: Attacker from different context cannot exploit
-- =============================================================================

-- Test 20: Attacker (not in chat) cannot update rounds
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "33333333-3333-3333-3333-333333333333"}', true);

UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round_id')::bigint;

RESET ROLE;

SELECT is(
    (SELECT phase FROM rounds WHERE id = current_setting('test.round_id')::bigint),
    'proposing',
    'Attacker (not in chat) CANNOT update rounds'
);

-- Test 21: Attacker cannot insert round_winners
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "33333333-3333-3333-3333-333333333333"}', true);

SELECT throws_ok(
    format(
        'INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
         VALUES (%s, %s, 1, 99.0)',
        current_setting('test.round_id'), current_setting('test.prop_id')
    ),
    NULL,
    'Attacker CANNOT insert round_winners'
);

RESET ROLE;

-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
