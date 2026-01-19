-- Cascade delete behavior tests
-- Verifies that related records are properly deleted when parent records are deleted
BEGIN;
SET search_path TO public, extensions;
SELECT plan(5);

-- =============================================================================
-- SETUP
-- =============================================================================

-- Create a chat with full structure: chat -> cycle -> round -> propositions -> grid_rankings
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Cascade Test Chat', 'Testing cascade deletes', gen_random_uuid());

DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_participant_id INT;
    v_proposition_id INT;
BEGIN
    SELECT id INTO v_chat_id FROM chats WHERE name = 'Cascade Test Chat';
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);

    -- Create cycle
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO v_cycle_id;
    PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);

    -- Create round
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;
    PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);

    -- Create participant
    INSERT INTO participants (chat_id, display_name, session_token, is_host)
    VALUES (v_chat_id, 'Test User', gen_random_uuid(), TRUE)
    RETURNING id INTO v_participant_id;
    PERFORM set_config('test.participant_id', v_participant_id::TEXT, TRUE);

    -- Create proposition
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_participant_id, 'Test proposition')
    RETURNING id INTO v_proposition_id;
    PERFORM set_config('test.proposition_id', v_proposition_id::TEXT, TRUE);

    -- Create grid ranking
    INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
    VALUES (v_round_id, v_proposition_id, v_participant_id, 75);
END $$;

-- =============================================================================
-- TEST: Verify setup
-- =============================================================================

-- Test 1: Verify grid_rankings exists
SELECT is(
    (SELECT COUNT(*) FROM grid_rankings
     WHERE round_id = current_setting('test.round_id')::INT
     AND participant_id = current_setting('test.participant_id')::INT),
    1::bigint,
    'Grid ranking created successfully'
);

-- =============================================================================
-- TEST: Cascade delete behavior
-- =============================================================================

-- Test 2: Deleting participant cascades to grid_rankings
-- (This was the bug: ON DELETE SET NULL violated the check constraint)
DELETE FROM participants WHERE id = current_setting('test.participant_id')::INT;

SELECT is(
    (SELECT COUNT(*) FROM grid_rankings
     WHERE proposition_id = current_setting('test.proposition_id')::INT),
    0::bigint,
    'Grid rankings deleted when participant is deleted'
);

-- Test 3: Deleting chat cascades everything
-- Re-create structure for this test
DO $$
DECLARE
    v_chat_id INT;
    v_cycle_id INT;
    v_round_id INT;
    v_participant_id INT;
    v_proposition_id INT;
BEGIN
    INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Cascade Test Chat 2', 'Testing cascade deletes', gen_random_uuid())
    RETURNING id INTO v_chat_id;
    PERFORM set_config('test.chat_id2', v_chat_id::TEXT, TRUE);

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW()) RETURNING id INTO v_round_id;
    PERFORM set_config('test.round_id2', v_round_id::TEXT, TRUE);

    INSERT INTO participants (chat_id, display_name, session_token, is_host)
    VALUES (v_chat_id, 'Test User 2', gen_random_uuid(), TRUE) RETURNING id INTO v_participant_id;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_participant_id, 'Test proposition 2') RETURNING id INTO v_proposition_id;

    INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
    VALUES (v_round_id, v_proposition_id, v_participant_id, 50);
END $$;

-- Verify grid_rankings exist before delete
SELECT is(
    (SELECT COUNT(*) FROM grid_rankings
     WHERE round_id = current_setting('test.round_id2')::INT),
    1::bigint,
    'Grid rankings exist before chat delete'
);

-- Delete the chat
DELETE FROM chats WHERE id = current_setting('test.chat_id2')::INT;

-- Test 4: Grid rankings should be gone after chat delete
SELECT is(
    (SELECT COUNT(*) FROM grid_rankings
     WHERE round_id = current_setting('test.round_id2')::INT),
    0::bigint,
    'Grid rankings cascade deleted when chat is deleted'
);

-- Test 5: No orphaned grid_rankings with NULL participant_id exist
SELECT is(
    (SELECT COUNT(*) FROM grid_rankings
     WHERE participant_id IS NULL AND session_token IS NULL),
    0::bigint,
    'No orphaned grid_rankings with NULL identity'
);

SELECT * FROM finish();
ROLLBACK;
