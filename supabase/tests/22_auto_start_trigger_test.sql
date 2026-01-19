-- Test auto-start trigger for chats with start_mode = 'auto'
BEGIN;

-- Plan the test
SELECT plan(11);

-- Clean up any existing test data
DELETE FROM chats WHERE name LIKE 'Auto Start Test%';

-- =============================================================================
-- Test 1: Auto mode chat should NOT start when only 1-2 participants join (threshold=3)
-- =============================================================================

-- Create an auto mode chat with threshold of 3 (minimum allowed)
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count, proposing_duration_seconds, rating_duration_seconds, access_method)
VALUES ('Auto Start Test Chat 1', 'Test auto start', 'auto', 3, 300, 300, 'code')
RETURNING id AS chat_id \gset

-- Add first participant (host)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (:chat_id, '11111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active');

-- Verify no cycle created yet
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :chat_id)::INTEGER,
    0,
    'No cycle should be created when only 1 participant (threshold=3)'
);

-- Add second participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (:chat_id, '22222222-2222-2222-2222-222222222222', 'User 1', FALSE, 'active');

-- Verify no round created yet (still below threshold)
SELECT is(
    (SELECT COUNT(*) FROM rounds r JOIN cycles c ON r.cycle_id = c.id WHERE c.chat_id = :chat_id)::INTEGER,
    0,
    'No round should be created when only 2 participants (threshold=3)'
);

-- =============================================================================
-- Test 2: Auto mode chat SHOULD start when third participant joins (threshold=3)
-- =============================================================================

-- Add third participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (:chat_id, '33333333-3333-3333-3333-333333333333', 'User 2', FALSE, 'active');

-- Verify cycle was created
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :chat_id)::INTEGER,
    1,
    'Cycle should be created when 3rd participant joins (threshold=3)'
);

-- Verify round was created in proposing phase
SELECT is(
    (SELECT phase FROM rounds r JOIN cycles c ON r.cycle_id = c.id WHERE c.chat_id = :chat_id ORDER BY r.id LIMIT 1),
    'proposing',
    'Round should be created in proposing phase'
);

-- Verify phase_ends_at is set (auto mode uses timers)
SELECT ok(
    (SELECT phase_ends_at IS NOT NULL FROM rounds r JOIN cycles c ON r.cycle_id = c.id WHERE c.chat_id = :chat_id ORDER BY r.id LIMIT 1),
    'phase_ends_at should be set for auto mode'
);

-- =============================================================================
-- Test 3: Additional participants should NOT create more cycles
-- =============================================================================

-- Add fourth participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (:chat_id, '44444444-4444-4444-4444-444444444444', 'User 3', FALSE, 'active');

-- Verify still only one cycle
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :chat_id)::INTEGER,
    1,
    'Only one cycle should exist after more participants join'
);

-- =============================================================================
-- Test 4: Manual mode chat should NOT auto-start
-- =============================================================================

-- Create a manual mode chat
INSERT INTO chats (name, initial_message, start_mode, proposing_duration_seconds, rating_duration_seconds, access_method)
VALUES ('Auto Start Test Chat 2 - Manual', 'Test manual', 'manual', 300, 300, 'code')
RETURNING id AS manual_chat_id \gset

-- Add three participants
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:manual_chat_id, '55555555-5555-5555-5555-555555555555', 'Host', TRUE, 'active'),
    (:manual_chat_id, '66666666-6666-6666-6666-666666666666', 'User 1', FALSE, 'active'),
    (:manual_chat_id, '77777777-7777-7777-7777-777777777777', 'User 2', FALSE, 'active');

-- Verify no cycle created (manual mode requires host to start)
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :manual_chat_id)::INTEGER,
    0,
    'Manual mode chat should NOT auto-start when participants join'
);

-- =============================================================================
-- Test 5: Auto mode with higher threshold
-- =============================================================================

-- Create an auto mode chat with threshold of 5
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count, proposing_duration_seconds, rating_duration_seconds, access_method)
VALUES ('Auto Start Test Chat 3 - Threshold 5', 'Test high threshold', 'auto', 5, 300, 300, 'code')
RETURNING id AS high_threshold_chat_id \gset

-- Add 4 participants (not enough)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:high_threshold_chat_id, '88888888-8888-8888-8888-888888888888', 'Host', TRUE, 'active'),
    (:high_threshold_chat_id, '99999999-9999-9999-9999-999999999999', 'User 1', FALSE, 'active'),
    (:high_threshold_chat_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'User 2', FALSE, 'active'),
    (:high_threshold_chat_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User 3', FALSE, 'active');

-- Verify no cycle created yet
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :high_threshold_chat_id)::INTEGER,
    0,
    'No cycle when only 4 participants (threshold=5)'
);

-- Add 5th participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (:high_threshold_chat_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'User 4', FALSE, 'active');

-- Verify cycle was created now
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :high_threshold_chat_id)::INTEGER,
    1,
    'Cycle should be created when 5th participant joins (threshold=5)'
);

-- =============================================================================
-- Test 6: Pending participants should NOT count toward threshold
-- =============================================================================

-- Create an auto mode chat with approval required (threshold=3)
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count, proposing_duration_seconds, rating_duration_seconds, access_method, require_approval)
VALUES ('Auto Start Test Chat 4 - Approval', 'Test pending', 'auto', 3, 300, 300, 'code', TRUE)
RETURNING id AS approval_chat_id \gset

-- Add host and one active user (2 active)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:approval_chat_id, 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'Host', TRUE, 'active'),
    (:approval_chat_id, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'User 1', FALSE, 'active');

-- Add pending user
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (:approval_chat_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'User 2', FALSE, 'pending');

-- Verify no cycle (pending doesn't count, only 2 active)
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :approval_chat_id)::INTEGER,
    0,
    'Pending participants should NOT count toward auto-start threshold'
);

-- Approve the user (update status to active) - now have 3 active
UPDATE participants
SET status = 'active'
WHERE chat_id = :approval_chat_id AND session_token = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

-- Verify cycle was created after approval
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :approval_chat_id)::INTEGER,
    1,
    'Cycle should be created when pending user is approved (meets threshold=3)'
);

-- Finish the tests
SELECT * FROM finish();

ROLLBACK;
