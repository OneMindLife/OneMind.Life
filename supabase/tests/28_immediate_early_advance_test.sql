-- Tests for immediate early advance triggers
BEGIN;
SELECT plan(12);

-- =============================================================================
-- SETUP: Create test chat with early advance thresholds
-- =============================================================================

-- Create auto-mode chat with early advance enabled
-- Set auto_start_participant_count high to prevent auto-start trigger
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count,
    proposing_threshold_percent, proposing_threshold_count,
    rating_threshold_percent, rating_threshold_count,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_minimum, rating_minimum)
VALUES ('ImmediateAdvanceTest', 'Test', 'auto', 99,
    100, 3,  -- 100% or at least 3 participants for proposing
    NULL, 2, -- Average of 2 raters per proposition for rating (achievable with 3 users)
    300, 300,
    3, 2);

-- Add 3 participants (won't trigger auto-start since threshold is 99)
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'User 1', 'active', gen_random_uuid() FROM chats WHERE name = 'ImmediateAdvanceTest';
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'User 2', 'active', gen_random_uuid() FROM chats WHERE name = 'ImmediateAdvanceTest';
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'User 3', 'active', gen_random_uuid() FROM chats WHERE name = 'ImmediateAdvanceTest';

-- Manually create cycle and round in proposing phase
INSERT INTO cycles (chat_id)
SELECT id FROM chats WHERE name = 'ImmediateAdvanceTest';

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
SELECT c.id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes'
FROM cycles c
JOIN chats ch ON ch.id = c.chat_id
WHERE ch.name = 'ImmediateAdvanceTest';

-- =============================================================================
-- TEST: Helper function
-- =============================================================================

SELECT is(
    calculate_early_advance_required(100, 3, 10),
    10,
    'calculate_early_advance_required: 100% of 10 = 10, count = 3, MAX = 10'
);

SELECT is(
    calculate_early_advance_required(50, 3, 10),
    5,
    'calculate_early_advance_required: 50% of 10 = 5, count = 3, MAX = 5'
);

SELECT is(
    calculate_early_advance_required(50, 8, 10),
    8,
    'calculate_early_advance_required: 50% of 10 = 5, count = 8, MAX = 8'
);

SELECT is(
    calculate_early_advance_required(NULL, NULL, 10),
    NULL,
    'calculate_early_advance_required: both null = disabled (NULL)'
);

-- =============================================================================
-- TEST: Proposing phase - no advance until threshold met
-- =============================================================================

-- User 1 submits
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Proposition from User 1'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'User 1'
WHERE ch.name = 'ImmediateAdvanceTest';

SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ImmediateAdvanceTest'),
    'proposing',
    'After 1 of 3 submit: still proposing (33%)'
);

-- User 2 submits
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Proposition from User 2'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'User 2'
WHERE ch.name = 'ImmediateAdvanceTest';

SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ImmediateAdvanceTest'),
    'proposing',
    'After 2 of 3 submit: still proposing (66%)'
);

-- User 3 submits - should trigger immediate advance
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Proposition from User 3'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'User 3'
WHERE ch.name = 'ImmediateAdvanceTest';

SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ImmediateAdvanceTest'),
    'rating',
    'After 3 of 3 submit: IMMEDIATELY advanced to rating (100%)'
);

-- =============================================================================
-- TEST: Rating phase - no advance until threshold met
-- =============================================================================

-- User 1 rates (ranks props from users 2 and 3)
INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
SELECT p.id, part.id, r.id, 80.0
FROM propositions p
JOIN rounds r ON r.id = p.round_id
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants part ON part.chat_id = ch.id AND part.display_name = 'User 1'
JOIN participants prop_owner ON prop_owner.id = p.participant_id
WHERE ch.name = 'ImmediateAdvanceTest' AND prop_owner.display_name = 'User 2';

INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
SELECT p.id, part.id, r.id, 20.0
FROM propositions p
JOIN rounds r ON r.id = p.round_id
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants part ON part.chat_id = ch.id AND part.display_name = 'User 1'
JOIN participants prop_owner ON prop_owner.id = p.participant_id
WHERE ch.name = 'ImmediateAdvanceTest' AND prop_owner.display_name = 'User 3';

SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ImmediateAdvanceTest'),
    'rating',
    'After 1 of 3 rate: still rating (33%)'
);

-- User 2 rates (ranks props from users 1 and 3)
INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
SELECT p.id, part.id, r.id, 70.0
FROM propositions p
JOIN rounds r ON r.id = p.round_id
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants part ON part.chat_id = ch.id AND part.display_name = 'User 2'
JOIN participants prop_owner ON prop_owner.id = p.participant_id
WHERE ch.name = 'ImmediateAdvanceTest' AND prop_owner.display_name = 'User 1';

INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
SELECT p.id, part.id, r.id, 30.0
FROM propositions p
JOIN rounds r ON r.id = p.round_id
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants part ON part.chat_id = ch.id AND part.display_name = 'User 2'
JOIN participants prop_owner ON prop_owner.id = p.participant_id
WHERE ch.name = 'ImmediateAdvanceTest' AND prop_owner.display_name = 'User 3';

SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ImmediateAdvanceTest'),
    'rating',
    'After 2 of 3 rate: still rating (66%)'
);

-- User 3 rates (ranks props from users 1 and 2) - should trigger immediate completion
INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
SELECT p.id, part.id, r.id, 60.0
FROM propositions p
JOIN rounds r ON r.id = p.round_id
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants part ON part.chat_id = ch.id AND part.display_name = 'User 3'
JOIN participants prop_owner ON prop_owner.id = p.participant_id
WHERE ch.name = 'ImmediateAdvanceTest' AND prop_owner.display_name = 'User 1';

INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
SELECT p.id, part.id, r.id, 40.0
FROM propositions p
JOIN rounds r ON r.id = p.round_id
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants part ON part.chat_id = ch.id AND part.display_name = 'User 3'
JOIN participants prop_owner ON prop_owner.id = p.participant_id
WHERE ch.name = 'ImmediateAdvanceTest' AND prop_owner.display_name = 'User 2';

SELECT is(
    (SELECT r.completed_at IS NOT NULL FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ImmediateAdvanceTest' AND r.custom_id = 1),
    true,
    'After 3 of 3 rate: round IMMEDIATELY completed'
);

SELECT is(
    (SELECT r.winning_proposition_id IS NOT NULL FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ImmediateAdvanceTest' AND r.custom_id = 1),
    true,
    'Round has a winning proposition'
);

-- =============================================================================
-- TEST: Manual rating_start_mode - advances to waiting, not rating
-- =============================================================================

-- Create chat with rating_start_mode='manual' (start_mode no longer affects early advance)
-- With rating_start_mode='manual', early advance goes to 'waiting' instead of 'rating'
INSERT INTO chats (name, initial_message, start_mode, rating_start_mode,
    proposing_threshold_percent, proposing_threshold_count,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_minimum, rating_minimum)
VALUES ('ManualModeNoAdvance', 'Test', 'manual', 'manual',
    100, 3,  -- threshold triggers early advance to 'waiting' (not rating)
    300, 300,
    3, 2);

INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'UserA', 'active', gen_random_uuid() FROM chats WHERE name = 'ManualModeNoAdvance';
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'UserB', 'active', gen_random_uuid() FROM chats WHERE name = 'ManualModeNoAdvance';
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'UserC', 'active', gen_random_uuid() FROM chats WHERE name = 'ManualModeNoAdvance';

INSERT INTO cycles (chat_id)
SELECT id FROM chats WHERE name = 'ManualModeNoAdvance';

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
SELECT c.id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes'
FROM cycles c
JOIN chats ch ON ch.id = c.chat_id
WHERE ch.name = 'ManualModeNoAdvance';

-- All 3 users submit (100% participation)
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Prop A'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'UserA'
WHERE ch.name = 'ManualModeNoAdvance';

INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Prop B'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'UserB'
WHERE ch.name = 'ManualModeNoAdvance';

INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Prop C'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'UserC'
WHERE ch.name = 'ManualModeNoAdvance';

SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'ManualModeNoAdvance'),
    'waiting',
    'Manual rating_start_mode: advances to waiting (not rating) at 100% participation'
);

-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
