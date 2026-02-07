-- Ratings and proposition_ratings tests
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(25);

-- =============================================================================
-- SETUP
-- =============================================================================

INSERT INTO users (id, email, display_name)
VALUES ('55555555-5555-5555-5555-555555555555', 'ratinghost@example.com', 'Rating Host');

INSERT INTO chats (name, initial_message, creator_id)
VALUES ('Rating Test Chat', 'Test ratings', '55555555-5555-5555-5555-555555555555');

DO $$
DECLARE
  v_chat_id INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Rating Test Chat';
  PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
END $$;

-- Create cycle and iteration
INSERT INTO cycles (chat_id, custom_id)
VALUES (current_setting('test.chat_id')::INT, 1);

DO $$
DECLARE
  v_cycle_id INT;
BEGIN
  SELECT id INTO v_cycle_id FROM cycles WHERE chat_id = current_setting('test.chat_id')::INT;
  PERFORM set_config('test.cycle_id', v_cycle_id::TEXT, TRUE);
END $$;

INSERT INTO iterations (cycle_id, custom_id, phase)
VALUES (current_setting('test.cycle_id')::INT, 1, 'proposing');

DO $$
DECLARE
  v_iter_id INT;
BEGIN
  SELECT id INTO v_iter_id FROM iterations WHERE cycle_id = current_setting('test.cycle_id')::INT;
  PERFORM set_config('test.iteration_id', v_iter_id::TEXT, TRUE);
END $$;

-- Create participants
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES
  (current_setting('test.chat_id')::INT, 'rater-1', 'Rater 1', FALSE, 'active'),
  (current_setting('test.chat_id')::INT, 'rater-2', 'Rater 2', FALSE, 'active'),
  (current_setting('test.chat_id')::INT, 'rater-3', 'Rater 3', FALSE, 'active'),
  (current_setting('test.chat_id')::INT, 'rater-4', 'Rater 4', FALSE, 'active'),
  (current_setting('test.chat_id')::INT, 'rater-5', 'Rater 5', FALSE, 'active');

DO $$
DECLARE
  v_p1 INT;
  v_p2 INT;
  v_p3 INT;
  v_p4 INT;
  v_p5 INT;
BEGIN
  SELECT id INTO v_p1 FROM participants WHERE session_token = 'rater-1';
  SELECT id INTO v_p2 FROM participants WHERE session_token = 'rater-2';
  SELECT id INTO v_p3 FROM participants WHERE session_token = 'rater-3';
  SELECT id INTO v_p4 FROM participants WHERE session_token = 'rater-4';
  SELECT id INTO v_p5 FROM participants WHERE session_token = 'rater-5';

  PERFORM set_config('test.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.p3', v_p3::TEXT, TRUE);
  PERFORM set_config('test.p4', v_p4::TEXT, TRUE);
  PERFORM set_config('test.p5', v_p5::TEXT, TRUE);
END $$;

-- Create propositions
INSERT INTO propositions (iteration_id, participant_id, content)
VALUES
  (current_setting('test.iteration_id')::INT, current_setting('test.p1')::INT, 'Prop Alpha'),
  (current_setting('test.iteration_id')::INT, current_setting('test.p2')::INT, 'Prop Beta'),
  (current_setting('test.iteration_id')::INT, current_setting('test.p3')::INT, 'Prop Gamma');

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
UPDATE iterations SET phase = 'rating' WHERE id = current_setting('test.iteration_id')::INT;

-- =============================================================================
-- RATING BASICS
-- =============================================================================

-- Test 1: Create rating
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p1')::INT, 85);

SELECT extensions.is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  1::bigint,
  'Rating created successfully'
);

-- Test 2: Rating value stored correctly
SELECT extensions.is(
  (SELECT rating FROM ratings
   WHERE proposition_id = current_setting('test.prop_a')::INT
   AND participant_id = current_setting('test.p1')::INT),
  85,
  'Rating value stored correctly'
);

-- Test 3: Rating range 0-100 (valid values)
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p2')::INT, 0);

SELECT extensions.is(
  (SELECT rating FROM ratings
   WHERE proposition_id = current_setting('test.prop_a')::INT
   AND participant_id = current_setting('test.p2')::INT),
  0,
  'Rating of 0 allowed'
);

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p3')::INT, 100);

SELECT extensions.is(
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
SELECT extensions.is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  5::bigint,
  '5 ratings for Prop Alpha'
);

-- Test 5: All ratings for Prop Beta
SELECT extensions.is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_b')::INT),
  5::bigint,
  '5 ratings for Prop Beta'
);

-- Test 6: All ratings for Prop Gamma
SELECT extensions.is(
  (SELECT COUNT(*) FROM ratings WHERE proposition_id = current_setting('test.prop_g')::INT),
  5::bigint,
  '5 ratings for Prop Gamma'
);

-- =============================================================================
-- AVERAGE RATING CALCULATIONS
-- =============================================================================

-- Test 7: Average for Prop Alpha = (85+0+100+70+90)/5 = 69
SELECT extensions.is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  69,
  'Average rating for Prop Alpha is 69'
);

-- Test 8: Average for Prop Beta = (60+65+70+55+50)/5 = 60
SELECT extensions.is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_b')::INT),
  60,
  'Average rating for Prop Beta is 60'
);

-- Test 9: Average for Prop Gamma = (40+45+35+50+30)/5 = 40
SELECT extensions.is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_g')::INT),
  40,
  'Average rating for Prop Gamma is 40'
);

-- =============================================================================
-- PROPOSITION_RATINGS TABLE
-- =============================================================================

-- Store calculated ratings in proposition_ratings
INSERT INTO proposition_ratings (proposition_id, rating)
SELECT proposition_id, AVG(rating)::INT
FROM ratings
WHERE proposition_id IN (
  current_setting('test.prop_a')::INT,
  current_setting('test.prop_b')::INT,
  current_setting('test.prop_g')::INT
)
GROUP BY proposition_id;

-- Test 10: Proposition ratings created
SELECT extensions.is(
  (SELECT COUNT(*) FROM proposition_ratings
   WHERE proposition_id IN (
     current_setting('test.prop_a')::INT,
     current_setting('test.prop_b')::INT,
     current_setting('test.prop_g')::INT
   )),
  3::bigint,
  '3 proposition_ratings created'
);

-- Test 11: Prop Alpha final rating
SELECT extensions.is(
  (SELECT rating FROM proposition_ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  69,
  'Prop Alpha final rating is 69'
);

-- Test 12: Prop Beta final rating
SELECT extensions.is(
  (SELECT rating FROM proposition_ratings WHERE proposition_id = current_setting('test.prop_b')::INT),
  60,
  'Prop Beta final rating is 60'
);

-- Test 13: Prop Gamma final rating
SELECT extensions.is(
  (SELECT rating FROM proposition_ratings WHERE proposition_id = current_setting('test.prop_g')::INT),
  40,
  'Prop Gamma final rating is 40'
);

-- =============================================================================
-- WINNER DETERMINATION
-- =============================================================================

-- Test 14: Winner has highest rating (Prop Alpha = 69)
SELECT extensions.is(
  (SELECT proposition_id FROM proposition_ratings
   WHERE proposition_id IN (
     current_setting('test.prop_a')::INT,
     current_setting('test.prop_b')::INT,
     current_setting('test.prop_g')::INT
   )
   ORDER BY rating DESC
   LIMIT 1),
  current_setting('test.prop_a')::INT,
  'Winner is Prop Alpha (highest rating)'
);

-- Test 15: Set iteration winner
UPDATE iterations
SET winner_proposition_id = current_setting('test.prop_a')::INT
WHERE id = current_setting('test.iteration_id')::INT;

SELECT extensions.is(
  (SELECT winner_proposition_id FROM iterations WHERE id = current_setting('test.iteration_id')::INT),
  current_setting('test.prop_a')::INT,
  'Iteration winner set to Prop Alpha'
);

-- =============================================================================
-- RATING CONSTRAINTS
-- =============================================================================

-- Test 16: Same participant cannot rate same proposition twice
SELECT extensions.throws_ok(
  $$INSERT INTO ratings (proposition_id, participant_id, rating)
    VALUES ($$ || current_setting('test.prop_a') || $$, $$ || current_setting('test.p1') || $$, 50)$$,
  '23505',  -- unique_violation
  NULL,
  'Same participant cannot rate same proposition twice'
);

-- Test 17: Participant can rate different propositions
SELECT extensions.is(
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
  FROM proposition_ratings
  WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )
)
SELECT extensions.is(
  (SELECT proposition_id FROM ranked WHERE rank = 1),
  current_setting('test.prop_a')::INT,
  'Rank 1 is Prop Alpha'
);

-- Test 19: Rank 2
WITH ranked AS (
  SELECT
    proposition_id,
    rating,
    ROW_NUMBER() OVER (ORDER BY rating DESC) as rank
  FROM proposition_ratings
  WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )
)
SELECT extensions.is(
  (SELECT proposition_id FROM ranked WHERE rank = 2),
  current_setting('test.prop_b')::INT,
  'Rank 2 is Prop Beta'
);

-- Test 20: Rank 3
WITH ranked AS (
  SELECT
    proposition_id,
    rating,
    ROW_NUMBER() OVER (ORDER BY rating DESC) as rank
  FROM proposition_ratings
  WHERE proposition_id IN (
    current_setting('test.prop_a')::INT,
    current_setting('test.prop_b')::INT,
    current_setting('test.prop_g')::INT
  )
)
SELECT extensions.is(
  (SELECT proposition_id FROM ranked WHERE rank = 3),
  current_setting('test.prop_g')::INT,
  'Rank 3 is Prop Gamma'
);

-- =============================================================================
-- EDGE CASES
-- =============================================================================

-- Test 21: Rating with only one rater
INSERT INTO propositions (iteration_id, participant_id, content)
VALUES (current_setting('test.iteration_id')::INT, current_setting('test.p4')::INT, 'Solo Prop');

DO $$
DECLARE
  v_solo_id INT;
BEGIN
  SELECT id INTO v_solo_id FROM propositions WHERE content = 'Solo Prop';
  PERFORM set_config('test.solo_prop', v_solo_id::TEXT, TRUE);
END $$;

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.solo_prop')::INT, current_setting('test.p1')::INT, 75);

SELECT extensions.is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.solo_prop')::INT),
  75,
  'Single rating gives that rating as average'
);

-- Test 22: Rating 50 (middle value)
INSERT INTO propositions (iteration_id, participant_id, content)
VALUES (current_setting('test.iteration_id')::INT, current_setting('test.p5')::INT, 'Middle Prop');

DO $$
DECLARE
  v_mid_id INT;
BEGIN
  SELECT id INTO v_mid_id FROM propositions WHERE content = 'Middle Prop';
  PERFORM set_config('test.mid_prop', v_mid_id::TEXT, TRUE);
END $$;

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.mid_prop')::INT, current_setting('test.p1')::INT, 50);

SELECT extensions.is(
  (SELECT rating FROM ratings WHERE proposition_id = current_setting('test.mid_prop')::INT),
  50,
  'Rating of 50 (middle) allowed'
);

-- Test 23: Rating timestamps
SELECT extensions.ok(
  (SELECT created_at FROM ratings WHERE proposition_id = current_setting('test.mid_prop')::INT) IS NOT NULL,
  'Rating has created_at timestamp'
);

-- Test 24: Proposition_ratings timestamps
SELECT extensions.ok(
  (SELECT created_at FROM proposition_ratings WHERE proposition_id = current_setting('test.prop_a')::INT) IS NOT NULL,
  'Proposition_ratings has created_at timestamp'
);

-- Test 25: Multiple ratings for same proposition update average
-- Current: Alpha has 5 ratings, avg = 69
-- Add one more with 0 -> new avg = (85+0+100+70+90+0)/6 = 57.5 -> 57
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (current_setting('test.chat_id')::INT, 'rater-6', 'Rater 6', FALSE, 'active');

DO $$
DECLARE
  v_p6 INT;
BEGIN
  SELECT id INTO v_p6 FROM participants WHERE session_token = 'rater-6';
  PERFORM set_config('test.p6', v_p6::TEXT, TRUE);
END $$;

INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.prop_a')::INT, current_setting('test.p6')::INT, 0);

SELECT extensions.is(
  (SELECT AVG(rating)::INT FROM ratings WHERE proposition_id = current_setting('test.prop_a')::INT),
  57,
  'Adding 6th rating updates average (69 -> 57)'
);

SELECT * FROM finish();
ROLLBACK;
