-- Convergence tie-tolerance regression tests.
--
-- Locks in the contract from migration 20260501170000:
--   complete_round_with_winner now treats two propositions as tied
--   for first when their global_score gap is ≤ 1.0, matching the
--   UI's display-bucket grouping (RatingStackTolerance.displayBucket
--   in rating_model.dart).
--
-- The tie detection is encapsulated in count_tied_top_propositions()
-- which can be tested with arbitrary inputs by manually populating
-- proposition_global_scores. Plus an end-to-end test that
-- complete_round_with_winner sets is_sole_winner correctly via the
-- helper.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(21);

-- =============================================================================
-- Constant: tolerance is 1.0 and stays in sync with UI
-- =============================================================================

SELECT is(
    convergence_tie_tolerance(),
    1.0::REAL,
    'convergence_tie_tolerance() returns 1.0 (matches UI displayBucket)'
);

-- =============================================================================
-- Fixture: a round with no propositions
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Tie Tolerance Test', 'Q', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_empty_round INT;
  v_round_a INT;  -- 1 prop
  v_round_b INT;  -- 2 props, exact tie
  v_round_c INT;  -- 2 props, gap 0.5 (within tolerance)
  v_round_d INT;  -- 2 props, gap 0.99 (within tolerance, edge)
  v_round_e INT;  -- 2 props, gap 1.0 (boundary, tied because >= condition)
  v_round_f INT;  -- 2 props, gap 1.5 (clearly outside)
  v_round_g INT;  -- 3 props, top two tied within tolerance, third clearly separate
  v_round_h INT;  -- NCDD R1 replica (16 props)
  v_participants BIGINT[];  -- 16 distinct participants for proposition authorship
  v_p1 INT;       -- helper for individual prop ids
  v_p2 INT;
  v_p3 INT;
  v_pid BIGINT;
  v_i INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Tie Tolerance Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

  -- Sixteen distinct participants. The unique constraint
  -- idx_propositions_unique_new_per_round enforces (round_id,
  -- participant_id) uniqueness for new (non-carry-forward)
  -- propositions, so each round needs each prop authored by a
  -- different participant. The largest round in this test has 16
  -- propositions (NCDD R1 replica), so we create 16 participants
  -- up-front and reuse them across rounds.
  v_participants := ARRAY[]::BIGINT[];
  FOR v_i IN 1..16 LOOP
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (
      v_chat_id,
      gen_random_uuid(),
      'Participant ' || v_i,
      v_i = 1,  -- first participant is host
      'active'
    )
    RETURNING id INTO v_pid;
    v_participants := array_append(v_participants, v_pid);
  END LOOP;

  -- ============= Empty round =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating')
  RETURNING id INTO v_empty_round;

  -- ============= 1 prop =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 2, 'rating')
  RETURNING id INTO v_round_a;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_a, v_participants[1], 'a1')
  RETURNING id INTO v_p1;
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_p1, v_round_a, 100.0::REAL);

  -- ============= Exact tie =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 3, 'rating')
  RETURNING id INTO v_round_b;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_b, v_participants[1], 'b1') RETURNING id INTO v_p1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_b, v_participants[2], 'b2') RETURNING id INTO v_p2;
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_p1, v_round_b, 50.0::REAL),
         (v_p2, v_round_b, 50.0::REAL);

  -- ============= Gap 0.5 (within tolerance, should tie) =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 4, 'rating')
  RETURNING id INTO v_round_c;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_c, v_participants[1], 'c-top') RETURNING id INTO v_p1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_c, v_participants[2], 'c-runner') RETURNING id INTO v_p2;
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_p1, v_round_c, 100.0::REAL),
         (v_p2, v_round_c, 99.5::REAL);

  -- ============= Gap 0.99 (within tolerance, edge) =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 5, 'rating')
  RETURNING id INTO v_round_d;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_d, v_participants[1], 'd-top') RETURNING id INTO v_p1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_d, v_participants[2], 'd-runner') RETURNING id INTO v_p2;
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_p1, v_round_d, 100.0::REAL),
         (v_p2, v_round_d, 99.01::REAL);

  -- ============= Gap exactly 1.0 (boundary, tied because tolerance is inclusive >=) =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 6, 'rating')
  RETURNING id INTO v_round_e;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_e, v_participants[1], 'e-top') RETURNING id INTO v_p1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_e, v_participants[2], 'e-runner') RETURNING id INTO v_p2;
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_p1, v_round_e, 100.0::REAL),
         (v_p2, v_round_e, 99.0::REAL);

  -- ============= Gap 1.5 (clearly outside tolerance, sole winner) =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 7, 'rating')
  RETURNING id INTO v_round_f;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_f, v_participants[1], 'f-top') RETURNING id INTO v_p1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_f, v_participants[2], 'f-runner') RETURNING id INTO v_p2;
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_p1, v_round_f, 100.0::REAL),
         (v_p2, v_round_f, 98.5::REAL);

  -- ============= Three propositions: top 2 tied, third clearly separate =============
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 8, 'rating')
  RETURNING id INTO v_round_g;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_g, v_participants[1], 'g-tied-1') RETURNING id INTO v_p1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_g, v_participants[2], 'g-tied-2') RETURNING id INTO v_p2;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_g, v_participants[3], 'g-far') RETURNING id INTO v_p3;
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_p1, v_round_g, 100.0::REAL),
         (v_p2, v_round_g, 99.7::REAL),
         (v_p3, v_round_g, 50.0::REAL);

  -- ============= NCDD R1 replica: 16 props with the actual scores =============
  -- See chat 309 R1 (2026-05-01). Top two are 0.09 apart (ingrained
  -- patterns + DEI question) and a second mid-cluster at 73.81/73.09
  -- is 0.72 apart. Both should be detected as ties.
  --
  -- Each proposition is authored by a distinct participant
  -- (v_participants[1..16]) — production-realistic, satisfies the
  -- per-(round, participant) unique constraint.
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 9, 'rating')
  RETURNING id INTO v_round_h;

  WITH names(content, score, slot) AS (VALUES
    ('ingrained patterns',        100.00::REAL,  1),
    ('DEI question',               99.91::REAL,  2),
    ('governmental interference',  92.67::REAL,  3),
    ('Red/Blue Divide',            88.25::REAL,  4),
    ('genAI values',               74.88::REAL,  5),
    ('critical thinking',          73.81::REAL,  6),
    ('mission/telos',              73.09::REAL,  7),
    ('departure of POC',           63.72::REAL,  8),
    ('AI skills',                  50.60::REAL,  9),
    ('sustained reading',          47.26::REAL, 10),
    ('literacy',                   45.68::REAL, 11),
    ('religion/LGBTQ+',            36.77::REAL, 12),
    ('civic engagement',           22.53::REAL, 13),
    ('Trump terror',               15.22::REAL, 14),
    ('interfaith dialogue',        10.86::REAL, 15),
    ('student motivation',          0.00::REAL, 16)
  ),
  inserted AS (
    INSERT INTO propositions (round_id, participant_id, content)
    SELECT v_round_h, v_participants[slot], content FROM names
    RETURNING id, content
  )
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  SELECT i.id, v_round_h, n.score
  FROM inserted i
  JOIN names n ON n.content = i.content;

  -- Persist round ids for the assertions below
  PERFORM set_config('test.empty_round',  v_empty_round::TEXT, TRUE);
  PERFORM set_config('test.round_a',      v_round_a::TEXT, TRUE);
  PERFORM set_config('test.round_b',      v_round_b::TEXT, TRUE);
  PERFORM set_config('test.round_c',      v_round_c::TEXT, TRUE);
  PERFORM set_config('test.round_d',      v_round_d::TEXT, TRUE);
  PERFORM set_config('test.round_e',      v_round_e::TEXT, TRUE);
  PERFORM set_config('test.round_f',      v_round_f::TEXT, TRUE);
  PERFORM set_config('test.round_g',      v_round_g::TEXT, TRUE);
  PERFORM set_config('test.round_h',      v_round_h::TEXT, TRUE);
END $$;

-- =============================================================================
-- count_tied_top_propositions: empty round
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.empty_round')::BIGINT),
    0,
    'empty round → 0 tied propositions'
);

-- =============================================================================
-- Single proposition → 1 tied (itself), would map to is_sole_winner = TRUE
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_a')::BIGINT),
    1,
    'single proposition → count is 1 (sole winner)'
);

-- =============================================================================
-- Exact tie → both propositions counted
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_b')::BIGINT),
    2,
    'exact tie (gap 0.0) → both propositions counted'
);

-- =============================================================================
-- Gap 0.5 → tied (within tolerance)
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_c')::BIGINT),
    2,
    'gap of 0.5 → both propositions counted (within tolerance)'
);

-- =============================================================================
-- Gap 0.99 → tied (just inside tolerance)
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_d')::BIGINT),
    2,
    'gap of 0.99 → both counted (just inside tolerance)'
);

-- =============================================================================
-- Gap exactly 1.0 → tied (the >= boundary is INCLUSIVE)
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_e')::BIGINT),
    2,
    'gap exactly 1.0 → both counted (boundary is inclusive: >= max - tolerance)'
);

-- =============================================================================
-- Gap 1.5 → only top counted (clearly outside tolerance)
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_f')::BIGINT),
    1,
    'gap of 1.5 → only top proposition counted (sole winner)'
);

-- =============================================================================
-- Three propositions: top two tied, third far
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_g')::BIGINT),
    2,
    'three propositions: top two within tolerance counted, third excluded'
);

-- =============================================================================
-- NCDD R1 replica: TWO near-tie clusters, but only the TOP cluster counts
-- toward "tied for first" (the mid cluster is the runner-up cluster, not top)
-- =============================================================================

SELECT is(
    count_tied_top_propositions(current_setting('test.round_h')::BIGINT),
    2,
    'NCDD R1 (16 props): top pair at 100.00 + 99.91 → tied for first '
    '(was previously declared sole winner under strict equality)'
);

-- =============================================================================
-- complete_round_with_winner: end-to-end is_sole_winner contract
-- (uses the same helper internally, this verifies the wiring)
-- =============================================================================

-- Round B (exact tie) → is_sole_winner = FALSE
SELECT lives_ok(
    $$SELECT complete_round_with_winner(current_setting('test.round_b')::BIGINT)$$,
    'complete_round_with_winner runs without error on exact-tie round'
);

SELECT is(
    (SELECT is_sole_winner FROM rounds
     WHERE id = current_setting('test.round_b')::BIGINT),
    FALSE,
    'exact tie → is_sole_winner = FALSE (no convergence chain advancement)'
);

-- Round C (gap 0.5) → is_sole_winner = FALSE under new tolerance
SELECT lives_ok(
    $$SELECT complete_round_with_winner(current_setting('test.round_c')::BIGINT)$$,
    'complete_round_with_winner runs on gap-0.5 round'
);

SELECT is(
    (SELECT is_sole_winner FROM rounds
     WHERE id = current_setting('test.round_c')::BIGINT),
    FALSE,
    'gap 0.5 → is_sole_winner = FALSE (the bug: was TRUE under strict equality)'
);

-- Round F (gap 1.5) → is_sole_winner = TRUE (clear winner)
SELECT lives_ok(
    $$SELECT complete_round_with_winner(current_setting('test.round_f')::BIGINT)$$,
    'complete_round_with_winner runs on gap-1.5 round'
);

SELECT is(
    (SELECT is_sole_winner FROM rounds
     WHERE id = current_setting('test.round_f')::BIGINT),
    TRUE,
    'gap 1.5 → is_sole_winner = TRUE (clear winner)'
);

-- =============================================================================
-- complete_round_with_winner is idempotent (re-running doesn't flip flags)
-- =============================================================================

SELECT lives_ok(
    $$SELECT complete_round_with_winner(current_setting('test.round_c')::BIGINT)$$,
    'complete_round_with_winner re-run is safe on already-completed round'
);

SELECT is(
    (SELECT is_sole_winner FROM rounds
     WHERE id = current_setting('test.round_c')::BIGINT),
    FALSE,
    'is_sole_winner unchanged after re-running complete_round_with_winner'
);

-- =============================================================================
-- complete_round_with_winner records ALL propositions in round_winners
-- (not just the tied ones) — preserves the existing rank-storage contract
-- =============================================================================

SELECT is(
    (SELECT COUNT(*)::INT FROM round_winners
     WHERE round_id = current_setting('test.round_g')::BIGINT),
    0,
    'round_winners empty before complete_round_with_winner is called for round G'
);

SELECT lives_ok(
    $$SELECT complete_round_with_winner(current_setting('test.round_g')::BIGINT)$$,
    'complete_round_with_winner runs on round G (3 props)'
);

SELECT cmp_ok(
    (SELECT COUNT(*)::INT FROM round_winners
     WHERE round_id = current_setting('test.round_g')::BIGINT),
    '>=', 3,
    'round_winners records ALL propositions ranked, not just tied ones'
);

SELECT * FROM finish();
ROLLBACK;
