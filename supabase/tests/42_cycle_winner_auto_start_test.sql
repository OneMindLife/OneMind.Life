-- Test: Optimize round creation to skip waiting phase when auto-start conditions are met
-- This tests that when a new round is created (within same cycle OR new cycle),
-- it starts in proposing phase immediately (not waiting phase) if auto-start conditions are met

BEGIN;

SELECT plan(16);

-- =============================================================================
-- Test 1-4: Auto-mode with enough participants - round should start in proposing
-- =============================================================================

-- Create an auto-mode chat with 3 participants (threshold=3)
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count, proposing_duration_seconds, rating_duration_seconds, confirmation_rounds_required, access_method)
VALUES ('Cycle Winner Auto Start Test 1', 'Test consensus auto-start', 'auto', 3, 300, 300, 1, 'code')
RETURNING id AS chat_id \gset

-- Add 3 participants (meets threshold)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:chat_id, '11111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active'),
    (:chat_id, '22222222-2222-2222-2222-222222222222', 'User 1', FALSE, 'active'),
    (:chat_id, '33333333-3333-3333-3333-333333333333', 'User 2', FALSE, 'active');

-- Auto-start should have triggered, get the cycle and round IDs
SELECT id AS cycle1_id FROM cycles WHERE chat_id = :chat_id LIMIT 1 \gset
SELECT id AS round1_id FROM rounds WHERE cycle_id = :cycle1_id LIMIT 1 \gset

-- Get participant ID for creating propositions
SELECT id AS participant_id FROM participants WHERE chat_id = :chat_id LIMIT 1 \gset

-- Create a proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (:round1_id, :participant_id, 'Winning Proposition')
RETURNING id AS prop_id \gset

-- Move to rating phase
UPDATE rounds SET phase = 'rating' WHERE id = :round1_id;

-- Add MOVDA rating for the proposition
INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
VALUES (:prop_id, :round1_id, 90);

-- Set the winner (this triggers on_round_winner_set -> consensus -> on_cycle_winner_set)
-- With confirmation_rounds_required=1, this should complete the cycle
UPDATE rounds
SET winning_proposition_id = :prop_id,
    is_sole_winner = TRUE
WHERE id = :round1_id;

-- Test 1: New cycle should be created after consensus
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :chat_id)::INTEGER,
    2,
    'New cycle created after consensus'
);

-- Get the new cycle
SELECT id AS cycle2_id FROM cycles WHERE chat_id = :chat_id ORDER BY id DESC LIMIT 1 \gset

-- Get the new round
SELECT id AS round2_id, phase, phase_started_at, phase_ends_at
FROM rounds WHERE cycle_id = :cycle2_id LIMIT 1 \gset

-- Test 2: New round should be in proposing phase (not waiting!)
SELECT is(
    (SELECT phase FROM rounds WHERE id = :round2_id),
    'proposing',
    'New round in proposing phase (auto-mode with enough participants)'
);

-- Test 3: phase_ends_at should be set
SELECT ok(
    (SELECT phase_ends_at IS NOT NULL FROM rounds WHERE id = :round2_id),
    'phase_ends_at is set for auto-mode round'
);

-- Test 4: Timer should be aligned to :00 seconds
SELECT is(
    (SELECT EXTRACT(SECOND FROM phase_ends_at)::INTEGER FROM rounds WHERE id = :round2_id),
    0,
    'Timer aligned to :00 seconds'
);

-- =============================================================================
-- Test 5-8: Manual mode - round should start in waiting
-- =============================================================================

-- Create a manual-mode chat
INSERT INTO chats (name, initial_message, start_mode, proposing_duration_seconds, rating_duration_seconds, confirmation_rounds_required, access_method)
VALUES ('Cycle Winner Manual Test', 'Test manual mode', 'manual', 300, 300, 1, 'code')
RETURNING id AS manual_chat_id \gset

-- Add participants
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:manual_chat_id, '44444444-4444-4444-4444-444444444444', 'Host', TRUE, 'active'),
    (:manual_chat_id, '55555555-5555-5555-5555-555555555555', 'User 1', FALSE, 'active'),
    (:manual_chat_id, '66666666-6666-6666-6666-666666666666', 'User 2', FALSE, 'active');

-- Manually create cycle and round for manual mode
INSERT INTO cycles (chat_id)
VALUES (:manual_chat_id)
RETURNING id AS manual_cycle1_id \gset

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
VALUES (:manual_cycle1_id, 1, 'proposing', NOW())
RETURNING id AS manual_round1_id \gset

-- Get participant ID
SELECT id AS manual_participant_id FROM participants WHERE chat_id = :manual_chat_id LIMIT 1 \gset

-- Create and rate a proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (:manual_round1_id, :manual_participant_id, 'Manual Mode Proposition')
RETURNING id AS manual_prop_id \gset

UPDATE rounds SET phase = 'rating' WHERE id = :manual_round1_id;

INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
VALUES (:manual_prop_id, :manual_round1_id, 90);

-- Set winner (triggers consensus)
UPDATE rounds
SET winning_proposition_id = :manual_prop_id,
    is_sole_winner = TRUE
WHERE id = :manual_round1_id;

-- Test 5: New cycle created for manual mode
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :manual_chat_id)::INTEGER,
    2,
    'New cycle created for manual mode'
);

-- Get the new cycle and round
SELECT id AS manual_cycle2_id FROM cycles WHERE chat_id = :manual_chat_id ORDER BY id DESC LIMIT 1 \gset
SELECT id AS manual_round2_id FROM rounds WHERE cycle_id = :manual_cycle2_id LIMIT 1 \gset

-- Test 6: Manual mode round should be in waiting phase
SELECT is(
    (SELECT phase FROM rounds WHERE id = :manual_round2_id),
    'waiting',
    'Manual mode round in waiting phase'
);

-- Test 7: phase_ends_at should be NULL for waiting phase
SELECT ok(
    (SELECT phase_ends_at IS NULL FROM rounds WHERE id = :manual_round2_id),
    'phase_ends_at is NULL for manual mode waiting round'
);

-- Test 8: phase_started_at should be NULL for waiting phase
SELECT ok(
    (SELECT phase_started_at IS NULL FROM rounds WHERE id = :manual_round2_id),
    'phase_started_at is NULL for manual mode waiting round'
);

-- =============================================================================
-- Test 9-12: Auto-mode with insufficient participants - round in waiting
-- =============================================================================

-- Create an auto-mode chat with high threshold
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count, proposing_duration_seconds, rating_duration_seconds, confirmation_rounds_required, access_method)
VALUES ('Cycle Winner Insufficient Test', 'Test insufficient participants', 'auto', 10, 300, 300, 1, 'code')
RETURNING id AS insufficient_chat_id \gset

-- Add only 3 participants (below threshold of 10)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:insufficient_chat_id, '77777777-7777-7777-7777-777777777777', 'Host', TRUE, 'active'),
    (:insufficient_chat_id, '88888888-8888-8888-8888-888888888888', 'User 1', FALSE, 'active'),
    (:insufficient_chat_id, '99999999-9999-9999-9999-999999999999', 'User 2', FALSE, 'active');

-- Manually create cycle and round (since auto-start threshold not met)
INSERT INTO cycles (chat_id)
VALUES (:insufficient_chat_id)
RETURNING id AS insuf_cycle1_id \gset

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
VALUES (:insuf_cycle1_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
RETURNING id AS insuf_round1_id \gset

-- Get participant ID
SELECT id AS insuf_participant_id FROM participants WHERE chat_id = :insufficient_chat_id LIMIT 1 \gset

-- Create and rate a proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (:insuf_round1_id, :insuf_participant_id, 'Insufficient Test Proposition')
RETURNING id AS insuf_prop_id \gset

UPDATE rounds SET phase = 'rating' WHERE id = :insuf_round1_id;

INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
VALUES (:insuf_prop_id, :insuf_round1_id, 90);

-- Set winner (triggers consensus)
UPDATE rounds
SET winning_proposition_id = :insuf_prop_id,
    is_sole_winner = TRUE
WHERE id = :insuf_round1_id;

-- Test 9: New cycle created
SELECT is(
    (SELECT COUNT(*) FROM cycles WHERE chat_id = :insufficient_chat_id)::INTEGER,
    2,
    'New cycle created for auto-mode with insufficient participants'
);

-- Get the new cycle and round
SELECT id AS insuf_cycle2_id FROM cycles WHERE chat_id = :insufficient_chat_id ORDER BY id DESC LIMIT 1 \gset
SELECT id AS insuf_round2_id FROM rounds WHERE cycle_id = :insuf_cycle2_id LIMIT 1 \gset

-- Test 10: Round should be in waiting phase (auto-start conditions not met)
SELECT is(
    (SELECT phase FROM rounds WHERE id = :insuf_round2_id),
    'waiting',
    'Auto-mode round in waiting phase when insufficient participants'
);

-- Test 11: phase_ends_at should be NULL
SELECT ok(
    (SELECT phase_ends_at IS NULL FROM rounds WHERE id = :insuf_round2_id),
    'phase_ends_at is NULL when auto-start conditions not met'
);

-- Test 12: Winner should still have been carried forward correctly
-- (The previous cycle should have the winning_proposition_id set)
SELECT ok(
    (SELECT winning_proposition_id = :insuf_prop_id FROM cycles WHERE id = :insuf_cycle1_id),
    'Winner correctly set on completed cycle'
);

-- =============================================================================
-- Test 13-16: New round within same cycle (consensus not reached yet)
-- =============================================================================

-- Create an auto-mode chat with confirmation_rounds_required=2
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count, proposing_duration_seconds, rating_duration_seconds, confirmation_rounds_required, access_method)
VALUES ('Same Cycle New Round Test', 'Test new round within cycle', 'auto', 3, 300, 300, 2, 'code')
RETURNING id AS same_cycle_chat_id \gset

-- Add 3 participants (meets threshold)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:same_cycle_chat_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active'),
    (:same_cycle_chat_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User 1', FALSE, 'active'),
    (:same_cycle_chat_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'User 2', FALSE, 'active');

-- Get cycle and round IDs
SELECT id AS same_cycle_id FROM cycles WHERE chat_id = :same_cycle_chat_id LIMIT 1 \gset
SELECT id AS same_round1_id FROM rounds WHERE cycle_id = :same_cycle_id LIMIT 1 \gset
SELECT id AS same_participant_id FROM participants WHERE chat_id = :same_cycle_chat_id LIMIT 1 \gset

-- Create a proposition
INSERT INTO propositions (round_id, participant_id, content)
VALUES (:same_round1_id, :same_participant_id, 'Same Cycle Proposition')
RETURNING id AS same_prop_id \gset

-- Move to rating phase
UPDATE rounds SET phase = 'rating' WHERE id = :same_round1_id;

-- Add MOVDA rating
INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
VALUES (:same_prop_id, :same_round1_id, 90);

-- Set the winner - with confirmation_rounds_required=2, this should NOT complete the cycle
-- but should create a NEW round in the SAME cycle
UPDATE rounds
SET winning_proposition_id = :same_prop_id,
    is_sole_winner = TRUE
WHERE id = :same_round1_id;

-- Test 13: Cycle should NOT be completed (need 2 consecutive wins)
SELECT ok(
    (SELECT winning_proposition_id IS NULL FROM cycles WHERE id = :same_cycle_id),
    'Cycle not completed after first win (need 2 consecutive)'
);

-- Test 14: A second round should be created in the same cycle
SELECT is(
    (SELECT COUNT(*) FROM rounds WHERE cycle_id = :same_cycle_id)::INTEGER,
    2,
    'Second round created in same cycle'
);

-- Get the new round
SELECT id AS same_round2_id FROM rounds WHERE cycle_id = :same_cycle_id AND custom_id = 2 \gset

-- Test 15: New round should be in proposing phase (not waiting!)
SELECT is(
    (SELECT phase FROM rounds WHERE id = :same_round2_id),
    'proposing',
    'New round within same cycle in proposing phase (auto-mode)'
);

-- Test 16: phase_ends_at should be set
SELECT ok(
    (SELECT phase_ends_at IS NOT NULL FROM rounds WHERE id = :same_round2_id),
    'phase_ends_at is set for new round within same cycle'
);

SELECT * FROM finish();

ROLLBACK;
