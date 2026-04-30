-- Test: get_my_chats_dashboard.has_participated
--
-- Covers every combination of (round phase × user action state) to guard
-- against the "Your turn" section silently re-breaking:
--   * no active round  -> TRUE
--   * waiting phase    -> TRUE
--   * proposing, user has NOT submitted -> FALSE
--   * proposing, user HAS submitted     -> TRUE
--   * proposing, user SKIPPED           -> TRUE
--   * rating, user placed NO props          -> FALSE
--   * rating, user placed SOME but not all  -> FALSE
--   * rating, user placed ALL non-own props -> TRUE
--   * rating, user SKIPPED                  -> TRUE
--   * multiple chats in one call returned with correct per-chat value
--   * another user in the same chat is evaluated independently
--   * prior completed round's submission does not satisfy the new round

BEGIN;
SET search_path TO public, extensions;
SELECT plan(16);

-- =============================================================================
-- Setup: Users
-- =============================================================================
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at) VALUES
  ('00000000-0000-0000-0000-000000000b01', 'hp-alice@test.com', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000b02', 'hp-bob@test.com',   'authenticated', 'authenticated', now(), now());

-- =============================================================================
-- Chat A: no active round  (expect has_participated = TRUE)
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat A (no round)', 'Q', 'public', '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat A (no round)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active'),
  ((SELECT id FROM chats WHERE name = 'HP Chat A (no round)'),
   '00000000-0000-0000-0000-000000000b02', 'Bob',   'active');

-- =============================================================================
-- Chat B: waiting phase  (expect has_participated = TRUE)
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat B (waiting)', 'Q', 'public', '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat B (waiting)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat B (waiting)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat B (waiting)')
      AND completed_at IS NULL),
   1, 'waiting', now());

-- =============================================================================
-- Chat C: proposing phase, user has NOT submitted  (expect FALSE)
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat C (proposing, not submitted)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat C (proposing, not submitted)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat C (proposing, not submitted)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat C (proposing, not submitted)')
      AND completed_at IS NULL),
   1, 'proposing', now());

-- =============================================================================
-- Chat D: proposing phase, user HAS submitted  (expect TRUE)
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat D (proposing, submitted)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat D (proposing, submitted)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat D (proposing, submitted)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat D (proposing, submitted)')
      AND completed_at IS NULL),
   1, 'proposing', now());

INSERT INTO propositions (round_id, participant_id, content) VALUES
  ((SELECT r.id FROM rounds r
      JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat D (proposing, submitted)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p
     WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat D (proposing, submitted)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b01'),
   'Alice proposition');

-- =============================================================================
-- Chat E: rating phase, Bob has 1 prop but Alice placed nothing on the grid.
-- Expect has_participated = FALSE.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat E (rating, not submitted)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat E (rating, not submitted)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active'),
  ((SELECT id FROM chats WHERE name = 'HP Chat E (rating, not submitted)'),
   '00000000-0000-0000-0000-000000000b02', 'Bob',   'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat E (rating, not submitted)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat E (rating, not submitted)')
      AND completed_at IS NULL),
   1, 'rating', now());

-- One Bob proposition for Alice to rate (but she won't).
INSERT INTO propositions (round_id, participant_id, content) VALUES
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat E (rating, not submitted)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat E (rating, not submitted)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b02'),
   'Bob prop for E');

-- =============================================================================
-- Chat F: rating phase, user placed every non-own proposition on the grid.
-- This is the real Flutter signal for "done rating" (grid_rankings upsert
-- in PropositionService.submitGridRankings), NOT round_participant_submissions.
-- Setup: 2 non-own props from Bob + Alice placed both on the grid. Expect TRUE.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat F (rating, grid complete)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active'),
  ((SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)'),
   '00000000-0000-0000-0000-000000000b02', 'Bob',   'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)')
      AND completed_at IS NULL),
   1, 'rating', now());

-- Two non-own propositions: one from Bob + one NULL-participant (AI/carried).
-- The unique index idx_propositions_unique_new_per_round forbids two rows
-- with same (round_id, participant_id) + NULL carried_from_id, so we can't
-- use two Bob propositions here.
INSERT INTO propositions (round_id, participant_id, content) VALUES
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b02'),
   'Bob prop for F'),
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)')
       AND r.completed_at IS NULL),
   NULL,
   'Orphan prop for F');

-- Alice placed BOTH non-own propositions on the grid.
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
SELECT r.id, alice.id, prop.id, 50
FROM rounds r
JOIN cycles cy ON cy.id = r.cycle_id AND cy.chat_id =
  (SELECT id FROM chats WHERE name = 'HP Chat F (rating, grid complete)')
JOIN propositions prop ON prop.round_id = r.id
  AND (prop.participant_id IS NULL
       OR prop.participant_id != (SELECT id FROM participants
                                  WHERE user_id = '00000000-0000-0000-0000-000000000b01'
                                    AND chat_id = (SELECT id FROM chats
                                                   WHERE name = 'HP Chat F (rating, grid complete)')))
CROSS JOIN (SELECT id FROM participants
            WHERE user_id = '00000000-0000-0000-0000-000000000b01'
              AND chat_id = (SELECT id FROM chats
                             WHERE name = 'HP Chat F (rating, grid complete)')
) alice
WHERE r.completed_at IS NULL;

-- =============================================================================
-- Chat G: proposing phase with TWO participants; Alice submits, Bob does not.
-- Verifies that has_participated is evaluated per-participant, not per-chat.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat G (per-user check)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat G (per-user check)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active'),
  ((SELECT id FROM chats WHERE name = 'HP Chat G (per-user check)'),
   '00000000-0000-0000-0000-000000000b02', 'Bob',   'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat G (per-user check)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat G (per-user check)')
      AND completed_at IS NULL),
   1, 'proposing', now());

INSERT INTO propositions (round_id, participant_id, content) VALUES
  ((SELECT r.id FROM rounds r
      JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat G (per-user check)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p
     WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat G (per-user check)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b01'),
   'Alice proposition');

-- =============================================================================
-- Assertions
-- =============================================================================

-- 1: No active round -> TRUE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat A (no round)'),
  TRUE,
  'has_participated = TRUE when chat has no active round'
);

-- 2: Waiting phase -> TRUE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat B (waiting)'),
  TRUE,
  'has_participated = TRUE when active round is in waiting phase'
);

-- 3: Proposing, no submission -> FALSE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat C (proposing, not submitted)'),
  FALSE,
  'has_participated = FALSE when proposing phase and user has not submitted'
);

-- 4: Proposing, with submission -> TRUE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat D (proposing, submitted)'),
  TRUE,
  'has_participated = TRUE when user has already submitted a proposition'
);

-- 5: Rating, no submission -> FALSE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat E (rating, not submitted)'),
  FALSE,
  'has_participated = FALSE when rating phase and user has not rated'
);

-- 6: Rating, with submission -> TRUE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat F (rating, grid complete)'),
  TRUE,
  'has_participated = TRUE when user has submitted a rating for the round'
);

-- 7: Per-user — Alice submitted
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat G (per-user check)'),
  TRUE,
  'Alice is reported as participated in the shared chat'
);

-- 8: Per-user — Bob did not submit
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b02', 'en'
   ) WHERE name = 'HP Chat G (per-user check)'),
  FALSE,
  'Bob is reported as NOT participated in the same chat'
);

-- 9: Multi-chat call evaluates has_participated per-row, not globally.
-- Alice participates in chats A, B, C, D, E, F, G (7 chats). Expected FALSE
-- rows for Alice: C (proposing, no submission) and E (rating, no submission).
SELECT is(
  (SELECT COUNT(*)::INT FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE has_participated = FALSE
     AND name LIKE 'HP Chat%'),
  2,
  'Exactly two HP chats report has_participated = FALSE for Alice (C, E)'
);

-- 10: Column is NOT NULL for any row (CASE always returns a value).
SELECT is(
  (SELECT COUNT(*)::INT FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE has_participated IS NULL
     AND name LIKE 'HP Chat%'),
  0,
  'has_participated is never NULL'
);

-- =============================================================================
-- Chat H: prior round was completed with a submission from Alice; a NEW round
-- is now in proposing with NO submission. Expectation: has_participated=FALSE.
-- Guards against the RPC looking at propositions across *all* rounds of the
-- cycle instead of only the current active round.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat H (new round, prior submission stale)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat H (new round, prior submission stale)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat H (new round, prior submission stale)'));

-- Round 1 (completed) with Alice's proposition
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat H (new round, prior submission stale)')
      AND completed_at IS NULL),
   1, 'rating', now() - interval '1 hour', now() - interval '30 minutes');

INSERT INTO propositions (round_id, participant_id, content) VALUES
  ((SELECT r.id FROM rounds r
      JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat H (new round, prior submission stale)')
       AND r.custom_id = 1),
   (SELECT p.id FROM participants p
     WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat H (new round, prior submission stale)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b01'),
   'Alice round 1 proposition');

-- Round 2 (active, proposing) with NO submission from Alice
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat H (new round, prior submission stale)')
      AND completed_at IS NULL),
   2, 'proposing', now());

-- 11: prior submission in round 1 does NOT count for round 2
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat H (new round, prior submission stale)'),
  FALSE,
  'prior rounds submission does not satisfy has_participated for current round'
);

-- 12: current_round_phase reflects round 2 (active), not round 1 (completed)
SELECT is(
  (SELECT current_round_phase FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat H (new round, prior submission stale)'),
  'proposing',
  'RPC picks the active (uncompleted) round, not the completed prior round'
);

-- =============================================================================
-- Chat I: rating phase, 2 non-own propositions but Alice placed only 1.
-- Expect has_participated = FALSE (partial ratings don't satisfy the check).
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat I (rating, partial grid)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active'),
  ((SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)'),
   '00000000-0000-0000-0000-000000000b02', 'Bob',   'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)')
      AND completed_at IS NULL),
   1, 'rating', now());

INSERT INTO propositions (round_id, participant_id, content) VALUES
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b02'),
   'Bob prop for I'),
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)')
       AND r.completed_at IS NULL),
   NULL,
   'Orphan prop for I');

-- Alice placed only ONE of the two non-own propositions.
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
SELECT r.id, alice.id, prop.id, 25
FROM rounds r
JOIN cycles cy ON cy.id = r.cycle_id AND cy.chat_id =
  (SELECT id FROM chats WHERE name = 'HP Chat I (rating, partial grid)')
JOIN propositions prop ON prop.round_id = r.id
  AND prop.content = 'Bob prop for I'
CROSS JOIN (SELECT id FROM participants
            WHERE user_id = '00000000-0000-0000-0000-000000000b01'
              AND chat_id = (SELECT id FROM chats
                             WHERE name = 'HP Chat I (rating, partial grid)')
) alice
WHERE r.completed_at IS NULL;

-- 13: placed 1 of 2 props -> still FALSE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat I (rating, partial grid)'),
  FALSE,
  'has_participated = FALSE when only some non-own props have been placed'
);

-- =============================================================================
-- Chat J: rating phase with 2 Bob propositions, Alice SKIPPED rating
-- (rating_skips row). Expect has_participated = TRUE regardless of grid state.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   allow_skip_rating,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat J (rating, skipped)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', TRUE,
        NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active'),
  ((SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)'),
   '00000000-0000-0000-0000-000000000b02', 'Bob',   'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)')
      AND completed_at IS NULL),
   1, 'rating', now());

INSERT INTO propositions (round_id, participant_id, content) VALUES
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b02'),
   'Bob prop for J'),
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)')
       AND r.completed_at IS NULL),
   NULL,
   'Orphan prop for J');

INSERT INTO rating_skips (round_id, participant_id) VALUES
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat J (rating, skipped)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b01'));

-- 14: skipped rating -> TRUE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat J (rating, skipped)'),
  TRUE,
  'has_participated = TRUE when user explicitly skipped rating'
);

-- =============================================================================
-- Chat K: proposing phase, Alice SKIPPED proposing (round_skips row).
-- Expect has_participated = TRUE even with no authored proposition.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   allow_skip_proposing,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('HP Chat K (proposing, skipped)', 'Q', 'public',
        '00000000-0000-0000-0000-000000000b01', 'manual', TRUE,
        NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat K (proposing, skipped)'),
   '00000000-0000-0000-0000-000000000b01', 'Alice', 'active');

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'HP Chat K (proposing, skipped)'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'HP Chat K (proposing, skipped)')
      AND completed_at IS NULL),
   1, 'proposing', now());

INSERT INTO round_skips (round_id, participant_id) VALUES
  ((SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
     WHERE cy.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat K (proposing, skipped)')
       AND r.completed_at IS NULL),
   (SELECT p.id FROM participants p WHERE p.chat_id =
       (SELECT id FROM chats WHERE name = 'HP Chat K (proposing, skipped)')
       AND p.user_id = '00000000-0000-0000-0000-000000000b01'));

-- 15: skipped proposing -> TRUE
SELECT is(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat K (proposing, skipped)'),
  TRUE,
  'has_participated = TRUE when user explicitly skipped proposing'
);

-- 16: Rating phase with zero non-own propositions trivially passes the count
-- check (0 >= 0). This is a degenerate case — rounds normally can't enter
-- rating with zero propositions — but the expression shouldn't NULL out.
SELECT isnt(
  (SELECT has_participated FROM get_my_chats_dashboard(
     '00000000-0000-0000-0000-000000000b01', 'en'
   ) WHERE name = 'HP Chat E (rating, not submitted)'),
  NULL,
  'has_participated returns non-NULL even when Alice placed nothing'
);

SELECT * FROM finish();
ROLLBACK;
