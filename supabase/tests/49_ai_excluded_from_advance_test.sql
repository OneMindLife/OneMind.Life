-- Tests that AI propositions are excluded from early advance count
-- AI propositions (participant_id IS NULL) should not count toward the
-- proposing threshold - only human submissions count.
BEGIN;
SELECT plan(6);

-- =============================================================================
-- SETUP: Create test chat with 3 participants and threshold of 3
-- =============================================================================

-- Create auto-mode chat with early advance enabled
-- Set auto_start_participant_count high to prevent auto-start trigger
INSERT INTO chats (name, initial_message, start_mode, auto_start_participant_count,
    proposing_threshold_percent, proposing_threshold_count,
    rating_threshold_percent, rating_threshold_count,
    proposing_duration_seconds, rating_duration_seconds,
    proposing_minimum, rating_minimum,
    enable_ai_participant, ai_propositions_count)
VALUES ('AIExcludedTest', 'Test', 'auto', 99,
    100, 3,  -- 100% or at least 3 propositions for proposing
    NULL, 2,
    300, 300,
    3, 2,
    TRUE, 1);  -- AI enabled with 1 proposition

-- Add 3 participants
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'User 1', 'active', gen_random_uuid() FROM chats WHERE name = 'AIExcludedTest';
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'User 2', 'active', gen_random_uuid() FROM chats WHERE name = 'AIExcludedTest';
INSERT INTO participants (chat_id, display_name, status, session_token)
SELECT id, 'User 3', 'active', gen_random_uuid() FROM chats WHERE name = 'AIExcludedTest';

-- Manually create cycle and round in proposing phase
INSERT INTO cycles (chat_id)
SELECT id FROM chats WHERE name = 'AIExcludedTest';

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
SELECT c.id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes'
FROM cycles c
JOIN chats ch ON ch.id = c.chat_id
WHERE ch.name = 'AIExcludedTest';

-- =============================================================================
-- TEST: AI proposition does NOT count toward threshold
-- =============================================================================

-- Simulate AI proposition (participant_id IS NULL)
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, NULL, 'AI generated proposition about the topic'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
WHERE ch.name = 'AIExcludedTest';

-- Test 1: After AI proposes, still in proposing phase
SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'AIExcludedTest'),
    'proposing',
    'After AI proposition: still proposing (AI does not count)'
);

-- User 1 submits
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Proposition from User 1'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'User 1'
WHERE ch.name = 'AIExcludedTest';

-- Test 2: AI + 1 human = still proposing
SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'AIExcludedTest'),
    'proposing',
    'After AI + 1 human: still proposing (1 human < 3 threshold)'
);

-- User 2 submits
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Proposition from User 2'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'User 2'
WHERE ch.name = 'AIExcludedTest';

-- Test 3: AI + 2 humans = still proposing (would have advanced if AI counted)
SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'AIExcludedTest'),
    'proposing',
    'After AI + 2 humans: still proposing (2 humans < 3 threshold, AI excluded)'
);

-- Test 4: Total proposition count is 3 (1 AI + 2 humans)
SELECT is(
    (SELECT COUNT(*) FROM propositions p
     JOIN rounds r ON r.id = p.round_id
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'AIExcludedTest'),
    3::bigint,
    'Total propositions is 3 (1 AI + 2 humans)'
);

-- Test 5: Human-only count is 2
SELECT is(
    (SELECT COUNT(*) FROM propositions p
     JOIN rounds r ON r.id = p.round_id
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'AIExcludedTest'
     AND p.participant_id IS NOT NULL),
    2::bigint,
    'Human propositions count is 2'
);

-- User 3 submits - should NOW advance (3 humans meet threshold)
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, p.id, 'Proposition from User 3'
FROM rounds r
JOIN cycles c ON c.id = r.cycle_id
JOIN chats ch ON ch.id = c.chat_id
JOIN participants p ON p.chat_id = ch.id AND p.display_name = 'User 3'
WHERE ch.name = 'AIExcludedTest';

-- Test 6: After 3 humans submit, advances to rating
SELECT is(
    (SELECT r.phase FROM rounds r
     JOIN cycles c ON c.id = r.cycle_id
     JOIN chats ch ON ch.id = c.chat_id
     WHERE ch.name = 'AIExcludedTest'),
    'rating',
    'After 3 humans: ADVANCED to rating (AI excluded, 3 humans = 3 threshold)'
);

-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
