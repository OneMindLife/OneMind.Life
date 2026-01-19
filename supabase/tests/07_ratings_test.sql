-- Ratings and proposition_movda_ratings tests
BEGIN;
SET search_path TO public, extensions;
SELECT plan(26);

-- =============================================================================
-- SETUP (Anonymous chats only - no users table dependency)
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Rating Test Chat', 'Test ratings', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Rating Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Create cycle and round
INSERT INTO cycles (chat_id)
VALUES (current_setting('test.chat_id')::INT);

DO $$
DECLARE
  v_cycle_id INT;
BEGIN
  SELECT id INTO v_cycle_id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
END $$;

INSERT INTO rounds (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 1, 'proposing');

DO $$
DECLARE
  v_round_id INT;
BEGIN
  SELECT id INTO v_round_id FROM rounds WHERE cycle_id = current_setting('test.cycle_id')::INT;
  PERFORM set_config('test.round_id', v_round_id::TEXT, TRUE);
END $$;

-- Create participants with UUID session tokens
DO $$
DECLARE
  v_p1 INT;
  v_p2 INT;
  v_p3 INT;
  v_p4 INT;
  v_p5 INT;
  v_session1 UUID := gen_random_uuid();
  v_session2 UUID := gen_random_uuid();
  v_session3 UUID := gen_random_uuid();
  v_session4 UUID := gen_random_uuid();
  v_session5 UUID := gen_random_uuid();
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, v_session1, 'Rater 1', FALSE, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, v_session2, 'Rater 2', FALSE, 'active')
  RETURNING id INTO v_p2;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, v_session3, 'Rater 3', FALSE, 'active')
  RETURNING id INTO v_p3;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, v_session4, 'Rater 4', FALSE, 'active')
  RETURNING id INTO v_p4;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, v_session5, 'Rater 5', FALSE, 'active')
  RETURNING id INTO v_p5;

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);
  PERFORM set_config('test.p4', v_p4::TEXT, TRUE);
  PERFORM set_config('test.p5', v_p5::TEXT, TRUE);
END $$;

-- Create propositions
INSERT INTO propositions (round_id, participant_id, content)
VALUES
  (current_setting('test.round_id')::INT, current_setting('test.p1')::INT, 'Prop Alpha'),
  (current_setting('test.round_id')::INT, current_setting('test.p2')::INT, 'Prop Beta'),
  (current_setting('test.round_id')::INT, current_setting('test.p3')::INT, 'Prop Gamma');

DO $$
DECLARE
  v_prop_a INT;
  v_prop_b INT;
  v_prop_g INT;
BEGIN
  SELECT id INTO v_prop_a FROM propositions WHERE content = 'Prop Alpha';
  SELECT id INTO v_prop_b FROM propositions WHERE content = 'Prop Beta';
  SELECT id INTO v_prop_g FROM propositions WHERE content = 'Prop Gamma';

  PERFORM set_config('test.prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.prop_b', v_prop_b::TEXT, TRUE);
  PERFORM set_config('test.prop_g', v_prop_g::TEXT, TRUE);
END $$;

-- Move to rating phase
UPDATE rounds SET phase = 'rating' WHERE id = current_setting('test.round_id')::INT;

-- =============================================================================
-- RATING BASICS
-- =============================================================================

-- Test 1: Create rating
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p1')::INT, 85);

SELECT is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  1::bigint,
  'Rating created successfully'
);

-- Test 2: Rating value stored correctly
SELECT is(
  (SELECT rating FROM ratings
   WHERE proposition_id = current_setting('test.prop_a')::INT
   AND participant_id = current_setting('test.p1')::INT),
  85,
  'Rating value stored correctly'
);

-- Test 3: Rating range 0-100 (valid values)
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p2')::INT, 0);

SELECT is(
  (SELECT rating FROM ratings
   WHERE proposition_id = current_setting('test.prop_a')::INT
   AND participant_id = current_setting('test.p2')::INT),
  0,
  'Rating of 0 allowed'
);

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p3')::INT, 100);

SELECT is(
  (SELECT rating FROM ratings
   WHERE proposition_id = current_setting('test.prop_a')::INT
   AND participant_id = current_setting('test.p3')::INT),
  100,
  'Rating of 100 allowed'
);

-- =============================================================================
-- MULTIPLE RATINGS
-- =============================================================================

-- Add more ratings for all propositions
INSERT INTO ratings (proposition_id, participant_id, rating) VALUES
  -- Prop Alpha: 85, 0, 100 already added, add more
  (current_setting('test.prop_a')::INT, current_setting('test.p4')::INT, 70),
  (current_setting('test.prop_a')::INT, current_setting('test.p5')::INT, 90),
  -- Prop Beta
  (current_setting('test.prop_b')::INT, current_setting('test.p1')::INT, 60),
  (current_setting('test.prop_b')::INT, current_setting('test.p2')::INT, 65),
  (current_setting('test.prop_b')::INT, current_setting('test.p3')::INT, 70),
  (current_setting('test.prop_b')::INT, current_setting('test.p4')::INT, 55),
  (current_setting('test.prop_b')::INT, current_setting('test.p5')::INT, 50),
  -- Prop Gamma
  (current_setting('test.prop_g')::INT, current_setting('test.p1')::INT, 40),
  (current_setting('test.prop_g')::INT, current_setting('test.p2')::INT, 45),
  (current_setting('test.prop_g')::INT, current_setting('test.p3')::INT, 35),
  (current_setting('test.prop_g')::INT, current_setting('test.p4')::INT, 50),
  (current_setting('test.prop_g')::INT, current_setting('test.p5')::INT, 30);

-- Test 4: All ratings for Prop Alpha
SELECT is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  5::bigint,
  '5 ratings for Prop Alpha'
);

-- Test 5: All ratings for Prop Beta
SELECT is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_b')::INT),
  5::bigint,
  '5 ratings for Prop Beta'
);

-- Test 6: All ratings for Prop Gamma
SELECT is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_g')::INT),
  5::bigint,
  '5 ratings for Prop Gamma'
);

-- =============================================================================
-- AVERAGE RATING CALCULATIONS
-- =============================================================================

-- Test 7: Average for Prop Alpha = (85+0+100+70+90)/5 = 69
SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  69,
  'Average rating for Prop Alpha is 69'
);

-- Test 8: Average for Prop Beta = (60+65+70+55+50)/5 = 60
SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_b')::INT),
  60,
  'Average rating for Prop Beta is 60'
);

-- Test 9: Average for Prop Gamma = (40+45+35+50+30)/5 = 40
SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_g')::INT),
  40,
  'Average rating for Prop Gamma is 40'
);

-- =============================================================================
-- PROPOSITION_MOVDA_RATINGS TABLE (MOVDA scores)
-- =============================================================================

-- Store calculated ratings in proposition_movda_ratings (simulating MOVDA output)
INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
SELECT proposition_id, current_setting('test.round_id')::INT, AVG(rating)::NUMERIC
FROM ratings
WHERE proposition_id IN (
  current_setting('test.prop_a')::INT,
  current_setting('test.prop_b')::INT,
  current_setting('test.prop_g')::INT
)
GROUP BY proposition_id;

-- Test 10: Proposition MOVDA ratings created
SELECT is(
  (SELECT COUNT(*) FROM proposition_movda_ratings
   WHERE proposition_id IN (
     current_setting('test.prop_a')::INT,
     current_setting('test.prop_b')::INT,
     current_setting('test.prop_g')::INT
   )),
  3::bigint,
  '3 proposition_movda_ratings created'
);

-- Test 11: Prop Alpha final rating
SELECT is(
  (SELECT rating::INT FROM proposition_movda_ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  69,
  'Prop Alpha final rating is 69'
);

-- Test 12: Prop Beta final rating
SELECT is(
  (SELECT rating::INT FROM proposition_movda_ratings WHERE proposition_id = current_setting('test.prop_b')::INT),
  60,
  'Prop Beta final rating is 60'
);

-- Test 13: Prop Gamma final rating
SELECT is(
  (SELECT rating::INT FROM proposition_movda_ratings WHERE proposition_id = current_setting('test.prop_g')::INT),
  40,
  'Prop Gamma final rating is 40'
);

-- =============================================================================
-- WINNER DETERMINATION
-- =============================================================================

-- Test 14: Winner has highest rating (Prop Alpha = 69)
SELECT is(
  (SELECT proposition_id FROM proposition_movda_ratings
   WHERE proposition_id IN (
     current_setting('test.prop_a')::INT,
     current_setting('test.prop_b')::INT,
     current_setting('test.prop_g')::INT
   )
   ORDER BY rating DESC
   LIMIT 1),
  current_setting('test.prop_a')::bigint,
  'Winner is Prop Alpha (highest rating)'
);

-- Test 15: Set round winner
UPDATE rounds
SET winning_proposition_id = current_setting('test.prop_a')::INT
WHERE id = current_setting('test.round_id')::INT;

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round_id')::INT),
  current_setting('test.prop_a')::bigint,
  'Round winner set to Prop Alpha'
);

-- =============================================================================
-- RATING CONSTRAINTS
-- =============================================================================

-- Test 16: Same participant cannot rate same proposition twice
SELECT throws_ok(
  $$INSERT INTO ratings (proposition_id, participant_id, rating)
    VALUES ($$ || current_setting('test.prop_a') || $$, $$ || current_setting('test.p1') || $$, 50)$$,
  '23505',  -- unique_violation
  NULL,
  'Same participant cannot rate same proposition twice'
);

-- Test 17: Participant can rate different propositions
SELECT is(
  (SELECT COUNT(DISTINCT proposition_id) FROM ratings WHERE participant_id = current_setting('test.p1')::INT),
  3::bigint,
  'Participant 1 rated all 3 propositions'
);

-- =============================================================================
-- RANKING (ORDER BY RATING)
-- =============================================================================

-- Test 18: Propositions ranked by rating
WITH ranked AS (
  SELECT
    proposition_id,
    rating,
    ROW_NUMBER() OVER (ORDER BY rating DESC) as rank
  FROM proposition_movda_ratings
  WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )
)
SELECT is(
  (SELECT proposition_id FROM ranked WHERE rank = 1),
  current_setting('test.prop_a')::bigint,
  'Rank 1 is Prop Alpha'
);

-- Test 19: Rank 2
WITH ranked AS (
  SELECT
    proposition_id,
    rating,
    ROW_NUMBER() OVER (ORDER BY rating DESC) as rank
  FROM proposition_movda_ratings
  WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )
)
SELECT is(
  (SELECT proposition_id FROM ranked WHERE rank = 2),
  current_setting('test.prop_b')::bigint,
  'Rank 2 is Prop Beta'
);

-- Test 20: Rank 3
WITH ranked AS (
  SELECT
    proposition_id,
    rating,
    ROW_NUMBER() OVER (ORDER BY rating DESC) as rank
  FROM proposition_movda_ratings
  WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )
)
SELECT is(
  (SELECT proposition_id FROM ranked WHERE rank = 3),
  current_setting('test.prop_g')::bigint,
  'Rank 3 is Prop Gamma'
);

-- =============================================================================
-- EDGE CASES
-- =============================================================================

-- Test 21: Rating with only one rater
INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.round_id')::INT, current_setting('test.p4')::INT, 'Solo Prop');

DO $$
DECLARE
  v_solo_id INT;
BEGIN
  SELECT id INTO v_solo_id FROM propositions WHERE content = 'Solo Prop';
  PERFORM set_config('test.solo_prop', v_solo_id::TEXT, TRUE);
END $$;

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.solo_prop')::INT, current_setting('test.p1')::INT, 75);

SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.solo_prop')::INT),
  75,
  'Single rating gives that rating as average'
);

-- Test 22: Rating 50 (middle value)
INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.round_id')::INT, current_setting('test.p5')::INT, 'Middle Prop');

DO $$
DECLARE
  v_mid_id INT;
BEGIN
  SELECT id INTO v_mid_id FROM propositions WHERE content = 'Middle Prop';
  PERFORM set_config('test.mid_prop', v_mid_id::TEXT, TRUE);
END $$;

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.mid_prop')::INT, current_setting('test.p1')::INT, 50);

SELECT is(
  (SELECT rating FROM ratings WHERE proposition_id = current_setting('test.mid_prop')::INT),
  50,
  'Rating of 50 (middle) allowed'
);

-- Test 23: Rating timestamps
SELECT ok(
  (SELECT created_at FROM ratings WHERE proposition_id = current_setting('test.mid_prop')::INT) IS NOT NULL,
  'Rating has created_at timestamp'
);

-- Test 24: Proposition_ratings timestamps
SELECT ok(
  (SELECT created_at FROM proposition_movda_ratings WHERE proposition_id = current_setting('test.prop_a')::INT) IS NOT NULL,
  'Proposition_ratings has created_at timestamp'
);

-- Test 25: Multiple ratings for same proposition update average
-- Current: Alpha has 5 ratings, avg = 69
-- Add one more with 0 -> new avg = (85+0+100+70+90+0)/6 = 57.5 -> 57
DO $$
DECLARE
  v_p6 INT;
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (current_setting('test.chat_id')::INT, gen_random_uuid(), 'Rater 6', FALSE, 'active')
  RETURNING id INTO v_p6;
  PERFORM set_config('test.p6', v_p6::TEXT, TRUE);
END $$;

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p6')::INT, 0);

SELECT is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  58,
  'Adding 6th rating updates average (69 -> 58)'
);

SELECT * FROM finish();
ROLLBACK;
