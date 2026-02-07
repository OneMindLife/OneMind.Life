-- Expiration and rate limiting tests
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(14);

-- =============================================================================
-- EXPIRATION FOR ANONYMOUS CHATS
-- =============================================================================

-- Test 1: Anonymous chat gets 7-day expiration
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Anon Chat', 'Anonymous topic', 'anon-session-xyz');

SELECT extensions.ok(
  (SELECT expires_at FROM chats WHERE name = 'Anon Chat') IS NOT NULL,
  'Anonymous chat has expiration date set'
);

-- Test 2: Expiration is approximately 7 days from now
SELECT extensions.ok(
  (SELECT expires_at FROM chats WHERE name = 'Anon Chat')
    BETWEEN NOW() + INTERVAL '6 days 23 hours' AND NOW() + INTERVAL '7 days 1 hour',
  'Anonymous chat expires in approximately 7 days'
);

-- Test 3: last_activity_at is set on creation
SELECT extensions.ok(
  (SELECT last_activity_at FROM chats WHERE name = 'Anon Chat') IS NOT NULL,
  'last_activity_at is set on chat creation'
);

-- =============================================================================
-- NO EXPIRATION FOR AUTHENTICATED CHATS
-- =============================================================================

-- Create a user first
INSERT INTO users (id, email, display_name)
VALUES ('11111111-1111-1111-1111-111111111111', 'test@example.com', 'Test User');

-- Test 4: Authenticated chat has no expiration
INSERT INTO chats (name, initial_message, creator_id)
VALUES ('Auth Chat', 'Authenticated topic', '11111111-1111-1111-1111-111111111111');

SELECT extensions.is(
  (SELECT expires_at FROM chats WHERE name = 'Auth Chat'),
  NULL,
  'Authenticated chat has no expiration'
);

-- =============================================================================
-- RATE LIMITING FOR ANONYMOUS SESSIONS
-- =============================================================================

-- Test 5-14: Anonymous session limited to 10 active chats
DO $$
DECLARE
  i INT;
BEGIN
  FOR i IN 1..10 LOOP
    INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Rate Limit Chat ' || i, 'Topic ' || i, 'rate-limit-session');
  END LOOP;
END $$;

SELECT extensions.is(
  (SELECT COUNT(*) FROM chats WHERE creator_session_token = 'rate-limit-session'),
  10::bigint,
  '10 chats created successfully for anonymous session'
);

-- Test 6: 11th chat should fail (rate limit exceeded)
SELECT extensions.throws_ok(
  $$INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('Rate Limit Chat 11', 'Topic 11', 'rate-limit-session')$$,
  NULL,
  NULL,
  '11th chat insertion fails due to rate limit'
);

-- Test 7: Different session can create chats
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Different Session Chat', 'Topic', 'different-session');

SELECT extensions.is(
  (SELECT COUNT(*) FROM chats WHERE creator_session_token = 'different-session'),
  1::bigint,
  'Different session can create chats independently'
);

-- Test 8: Authenticated users have no rate limit (create 11+ chats)
DO $$
DECLARE
  i INT;
BEGIN
  FOR i IN 1..11 LOOP
    INSERT INTO chats (name, initial_message, creator_id)
    VALUES ('Auth Rate Chat ' || i, 'Topic ' || i, '11111111-1111-1111-1111-111111111111');
  END LOOP;
END $$;

SELECT extensions.is(
  (SELECT COUNT(*) FROM chats WHERE creator_id = '11111111-1111-1111-1111-111111111111'),
  12::bigint,  -- 11 new + 1 Auth Chat from earlier
  'Authenticated users have no rate limit'
);

-- =============================================================================
-- ACTIVITY UPDATES RESET EXPIRATION
-- =============================================================================

-- Test 9: Set up chat with known expiration
UPDATE chats
SET expires_at = NOW() + INTERVAL '1 day',
    last_activity_at = NOW() - INTERVAL '6 days'
WHERE name = 'Anon Chat';

-- Create cycle and iteration for propositions
INSERT INTO cycles (chat_id, custom_id)
SELECT id, 1 FROM chats WHERE name = 'Anon Chat';

INSERT INTO iterations (cycle_id, custom_id, phase)
SELECT id, 1, 'proposing' FROM cycles
WHERE chat_id = (SELECT id FROM chats WHERE name = 'Anon Chat');

-- Create participant
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
SELECT id, 'anon-session-xyz', 'Anon User', TRUE, 'active'
FROM chats WHERE name = 'Anon Chat';

-- Test 10: Creating proposition updates activity
INSERT INTO propositions (iteration_id, participant_id, content)
SELECT
  i.id,
  p.id,
  'My proposition'
FROM iterations i
JOIN cycles c ON i.cycle_id = c.id
JOIN chats ch ON c.chat_id = ch.id
JOIN participants p ON p.chat_id = ch.id
WHERE ch.name = 'Anon Chat';

SELECT extensions.ok(
  (SELECT last_activity_at FROM chats WHERE name = 'Anon Chat') > NOW() - INTERVAL '1 minute',
  'Proposition creation updates last_activity_at'
);

-- Test 11: Expiration extended after activity
SELECT extensions.ok(
  (SELECT expires_at FROM chats WHERE name = 'Anon Chat') > NOW() + INTERVAL '6 days',
  'Expiration extended after proposition activity'
);

-- Test 12: Set up for rating activity test
UPDATE chats
SET expires_at = NOW() + INTERVAL '1 day',
    last_activity_at = NOW() - INTERVAL '6 days'
WHERE name = 'Anon Chat';

-- Update iteration to rating phase
UPDATE iterations SET phase = 'rating'
WHERE cycle_id = (SELECT id FROM cycles WHERE chat_id = (SELECT id FROM chats WHERE name = 'Anon Chat'));

-- Test 13: Creating rating updates activity
INSERT INTO ratings (proposition_id, participant_id, rating)
SELECT
  prop.id,
  p.id,
  75
FROM propositions prop
JOIN iterations i ON prop.iteration_id = i.id
JOIN cycles c ON i.cycle_id = c.id
JOIN chats ch ON c.chat_id = ch.id
JOIN participants p ON p.chat_id = ch.id
WHERE ch.name = 'Anon Chat'
LIMIT 1;

SELECT extensions.ok(
  (SELECT last_activity_at FROM chats WHERE name = 'Anon Chat') > NOW() - INTERVAL '1 minute',
  'Rating creation updates last_activity_at'
);

-- Test 14: Expiration extended after rating activity
SELECT extensions.ok(
  (SELECT expires_at FROM chats WHERE name = 'Anon Chat') > NOW() + INTERVAL '6 days',
  'Expiration extended after rating activity'
);

SELECT * FROM finish();
ROLLBACK;
