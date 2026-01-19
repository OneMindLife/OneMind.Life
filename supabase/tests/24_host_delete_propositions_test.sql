-- Host delete propositions tests
-- Tests that hosts can delete propositions during proposing phase only
-- Updated to use auth.uid() instead of session tokens.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

-- Create test auth users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('11111111-1111-1111-1111-111111111111'::UUID, 'host@test.com', 'pass', NOW(), NOW(), NOW()),
  ('22222222-2222-2222-2222-222222222222'::UUID, 'user2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('33333333-3333-3333-3333-333333333333'::UUID, 'user3@test.com', 'pass', NOW(), NOW(), NOW()),
  ('44444444-4444-4444-4444-444444444444'::UUID, 'otherhost@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
    v_chat_id BIGINT;
    v_host_participant_id BIGINT;
    v_user2_participant_id BIGINT;
    v_user3_participant_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_prop_id BIGINT;
    v_user2_prop_id BIGINT;
    v_user3_prop_id BIGINT;
    v_host_user_id UUID := '11111111-1111-1111-1111-111111111111';
    v_user2_id UUID := '22222222-2222-2222-2222-222222222222';
    v_user3_id UUID := '33333333-3333-3333-3333-333333333333';
BEGIN
    -- Create main chat
    INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Delete Test Chat', 'Testing proposition deletion', v_host_user_id)
    RETURNING id INTO v_chat_id;

    -- Create participants with user_id
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_host_user_id, 'Host User', TRUE, 'active')
    RETURNING id INTO v_host_participant_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user2_id, 'User 2', FALSE, 'active')
    RETURNING id INTO v_user2_participant_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user3_id, 'User 3', FALSE, 'active')
    RETURNING id INTO v_user3_participant_id;

    -- Create cycle
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Create round in PROPOSING phase
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    -- Create propositions
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_participant_id, 'Host proposition')
    RETURNING id INTO v_host_prop_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_participant_id, 'User 2 proposition')
    RETURNING id INTO v_user2_prop_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user3_participant_id, 'User 3 proposition')
    RETURNING id INTO v_user3_prop_id;

    -- Store IDs in session settings for later reference
    PERFORM set_config('test.chat_id', v_chat_id::text, true);
    PERFORM set_config('test.round_id', v_round_id::text, true);
    PERFORM set_config('test.host_prop_id', v_host_prop_id::text, true);
    PERFORM set_config('test.user2_prop_id', v_user2_prop_id::text, true);
    PERFORM set_config('test.user3_prop_id', v_user3_prop_id::text, true);
    PERFORM set_config('test.user2_participant_id', v_user2_participant_id::text, true);
    PERFORM set_config('test.host_participant_id', v_host_participant_id::text, true);
END $$;

-- =============================================================================
-- TEST: Host can delete propositions during proposing phase
-- =============================================================================

-- Test 1: Verify all 3 propositions exist initially
SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::bigint),
    3::bigint,
    'Initially 3 propositions exist'
);

-- Switch to anon role to have RLS applied
SET ROLE anon;

-- Set auth context to host user
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

-- Test 2: Host can delete another user's proposition during proposing phase
DELETE FROM propositions WHERE id = current_setting('test.user2_prop_id')::bigint;

SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::bigint),
    2::bigint,
    'Host can delete proposition during proposing phase'
);

-- Test 3: Proposition is actually deleted
SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE id = current_setting('test.user2_prop_id')::bigint),
    0::bigint,
    'Deleted proposition no longer exists'
);

-- Reset to postgres to restore the proposition
RESET ROLE;

-- Re-add the proposition for next test (bypassing proposition limit trigger)
DO $$
DECLARE
    v_new_prop_id BIGINT;
BEGIN
    -- Temporarily disable the trigger
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (
        current_setting('test.round_id')::bigint,
        current_setting('test.user2_participant_id')::bigint,
        'User 2 proposition restored'
    )
    RETURNING id INTO v_new_prop_id;

    -- Re-enable the trigger
    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    PERFORM set_config('test.user2_prop_id', v_new_prop_id::text, true);
END $$;

-- =============================================================================
-- TEST: Non-host cannot delete propositions
-- =============================================================================

-- Switch to anon role with non-host auth context
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222"}', true);

-- Test 4: Non-host cannot delete propositions (DELETE should affect 0 rows)
DELETE FROM propositions WHERE id = current_setting('test.user3_prop_id')::bigint;

SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE id = current_setting('test.user3_prop_id')::bigint),
    1::bigint,
    'Non-host cannot delete propositions - proposition still exists'
);

-- =============================================================================
-- TEST: Host cannot delete during rating phase
-- =============================================================================

-- Reset to postgres to change the phase
RESET ROLE;
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round_id')::bigint;

-- Switch back to anon with host auth context
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

-- Test 5: Host cannot delete during rating phase (DELETE should affect 0 rows)
DELETE FROM propositions WHERE id = current_setting('test.user2_prop_id')::bigint;

SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE id = current_setting('test.user2_prop_id')::bigint),
    1::bigint,
    'Host cannot delete propositions during rating phase'
);

-- Test 6: Verify all remaining propositions still exist
SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::bigint),
    3::bigint,
    'All propositions still exist after failed delete attempt'
);

-- =============================================================================
-- TEST: Service role can always delete
-- =============================================================================

-- Reset and switch to service_role
RESET ROLE;
SET ROLE service_role;

-- Test 7: Service role can delete propositions in any phase
DELETE FROM propositions WHERE id = current_setting('test.user3_prop_id')::bigint;

SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE id = current_setting('test.user3_prop_id')::bigint),
    0::bigint,
    'Service role can delete propositions in any phase'
);

-- =============================================================================
-- TEST: Edge cases - wrong chat host cannot delete
-- =============================================================================

-- Reset to postgres to create another chat
RESET ROLE;

-- Create another chat with different host
DO $$
DECLARE
    v_other_chat_id BIGINT;
    v_other_host_participant_id BIGINT;
    v_other_host_id UUID := '44444444-4444-4444-4444-444444444444';
BEGIN
    INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Other Chat', 'Other chat', v_other_host_id)
    RETURNING id INTO v_other_chat_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_other_chat_id, v_other_host_id, 'Other Host', TRUE, 'active')
    RETURNING id INTO v_other_host_participant_id;
END $$;

-- Change round back to proposing for this test
UPDATE rounds SET phase = 'proposing' WHERE id = current_setting('test.round_id')::bigint;

-- Switch to anon with the OTHER chat's host auth context
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "44444444-4444-4444-4444-444444444444"}', true);

-- Test 8: Host of different chat cannot delete propositions
DELETE FROM propositions WHERE id = current_setting('test.host_prop_id')::bigint;

-- Reset to postgres to verify the proposition still exists (anon can't see it due to SELECT RLS)
RESET ROLE;

SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE id = current_setting('test.host_prop_id')::bigint),
    1::bigint,
    'Host of different chat cannot delete propositions'
);

-- Switch back to anon for the next test
SET ROLE anon;

-- =============================================================================
-- TEST: Correct host can still delete
-- =============================================================================

-- Set auth context back to correct host
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

-- Test 9: Correct host can delete
DELETE FROM propositions WHERE id = current_setting('test.host_prop_id')::bigint;

SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE id = current_setting('test.host_prop_id')::bigint),
    0::bigint,
    'Correct host can delete propositions in their chat'
);

-- Test 10: Verify only 1 proposition remains (user2's restored one)
SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::bigint),
    1::bigint,
    'Only 1 proposition remains after host deletion'
);

-- =============================================================================
-- TEST: Cascade delete behavior
-- =============================================================================

-- Reset to postgres to add ratings
RESET ROLE;

-- Add ratings to the remaining proposition
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (
    current_setting('test.user2_prop_id')::bigint,
    current_setting('test.host_participant_id')::bigint,
    75
);

-- Switch back to anon as host to delete
SET ROLE anon;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111"}', true);

-- Test 11: Deleting proposition cascades to ratings
DELETE FROM propositions WHERE id = current_setting('test.user2_prop_id')::bigint;

-- Reset to check ratings (need access)
RESET ROLE;

SELECT is(
    (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.user2_prop_id')::bigint),
    0::bigint,
    'Deleting proposition cascades to delete associated ratings'
);

-- Test 12: Round now has no propositions
SELECT is(
    (SELECT COUNT(*) FROM propositions WHERE round_id = current_setting('test.round_id')::bigint),
    0::bigint,
    'All propositions deleted from round'
);

SELECT * FROM finish();
ROLLBACK;
