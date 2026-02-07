-- Security Hardening Wave 2 Tests
-- Tests for migration 20260207200000_security_hardening_wave2.sql
--
-- Covers:
-- A. Restrictive chats SELECT (public discoverable, private hidden)
-- B. get_chat_by_code() RPC
-- C. Access-method validation on participants INSERT
-- D. Cross-chat proposition injection blocked
-- E. Scoring function revocations
-- F. owns_participant() active-status check (kicked users blocked)
BEGIN;
SET search_path TO public, extensions;
SELECT plan(17);

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'host_w2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'user_w2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID, 'outsider_w2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd'::UUID, 'stranger_w2@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
    v_public_chat_id BIGINT;
    v_invite_chat_id BIGINT;
    v_code_chat_id BIGINT;
    v_host_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_user_id UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    v_outsider_id UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_host_participant_id BIGINT;
    v_user_participant_id BIGINT;
    v_kicked_participant_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_prop_id BIGINT;
    -- Chat B for cross-chat test
    v_chatB_id BIGINT;
    v_chatB_participant_id BIGINT;
    v_chatB_cycle_id BIGINT;
    v_chatB_round_id BIGINT;
BEGIN
    -- Create PUBLIC chat
    INSERT INTO chats (name, access_method, creator_id, enable_ai_participant, proposing_minimum, proposing_threshold_count, proposing_threshold_percent)
    VALUES ('Public Chat W2', 'public', v_host_id, FALSE, 10, NULL, NULL)
    RETURNING id INTO v_public_chat_id;

    -- Create INVITE_ONLY chat
    INSERT INTO chats (name, access_method, creator_id, enable_ai_participant, proposing_minimum, proposing_threshold_count, proposing_threshold_percent)
    VALUES ('Invite Only Chat W2', 'invite_only', v_host_id, FALSE, 10, NULL, NULL)
    RETURNING id INTO v_invite_chat_id;

    -- Create CODE chat
    INSERT INTO chats (name, access_method, invite_code, creator_id, enable_ai_participant, proposing_minimum, proposing_threshold_count, proposing_threshold_percent)
    VALUES ('Code Chat W2', 'code', 'TST2CD', v_host_id, FALSE, 10, NULL, NULL)
    RETURNING id INTO v_code_chat_id;

    -- Host is participant of invite_only chat
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_invite_chat_id, v_host_id, 'Host W2', TRUE, 'active')
    RETURNING id INTO v_host_participant_id;

    -- User is participant of invite_only chat
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_invite_chat_id, v_user_id, 'User W2', FALSE, 'active')
    RETURNING id INTO v_user_participant_id;

    -- Host is also participant of public chat
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_public_chat_id, v_host_id, 'Host W2', TRUE, 'active');

    -- Host is also participant of code chat
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_code_chat_id, v_host_id, 'Host W2', TRUE, 'active');

    -- Create cycle + round in invite_only chat
    INSERT INTO cycles (chat_id) VALUES (v_invite_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    -- Create a proposition for the rating test
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_participant_id, 'Host proposition W2')
    RETURNING id INTO v_prop_id;
    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    -- Create Chat B for cross-chat injection test
    INSERT INTO chats (name, access_method, creator_id, enable_ai_participant, proposing_minimum, proposing_threshold_count, proposing_threshold_percent)
    VALUES ('Chat B W2', 'public', v_host_id, FALSE, 10, NULL, NULL)
    RETURNING id INTO v_chatB_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chatB_id, v_outsider_id, 'Outsider in B', FALSE, 'active')
    RETURNING id INTO v_chatB_participant_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chatB_id, v_host_id, 'Host in B', TRUE, 'active');

    INSERT INTO cycles (chat_id) VALUES (v_chatB_id) RETURNING id INTO v_chatB_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_chatB_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_chatB_round_id;

    -- Create a kicked participant in invite_only chat for tests 11-12
    -- Uses outsider (cccccccc) who is also in Chat B
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_invite_chat_id, v_outsider_id, 'Kicked User', FALSE, 'kicked')
    RETURNING id INTO v_kicked_participant_id;

    -- Store all IDs
    PERFORM set_config('test.public_chat_id', v_public_chat_id::text, true);
    PERFORM set_config('test.invite_chat_id', v_invite_chat_id::text, true);
    PERFORM set_config('test.code_chat_id', v_code_chat_id::text, true);
    PERFORM set_config('test.host_participant_id', v_host_participant_id::text, true);
    PERFORM set_config('test.user_participant_id', v_user_participant_id::text, true);
    PERFORM set_config('test.kicked_participant_id', v_kicked_participant_id::text, true);
    PERFORM set_config('test.cycle_id', v_cycle_id::text, true);
    PERFORM set_config('test.round_id', v_round_id::text, true);
    PERFORM set_config('test.prop_id', v_prop_id::text, true);
    PERFORM set_config('test.chatB_id', v_chatB_id::text, true);
    PERFORM set_config('test.chatB_participant_id', v_chatB_participant_id::text, true);
    PERFORM set_config('test.chatB_round_id', v_chatB_round_id::text, true);
END $$;

-- =============================================================================
-- TEST GROUP 1: Chats SELECT visibility (Tests 1-4)
-- =============================================================================

-- Test 1: Stranger (no participant record anywhere relevant) cannot see invite_only chat
-- Uses dddddddd who has NO participant records at all
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

SELECT is(
    (SELECT COUNT(*) FROM chats WHERE id = current_setting('test.invite_chat_id')::bigint),
    0::bigint,
    'Non-participant CANNOT see invite_only chat'
);

RESET ROLE;

-- Test 2: Anon CAN see public chats
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

SELECT is(
    (SELECT COUNT(*) FROM chats WHERE id = current_setting('test.public_chat_id')::bigint),
    1::bigint,
    'Anyone CAN see public chats'
);

RESET ROLE;

-- Test 3: Participant can see their own invite_only chat
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', true);

SELECT is(
    (SELECT COUNT(*) FROM chats WHERE id = current_setting('test.invite_chat_id')::bigint),
    1::bigint,
    'Participant CAN see their own invite_only chat'
);

RESET ROLE;

-- Test 4: Non-participant cannot see code chat
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

SELECT is(
    (SELECT COUNT(*) FROM chats WHERE id = current_setting('test.code_chat_id')::bigint),
    0::bigint,
    'Non-participant CANNOT see code chat'
);

RESET ROLE;

-- =============================================================================
-- TEST GROUP 2: Participants INSERT access_method validation (Tests 5-8)
-- =============================================================================

-- Test 5: User cannot join invite_only chat via direct INSERT
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

SELECT throws_ok(
    format(
        'INSERT INTO participants (chat_id, user_id, display_name, status) VALUES (%s, %L, %L, %L)',
        current_setting('test.invite_chat_id'),
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'Sneaky Join',
        'active'
    ),
    NULL,
    'User CANNOT join invite_only chat via INSERT'
);

RESET ROLE;

-- Test 6: User CAN join public chat (as self)
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

INSERT INTO participants (chat_id, user_id, display_name, status)
VALUES (
    current_setting('test.public_chat_id')::bigint,
    'dddddddd-dddd-dddd-dddd-dddddddddddd'::UUID,
    'Stranger Public',
    'active'
);

RESET ROLE;

SELECT is(
    (SELECT COUNT(*) FROM participants
     WHERE chat_id = current_setting('test.public_chat_id')::bigint
     AND user_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'::UUID),
    1::bigint,
    'User CAN join public chat as self'
);

-- Test 7: User CAN join code chat (as self)
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', true);

INSERT INTO participants (chat_id, user_id, display_name, status)
VALUES (
    current_setting('test.code_chat_id')::bigint,
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID,
    'User Code',
    'active'
);

RESET ROLE;

SELECT is(
    (SELECT COUNT(*) FROM participants
     WHERE chat_id = current_setting('test.code_chat_id')::bigint
     AND user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID),
    1::bigint,
    'User CAN join code chat as self'
);

-- Test 8: User cannot join chat as different user
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

SELECT throws_ok(
    format(
        'INSERT INTO participants (chat_id, user_id, display_name, status) VALUES (%s, %L, %L, %L)',
        current_setting('test.public_chat_id'),
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'Impersonator',
        'active'
    ),
    NULL,
    'User CANNOT join chat as a different user'
);

RESET ROLE;

-- =============================================================================
-- TEST GROUP 3: Cross-chat proposition injection (Tests 9-10)
-- =============================================================================

-- Test 9: Cross-chat proposition injection blocked
-- Outsider is in Chat B but tries to submit proposition to Chat A's round

-- Disable trigger as postgres (need privileges)
ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-cccc-cccc-cccc-cccccccccccc"}', true);

SELECT throws_ok(
    format(
        'INSERT INTO propositions (round_id, participant_id, content) VALUES (%s, %s, %L)',
        current_setting('test.round_id'),
        current_setting('test.chatB_participant_id'),
        'Cross-chat injection!'
    ),
    NULL,
    'Cross-chat proposition injection BLOCKED'
);

RESET ROLE;

-- Test 10: Same-chat proposition succeeds
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', true);

INSERT INTO propositions (round_id, participant_id, content)
VALUES (
    current_setting('test.round_id')::bigint,
    current_setting('test.user_participant_id')::bigint,
    'Valid same-chat proposition'
);

RESET ROLE;

ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

SELECT is(
    (SELECT COUNT(*) FROM propositions
     WHERE round_id = current_setting('test.round_id')::bigint
     AND content = 'Valid same-chat proposition'),
    1::bigint,
    'Same-chat proposition SUCCEEDS'
);

-- =============================================================================
-- TEST GROUP 4: Kicked participant blocked (Tests 11-12)
-- =============================================================================

-- Test 11: Kicked participant cannot submit proposition
ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-cccc-cccc-cccc-cccccccccccc"}', true);

SELECT throws_ok(
    format(
        'INSERT INTO propositions (round_id, participant_id, content) VALUES (%s, %s, %L)',
        current_setting('test.round_id'),
        current_setting('test.kicked_participant_id'),
        'Kicked user proposition'
    ),
    NULL,
    'Kicked participant CANNOT submit proposition'
);

RESET ROLE;
ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

-- Test 12: Kicked participant cannot submit rating (via grid_rankings)
-- Change round to rating phase for this test
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round_id')::bigint;

SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-cccc-cccc-cccc-cccccccccccc"}', true);

SELECT throws_ok(
    format(
        'INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position) VALUES (%s, %s, %s, 50)',
        current_setting('test.round_id'),
        current_setting('test.kicked_participant_id'),
        current_setting('test.prop_id')
    ),
    NULL,
    'Kicked participant CANNOT submit rating'
);

RESET ROLE;

-- Restore phase
UPDATE rounds SET phase = 'proposing' WHERE id = current_setting('test.round_id')::bigint;

-- =============================================================================
-- TEST GROUP 5: Scoring function revocations (Tests 13-15)
-- =============================================================================

-- Test 13: Anon cannot call calculate_movda_scores_for_round directly
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

SELECT throws_ok(
    format(
        'SELECT calculate_movda_scores_for_round(%s)',
        current_setting('test.round_id')
    ),
    NULL,
    'Anon CANNOT call calculate_movda_scores_for_round directly'
);

RESET ROLE;

-- Test 14: Anon cannot call store_round_ranks directly
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-dddd-dddd-dddd-dddddddddddd"}', true);

SELECT throws_ok(
    format(
        'SELECT store_round_ranks(%s)',
        current_setting('test.round_id')
    ),
    NULL,
    'Anon CANNOT call store_round_ranks directly'
);

RESET ROLE;

-- Test 15: Non-host cannot call host_calculate_movda_scores wrapper
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', true);

SELECT throws_ok(
    format(
        'SELECT host_calculate_movda_scores(%s)',
        current_setting('test.round_id')
    ),
    NULL,
    'Non-host CANNOT call host_calculate_movda_scores'
);

RESET ROLE;

-- =============================================================================
-- TEST GROUP 6: get_chat_by_code RPC (Tests 16-17)
-- =============================================================================

-- Test 16: get_chat_by_code returns chat for valid code
SELECT is(
    (SELECT COUNT(*) FROM get_chat_by_code('TST2CD')),
    1::bigint,
    'get_chat_by_code returns chat for valid code'
);

-- Test 17: get_chat_by_code returns nothing for invalid code
SELECT is(
    (SELECT COUNT(*) FROM get_chat_by_code('BADCOD')),
    0::bigint,
    'get_chat_by_code returns nothing for invalid code'
);

-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
