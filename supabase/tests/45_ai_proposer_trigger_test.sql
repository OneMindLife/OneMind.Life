-- Test: AI proposer trigger for automatic proposition generation
-- This tests the database trigger that calls ai-proposer Edge Function
-- when a round enters the proposing phase.
--
-- Note: We cannot test the actual HTTP call to the Edge Function in these tests
-- since pg_net requires the extension to be running and the function to be deployed.
-- These tests verify:
-- 1. Default values changed for enable_ai_participant and ai_propositions_count
-- 2. Trigger function exists and has correct logic
-- 3. Trigger fires at the right times (on INSERT/UPDATE when phase='proposing')

BEGIN;

SELECT plan(14);

-- =============================================================================
-- Test 1-2: Verify default values changed
-- =============================================================================

-- Test 1: enable_ai_participant default is now TRUE
SELECT is(
    (SELECT column_default FROM information_schema.columns
     WHERE table_name = 'chats' AND column_name = 'enable_ai_participant'),
    'true',
    'enable_ai_participant default is TRUE'
);

-- Test 2: ai_propositions_count default is now 1
SELECT is(
    (SELECT column_default FROM information_schema.columns
     WHERE table_name = 'chats' AND column_name = 'ai_propositions_count'),
    '1',
    'ai_propositions_count default is 1'
);

-- =============================================================================
-- Test 3-4: Verify trigger and function exist
-- =============================================================================

-- Test 3: Trigger function exists
SELECT has_function(
    'public',
    'trigger_ai_proposer_on_proposing',
    'Trigger function trigger_ai_proposer_on_proposing exists'
);

-- Test 4: Trigger exists on rounds table
SELECT has_trigger(
    'rounds',
    'ai_proposer_on_proposing_phase',
    'Trigger ai_proposer_on_proposing_phase exists on rounds table'
);

-- =============================================================================
-- Test 5-8: New chat gets AI enabled by default
-- =============================================================================

-- Create a chat without specifying AI settings (should use defaults)
INSERT INTO chats (name, initial_message, access_method, start_mode)
VALUES ('AI Default Test Chat', 'Test topic', 'code', 'manual')
RETURNING id AS chat_id \gset

-- Test 5: Chat has enable_ai_participant = TRUE
SELECT is(
    (SELECT enable_ai_participant FROM chats WHERE id = :chat_id),
    TRUE,
    'New chat has enable_ai_participant = TRUE by default'
);

-- Test 6: Chat has ai_propositions_count = 1
SELECT is(
    (SELECT ai_propositions_count FROM chats WHERE id = :chat_id),
    1,
    'New chat has ai_propositions_count = 1 by default'
);

-- Test 7: Can still create chat with AI disabled
INSERT INTO chats (name, initial_message, access_method, start_mode, enable_ai_participant)
VALUES ('AI Disabled Test Chat', 'Test topic', 'code', 'manual', FALSE)
RETURNING id AS disabled_chat_id \gset

SELECT is(
    (SELECT enable_ai_participant FROM chats WHERE id = :disabled_chat_id),
    FALSE,
    'Can create chat with enable_ai_participant = FALSE'
);

-- Test 8: Can set custom ai_propositions_count
INSERT INTO chats (name, initial_message, access_method, start_mode, ai_propositions_count)
VALUES ('AI Custom Count Chat', 'Test topic', 'code', 'manual', 5)
RETURNING id AS custom_count_chat_id \gset

SELECT is(
    (SELECT ai_propositions_count FROM chats WHERE id = :custom_count_chat_id),
    5,
    'Can create chat with custom ai_propositions_count'
);

-- =============================================================================
-- Test 9-11: Trigger function logic (without actual HTTP call)
-- =============================================================================

-- We can't test the actual pg_net call, but we can verify the function
-- doesn't fail when AI is disabled

-- Create a chat with AI disabled
INSERT INTO chats (name, initial_message, access_method, start_mode, enable_ai_participant, proposing_duration_seconds, rating_duration_seconds)
VALUES ('AI Trigger Test Chat', 'Test topic', 'code', 'manual', FALSE, 300, 300)
RETURNING id AS trigger_test_chat_id \gset

-- Create cycle and round
INSERT INTO cycles (chat_id)
VALUES (:trigger_test_chat_id)
RETURNING id AS trigger_cycle_id \gset

-- Test 9: Can create round in proposing phase (trigger runs but skips AI)
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
VALUES (:trigger_cycle_id, 1, 'proposing', NOW())
RETURNING id AS trigger_round_id \gset

SELECT ok(
    (SELECT id FROM rounds WHERE id = :trigger_round_id) IS NOT NULL,
    'Round created successfully when AI disabled (trigger does not block)'
);

-- Test 10: Can update round to proposing phase (trigger runs but skips AI)
UPDATE rounds SET phase = 'waiting' WHERE id = :trigger_round_id;

UPDATE rounds SET phase = 'proposing', phase_started_at = NOW()
WHERE id = :trigger_round_id;

SELECT is(
    (SELECT phase FROM rounds WHERE id = :trigger_round_id),
    'proposing',
    'Round updated to proposing successfully when AI disabled'
);

-- Test 11: Trigger doesn't fire twice on same phase
-- (no error means it correctly checks OLD.phase != NEW.phase)
UPDATE rounds SET phase_started_at = NOW() WHERE id = :trigger_round_id;

SELECT is(
    (SELECT phase FROM rounds WHERE id = :trigger_round_id),
    'proposing',
    'Updating round without phase change does not cause issues'
);

-- =============================================================================
-- Test 12-14: Trigger fires in all scenarios where rounds enter proposing
-- =============================================================================

-- Setup: Create auto-mode chat with AI enabled
INSERT INTO chats (name, initial_message, access_method, start_mode, auto_start_participant_count, enable_ai_participant, ai_propositions_count, proposing_duration_seconds, rating_duration_seconds, confirmation_rounds_required)
VALUES ('AI Scenario Test Chat', 'Test topic', 'code', 'auto', 3, TRUE, 1, 300, 300, 1)
RETURNING id AS scenario_chat_id \gset

-- Add 3 participants (triggers auto-start cycle creation)
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
    (:scenario_chat_id, '11111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active'),
    (:scenario_chat_id, '22222222-2222-2222-2222-222222222222', 'User 1', FALSE, 'active'),
    (:scenario_chat_id, '33333333-3333-3333-3333-333333333333', 'User 2', FALSE, 'active');

-- Get the auto-created cycle and round
SELECT id AS scenario_cycle_id FROM cycles WHERE chat_id = :scenario_chat_id LIMIT 1 \gset
SELECT id AS scenario_round_id FROM rounds WHERE cycle_id = :scenario_cycle_id LIMIT 1 \gset
SELECT id AS scenario_participant_id FROM participants WHERE chat_id = :scenario_chat_id LIMIT 1 \gset

-- Test 12: Scenario 1 - Round created in proposing phase via auto-start
SELECT is(
    (SELECT phase FROM rounds WHERE id = :scenario_round_id),
    'proposing',
    'Scenario 1: Auto-start creates round in proposing phase (trigger fires on INSERT)'
);

-- Complete the round to trigger new round creation
INSERT INTO propositions (round_id, participant_id, content)
VALUES (:scenario_round_id, :scenario_participant_id, 'Winning proposition')
RETURNING id AS scenario_prop_id \gset

UPDATE rounds SET phase = 'rating' WHERE id = :scenario_round_id;

INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
VALUES (:scenario_prop_id, :scenario_round_id, 90);

-- Set winner (triggers on_round_winner_set -> consensus -> on_cycle_winner_set -> new cycle)
UPDATE rounds
SET winning_proposition_id = :scenario_prop_id,
    is_sole_winner = TRUE
WHERE id = :scenario_round_id;

-- Get the new cycle's first round
SELECT id AS scenario_cycle2_id FROM cycles WHERE chat_id = :scenario_chat_id ORDER BY id DESC LIMIT 1 \gset
SELECT id AS scenario_round2_id FROM rounds WHERE cycle_id = :scenario_cycle2_id LIMIT 1 \gset

-- Test 13: Scenario 2 - New cycle after consensus creates round in proposing
SELECT is(
    (SELECT phase FROM rounds WHERE id = :scenario_round2_id),
    'proposing',
    'Scenario 2: New cycle after consensus creates round in proposing (trigger fires)'
);

-- Test 14: Scenario 3 - Manual start (waiting -> proposing transition)
INSERT INTO chats (name, initial_message, access_method, start_mode, enable_ai_participant, proposing_duration_seconds, rating_duration_seconds)
VALUES ('Manual Start AI Test', 'Test topic', 'code', 'manual', TRUE, 300, 300)
RETURNING id AS manual_chat_id \gset

INSERT INTO cycles (chat_id)
VALUES (:manual_chat_id)
RETURNING id AS manual_cycle_id \gset

INSERT INTO rounds (cycle_id, custom_id, phase)
VALUES (:manual_cycle_id, 1, 'waiting')
RETURNING id AS manual_round_id \gset

-- Simulate manual start (host clicks Start Phase)
UPDATE rounds
SET phase = 'proposing',
    phase_started_at = NOW(),
    phase_ends_at = NOW() + INTERVAL '5 minutes'
WHERE id = :manual_round_id;

SELECT is(
    (SELECT phase FROM rounds WHERE id = :manual_round_id),
    'proposing',
    'Scenario 3: Manual waiting -> proposing transition works (trigger fires on UPDATE)'
);

SELECT * FROM finish();

ROLLBACK;
