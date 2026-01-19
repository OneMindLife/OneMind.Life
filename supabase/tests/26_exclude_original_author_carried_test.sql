-- Test: Original author excluded from rating carried propositions
-- Verifies that the original author of a proposition cannot rate it
-- even when it's carried forward to subsequent rounds
BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

-- =============================================================================
-- SETUP: Create auth users and test data
-- =============================================================================

-- Create test auth users
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'author@test.com', 'pass', NOW(), NOW(), NOW()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'user2@test.com', 'pass', NOW(), NOW(), NOW()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID, 'user3@test.com', 'pass', NOW(), NOW(), NOW());

DO $$
DECLARE
    v_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round1_id BIGINT;
    v_round2_id BIGINT;
    v_author_participant_id BIGINT;
    v_user2_participant_id BIGINT;
    v_user3_participant_id BIGINT;
    v_author_user_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_user2_id UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    v_user3_id UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_original_prop_id BIGINT;
    v_carried_prop_id BIGINT;
    v_user2_prop_id BIGINT;
    v_user3_prop_id BIGINT;
BEGIN
    -- Create chat
    INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Carried Author Test Chat', 'Testing carried proposition exclusion', v_author_user_id)
    RETURNING id INTO v_chat_id;

    -- Create participants with user_id
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_author_user_id, 'Original Author', TRUE, 'active')
    RETURNING id INTO v_author_participant_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user2_id, 'User 2', FALSE, 'active')
    RETURNING id INTO v_user2_participant_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user3_id, 'User 3', FALSE, 'active')
    RETURNING id INTO v_user3_participant_id;

    -- Create cycle
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    -- Create Round 1 in rating phase (already past proposing)
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'rating', NOW())
    RETURNING id INTO v_round1_id;

    -- Create propositions for Round 1
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_author_participant_id, 'Original Author Proposition')
    RETURNING id INTO v_original_prop_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_user2_participant_id, 'User 2 Proposition')
    RETURNING id INTO v_user2_prop_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round1_id, v_user3_participant_id, 'User 3 Proposition')
    RETURNING id INTO v_user3_prop_id;

    -- Create Round 2 in rating phase (simulating carry forward)
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 2, 'rating', NOW())
    RETURNING id INTO v_round2_id;

    -- Simulate carried proposition (from author, carried to round 2)
    -- The carried proposition keeps the original participant_id and has carried_from_id set
    INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (v_round2_id, v_author_participant_id, 'Original Author Proposition', v_original_prop_id)
    RETURNING id INTO v_carried_prop_id;

    -- Create new propositions for Round 2
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round2_id, v_user2_participant_id, 'User 2 Round 2 Proposition');

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round2_id, v_user3_participant_id, 'User 3 Round 2 Proposition');

    -- Store IDs in session settings for later reference
    PERFORM set_config('test.chat_id', v_chat_id::text, true);
    PERFORM set_config('test.cycle_id', v_cycle_id::text, true);
    PERFORM set_config('test.round1_id', v_round1_id::text, true);
    PERFORM set_config('test.round2_id', v_round2_id::text, true);
    PERFORM set_config('test.author_participant_id', v_author_participant_id::text, true);
    PERFORM set_config('test.user2_participant_id', v_user2_participant_id::text, true);
    PERFORM set_config('test.user3_participant_id', v_user3_participant_id::text, true);
    PERFORM set_config('test.original_prop_id', v_original_prop_id::text, true);
    PERFORM set_config('test.carried_prop_id', v_carried_prop_id::text, true);
    PERFORM set_config('test.author_user_id', v_author_user_id::text, true);
    PERFORM set_config('test.user2_id', v_user2_id::text, true);
END $$;

-- =============================================================================
-- TEST: get_original_author_user_id function
-- =============================================================================

-- Test 1: Get original author of non-carried proposition
SELECT is(
    get_original_author_user_id(current_setting('test.original_prop_id')::bigint),
    current_setting('test.author_user_id')::UUID,
    'get_original_author_user_id returns correct user_id for non-carried proposition'
);

-- Test 2: Get original author of carried proposition (should trace back to original)
SELECT is(
    get_original_author_user_id(current_setting('test.carried_prop_id')::bigint),
    current_setting('test.author_user_id')::UUID,
    'get_original_author_user_id traces carried proposition back to original author'
);

-- =============================================================================
-- TEST: Round 1 - Original author cannot rate own proposition
-- =============================================================================

-- Test 3: In Round 1, author should see 2 propositions (not their own)
SELECT is(
    (SELECT COUNT(*) FROM get_unranked_propositions(
        current_setting('test.round1_id')::bigint,
        current_setting('test.author_participant_id')::bigint,
        NULL
    )),
    2::bigint,
    'Round 1: Author sees 2 propositions (excludes own)'
);

-- Test 4: User 2 should see 2 propositions (excludes own)
SELECT is(
    (SELECT COUNT(*) FROM get_unranked_propositions(
        current_setting('test.round1_id')::bigint,
        current_setting('test.user2_participant_id')::bigint,
        NULL
    )),
    2::bigint,
    'Round 1: User 2 sees 2 propositions (excludes own)'
);

-- =============================================================================
-- TEST: Round 2 - Original author cannot rate carried proposition
-- =============================================================================

-- Test 5: In Round 2, author should see 2 propositions (excludes own NEW and CARRIED)
SELECT is(
    (SELECT COUNT(*) FROM get_unranked_propositions(
        current_setting('test.round2_id')::bigint,
        current_setting('test.author_participant_id')::bigint,
        NULL
    )),
    2::bigint,
    'Round 2: Author sees 2 propositions (excludes carried which is their own)'
);

-- Test 6: User 2 should see 2 propositions (can rate carried, excludes own)
SELECT is(
    (SELECT COUNT(*) FROM get_unranked_propositions(
        current_setting('test.round2_id')::bigint,
        current_setting('test.user2_participant_id')::bigint,
        NULL
    )),
    2::bigint,
    'Round 2: User 2 sees 2 propositions (can rate carried, excludes own)'
);

-- Test 7: Verify carried proposition is NOT in author's list
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM get_unranked_propositions(
            current_setting('test.round2_id')::bigint,
            current_setting('test.author_participant_id')::bigint,
            NULL
        )
        WHERE proposition_id = current_setting('test.carried_prop_id')::bigint
    ),
    'Round 2: Carried proposition NOT in authors unranked list'
);

-- Test 8: Verify carried proposition IS in user2's list
SELECT ok(
    EXISTS (
        SELECT 1 FROM get_unranked_propositions(
            current_setting('test.round2_id')::bigint,
            current_setting('test.user2_participant_id')::bigint,
            NULL
        )
        WHERE proposition_id = current_setting('test.carried_prop_id')::bigint
    ),
    'Round 2: Carried proposition IS in user2s unranked list'
);

-- =============================================================================
-- TEST: Edge case - Author leaves and rejoins (reactivates same participant)
-- Note: Due to unique constraint idx_unique_user_per_chat, rejoining reactivates
-- the same participant record rather than creating a new one
-- =============================================================================

DO $$
BEGIN
    -- "Leave" by setting status to left
    UPDATE participants
    SET status = 'left'
    WHERE id = current_setting('test.author_participant_id')::bigint;

    -- "Rejoin" - reactivates same participant record (unique constraint prevents new record)
    UPDATE participants
    SET status = 'active'
    WHERE id = current_setting('test.author_participant_id')::bigint;
END $$;

-- Test 9: After rejoining (same participant_id), author STILL cannot rate carried proposition
SELECT is(
    (SELECT COUNT(*) FROM get_unranked_propositions(
        current_setting('test.round2_id')::bigint,
        current_setting('test.author_participant_id')::bigint,
        NULL
    )),
    2::bigint,
    'After rejoining: Author STILL sees only 2 propositions (cannot rate carried)'
);

-- Test 10: Verify carried proposition is NOT in rejoined author's list
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM get_unranked_propositions(
            current_setting('test.round2_id')::bigint,
            current_setting('test.author_participant_id')::bigint,
            NULL
        )
        WHERE proposition_id = current_setting('test.carried_prop_id')::bigint
    ),
    'After rejoining: Carried proposition NOT in rejoined authors list'
);

SELECT * FROM finish();
ROLLBACK;
