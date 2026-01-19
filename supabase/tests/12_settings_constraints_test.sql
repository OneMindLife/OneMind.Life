-- Settings constraint validation tests
-- Tests that invalid setting values are properly rejected
BEGIN;
SET search_path TO public, extensions;
SELECT plan(32);

-- =============================================================================
-- CONFIRMATION_ROUNDS_REQUIRED CONSTRAINTS
-- =============================================================================

-- Test 1: confirmation_rounds_required cannot be 0
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 0)$$,
  '23514',
  NULL,
  'confirmation_rounds_required cannot be 0'
);

-- Test 2: confirmation_rounds_required cannot be negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), -1)$$,
  '23514',
  NULL,
  'confirmation_rounds_required cannot be negative'
);

-- Test 3: confirmation_rounds_required can be 1
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('One Round Chat', 'Test', gen_random_uuid(), 1);

SELECT is(
  (SELECT confirmation_rounds_required FROM chats WHERE name = 'One Round Chat'),
  1,
  'confirmation_rounds_required can be 1'
);

-- Test 4: confirmation_rounds_required can be 2 (max)
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
VALUES ('Two Round Chat', 'Test', gen_random_uuid(), 2);

SELECT is(
  (SELECT confirmation_rounds_required FROM chats WHERE name = 'Two Round Chat'),
  2,
  'confirmation_rounds_required can be 2 (max)'
);

-- Test 5: confirmation_rounds_required cannot be 3 (max is 2)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 3)$$,
  '23514',
  NULL,
  'confirmation_rounds_required cannot be 3 (max is 2)'
);

-- =============================================================================
-- PROPOSITIONS_PER_USER CONSTRAINTS
-- =============================================================================

-- Test 6: propositions_per_user cannot be 0
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 0)$$,
  '23514',
  NULL,
  'propositions_per_user cannot be 0'
);

-- Test 7: propositions_per_user cannot be negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), -5)$$,
  '23514',
  NULL,
  'propositions_per_user cannot be negative'
);

-- Test 8: propositions_per_user can be 1
INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
VALUES ('One Prop Chat', 'Test', gen_random_uuid(), 1);

SELECT is(
  (SELECT propositions_per_user FROM chats WHERE name = 'One Prop Chat'),
  1,
  'propositions_per_user can be 1'
);

-- Test 9: propositions_per_user can be 20
INSERT INTO chats (name, initial_message, creator_session_token, propositions_per_user)
VALUES ('Twenty Prop Chat', 'Test', gen_random_uuid(), 20);

SELECT is(
  (SELECT propositions_per_user FROM chats WHERE name = 'Twenty Prop Chat'),
  20,
  'propositions_per_user can be 20'
);

-- =============================================================================
-- TIMER DURATION CONSTRAINTS
-- =============================================================================

-- Test 10: proposing_duration_seconds must be at least 60 seconds
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 59)$$,
  '23514',
  NULL,
  'proposing_duration_seconds must be >= 60'
);

-- Test 11: proposing_duration_seconds cannot be negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), -100)$$,
  '23514',
  NULL,
  'proposing_duration_seconds cannot be negative'
);

-- Test 12: rating_duration_seconds must be at least 60 seconds
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, rating_duration_seconds)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 59)$$,
  '23514',
  NULL,
  'rating_duration_seconds must be >= 60'
);

-- Test 13: rating_duration_seconds cannot be negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, rating_duration_seconds)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), -100)$$,
  '23514',
  NULL,
  'rating_duration_seconds cannot be negative'
);

-- Test 14: Valid 5 minute timer
INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
VALUES ('5min Timer Chat', 'Test', gen_random_uuid(), 300);

SELECT is(
  (SELECT proposing_duration_seconds FROM chats WHERE name = '5min Timer Chat'),
  300,
  'proposing_duration_seconds can be 300 (5 minutes)'
);

-- Test 15: 7 day timer is rejected (max is 1 day = 86400 seconds)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_duration_seconds)
    VALUES ('7day Timer Chat', 'Test', gen_random_uuid(), 604800)$$,
  '23514',
  NULL,
  'proposing_duration_seconds cannot exceed 86400 (1 day max)'
);

-- =============================================================================
-- MINIMUM CONSTRAINTS
-- proposing_minimum >= 3 (users can't rate their own, so need 2+ visible to each)
-- rating_minimum >= 2 (need 2 raters for meaningful alignment)
-- =============================================================================

-- Test 16: proposing_minimum must be >= 3 (users can't rate own, need 2+ visible)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_minimum)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 2)$$,
  '23514',
  NULL,
  'proposing_minimum cannot be 2 (must be >= 3)'
);

-- Test 17: proposing_minimum cannot be 1
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_minimum)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 1)$$,
  '23514',
  NULL,
  'proposing_minimum cannot be 1'
);

-- Test 18: rating_minimum must be >= 2 (need 2 raters for alignment)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, rating_minimum)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 1)$$,
  '23514',
  NULL,
  'rating_minimum cannot be 1 (must be >= 2)'
);

-- Test 19: rating_minimum cannot be 0
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, rating_minimum)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 0)$$,
  '23514',
  NULL,
  'rating_minimum cannot be 0'
);

-- Test 20: Valid minimum of 3 for proposing, 2 for rating
INSERT INTO chats (name, initial_message, creator_session_token, proposing_minimum, rating_minimum)
VALUES ('Min 3 Chat', 'Test', gen_random_uuid(), 3, 2);

SELECT is(
  (SELECT proposing_minimum FROM chats WHERE name = 'Min 3 Chat'),
  3,
  'proposing_minimum can be 3'
);

-- Test 21: Valid minimum of 100
INSERT INTO chats (name, initial_message, creator_session_token, proposing_minimum)
VALUES ('Min 100 Chat', 'Test', gen_random_uuid(), 100);

SELECT is(
  (SELECT proposing_minimum FROM chats WHERE name = 'Min 100 Chat'),
  100,
  'proposing_minimum can be 100'
);

-- =============================================================================
-- THRESHOLD CONSTRAINTS
-- =============================================================================

-- Test 22: proposing_threshold_percent must be between 0 and 100
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_threshold_percent)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 101)$$,
  '23514',
  NULL,
  'proposing_threshold_percent cannot exceed 100'
);

-- Test 23: proposing_threshold_percent cannot be negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, proposing_threshold_percent)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), -1)$$,
  '23514',
  NULL,
  'proposing_threshold_percent cannot be negative'
);

-- Test 24: rating_threshold_percent must be between 0 and 100
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, rating_threshold_percent)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), 150)$$,
  '23514',
  NULL,
  'rating_threshold_percent cannot exceed 100'
);

-- Test 25: rating_threshold_percent cannot be negative
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, rating_threshold_percent)
    VALUES ('Bad Chat', 'Test', gen_random_uuid(), -10)$$,
  '23514',
  NULL,
  'rating_threshold_percent cannot be negative'
);

-- Test 26: Valid threshold of 50%
INSERT INTO chats (name, initial_message, creator_session_token, proposing_threshold_percent)
VALUES ('50% Threshold Chat', 'Test', gen_random_uuid(), 50);

SELECT is(
  (SELECT proposing_threshold_percent FROM chats WHERE name = '50% Threshold Chat'),
  50,
  'proposing_threshold_percent can be 50'
);

-- Test 27: Valid threshold of 100%
INSERT INTO chats (name, initial_message, creator_session_token, rating_threshold_percent)
VALUES ('100% Threshold Chat', 'Test', gen_random_uuid(), 100);

SELECT is(
  (SELECT rating_threshold_percent FROM chats WHERE name = '100% Threshold Chat'),
  100,
  'rating_threshold_percent can be 100'
);

-- =============================================================================
-- AUTO-START COUNT CONSTRAINTS
-- =============================================================================

-- Test 28: auto_start_participant_count must be >= 3 (need 3+ for proposing minimum and rating)
INSERT INTO chats (name, initial_message, creator_session_token, start_mode, auto_start_participant_count)
VALUES ('Auto Start 3 Chat', 'Test', gen_random_uuid(), 'auto', 3);

SELECT is(
  (SELECT auto_start_participant_count FROM chats WHERE name = 'Auto Start 3 Chat'),
  3,
  'auto_start_participant_count can be 3 (minimum)'
);

-- Test 29: auto_start_participant_count cannot be 2 (below minimum)
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token, start_mode, auto_start_participant_count)
    VALUES ('Auto Start 2 Chat', 'Test', gen_random_uuid(), 'auto', 2)$$,
  '23514',  -- check constraint violation
  NULL,
  'auto_start_participant_count cannot be 2 (requires >= 3)'
);

-- Test 30: auto_start_participant_count can be NULL
INSERT INTO chats (name, initial_message, creator_session_token, start_mode, auto_start_participant_count)
VALUES ('Manual Start Chat', 'Test', gen_random_uuid(), 'manual', NULL);

SELECT is(
  (SELECT auto_start_participant_count FROM chats WHERE name = 'Manual Start Chat'),
  NULL,
  'auto_start_participant_count can be NULL'
);

-- =============================================================================
-- AI SETTINGS CONSTRAINTS
-- =============================================================================

-- Test 31: ai_propositions_count can be set when AI enabled
INSERT INTO chats (name, initial_message, creator_session_token, enable_ai_participant, ai_propositions_count)
VALUES ('AI Enabled Chat', 'Test', gen_random_uuid(), true, 5);

SELECT is(
  (SELECT ai_propositions_count FROM chats WHERE name = 'AI Enabled Chat'),
  5,
  'ai_propositions_count can be 5 when AI enabled'
);

-- Test 32: ai_propositions_count can be NULL when AI disabled
INSERT INTO chats (name, initial_message, creator_session_token, enable_ai_participant, ai_propositions_count)
VALUES ('AI Disabled Chat', 'Test', gen_random_uuid(), false, NULL);

SELECT is(
  (SELECT ai_propositions_count FROM chats WHERE name = 'AI Disabled Chat'),
  NULL,
  'ai_propositions_count can be NULL when AI disabled'
);

SELECT * FROM finish();
ROLLBACK;
