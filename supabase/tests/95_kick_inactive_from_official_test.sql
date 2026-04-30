-- Test: auto-kick inactive participants from public chats (originally
-- official-only — expanded by 20260430140000 to cover all public chats).
--
-- Coverage:
--   1. Inactive participant in OFFICIAL chat → kicked.
--   2. Participant who proposed → NOT kicked.
--   3. Participant who skipped proposing → NOT kicked.
--   4. Participant who placed a grid ranking → NOT kicked.
--   5. Participant who skipped rating → NOT kicked.
--   6. Inactive participant in INVITE-ONLY chat → NOT kicked (scope guard).
--   7. Carried-forward proposition does NOT save the participant.
--   8. Mid-round joiner in official chat → NOT kicked.
--   9. Host of official chat → NOT kicked even with zero activity.
--  10. Trigger only fires on completed_at NULL → non-NULL.
--  11. Round still in flight → no kicks.
--  12. Already-left participant (status='left') → not flipped to 'kicked'.
--  13. Inactive participant in NON-OFFICIAL PUBLIC chat → KICKED (scope expansion).

BEGIN;
SET search_path TO public, extensions;
SELECT plan(13);

-- The schema enforces a single official chat (idx_chats_single_official)
-- and the seed installs one ("Welcome to OneMind"). The test creates
-- several official-chat fixtures back-to-back, so within this transaction
-- we drop the constraint and remove the seeded row. ROLLBACK at the end
-- restores both.
DROP INDEX IF EXISTS idx_chats_single_official;
DELETE FROM chats WHERE is_official = TRUE;

-- ---------------------------------------------------------------- helpers
CREATE OR REPLACE FUNCTION _kif_make_user(p_uuid UUID, p_email TEXT) RETURNS VOID AS $$
BEGIN
  INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
  VALUES (p_uuid, p_email, 'authenticated', 'authenticated', now(), now())
  ON CONFLICT DO NOTHING;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _kif_pid(p_chat_id BIGINT, p_user_id UUID)
RETURNS BIGINT AS $$
  SELECT id FROM participants WHERE chat_id = p_chat_id AND user_id = p_user_id;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION _kif_status(p_chat_id BIGINT, p_user_id UUID)
RETURNS TEXT AS $$
  SELECT status FROM participants
  WHERE chat_id = p_chat_id AND user_id = p_user_id;
$$ LANGUAGE SQL;

-- 6 test users
SELECT _kif_make_user('00000000-0000-0000-0000-00000000ff01', 'kif-alice@t.com');
SELECT _kif_make_user('00000000-0000-0000-0000-00000000ff02', 'kif-bob@t.com');
SELECT _kif_make_user('00000000-0000-0000-0000-00000000ff03', 'kif-carol@t.com');
SELECT _kif_make_user('00000000-0000-0000-0000-00000000ff04', 'kif-dan@t.com');
SELECT _kif_make_user('00000000-0000-0000-0000-00000000ff05', 'kif-eve@t.com');
SELECT _kif_make_user('00000000-0000-0000-0000-00000000ff06', 'kif-frank@t.com');

-- =============================================================================
-- Chat A: OFFICIAL — kick inactive, keep active variants, keep host.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Official A', 'Q', 'public',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        TRUE,
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official A'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice (host)', 'active', TRUE),
  ((SELECT id FROM chats WHERE name = 'KIF Official A'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob',   'active', FALSE),
  ((SELECT id FROM chats WHERE name = 'KIF Official A'),
   '00000000-0000-0000-0000-00000000ff03', 'Carol', 'active', FALSE),
  ((SELECT id FROM chats WHERE name = 'KIF Official A'),
   '00000000-0000-0000-0000-00000000ff04', 'Dan',   'active', FALSE),
  ((SELECT id FROM chats WHERE name = 'KIF Official A'),
   '00000000-0000-0000-0000-00000000ff05', 'Eve',   'active', FALSE),
  ((SELECT id FROM chats WHERE name = 'KIF Official A'),
   '00000000-0000-0000-0000-00000000ff06', 'Frank', 'active', FALSE);

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official A'));

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Official A') AND completed_at IS NULL),
   1, 'rating', now() - interval '5 minutes');

-- Bob: authored a non-carried proposition.
INSERT INTO propositions (round_id, participant_id, content)
VALUES (
  (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
   WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official A')
     AND r.completed_at IS NULL),
  _kif_pid((SELECT id FROM chats WHERE name = 'KIF Official A'),
           '00000000-0000-0000-0000-00000000ff02'),
  'Bob prop'
);

-- Carol: skipped proposing.
INSERT INTO round_skips (round_id, participant_id) VALUES (
  (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
   WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official A')
     AND r.completed_at IS NULL),
  _kif_pid((SELECT id FROM chats WHERE name = 'KIF Official A'),
           '00000000-0000-0000-0000-00000000ff03')
);

-- Dan: placed a grid ranking on Bob's prop.
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
SELECT r.id,
       _kif_pid((SELECT id FROM chats WHERE name = 'KIF Official A'),
                '00000000-0000-0000-0000-00000000ff04'),
       (SELECT id FROM propositions WHERE content = 'Bob prop'),
       50
FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official A')
  AND r.completed_at IS NULL;

-- Eve: skipped rating.
INSERT INTO rating_skips (round_id, participant_id) VALUES (
  (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
   WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official A')
     AND r.completed_at IS NULL),
  _kif_pid((SELECT id FROM chats WHERE name = 'KIF Official A'),
           '00000000-0000-0000-0000-00000000ff05')
);

-- Frank: did nothing. Alice (host) also did nothing — but is host.

-- Complete the round → trigger fires.
UPDATE rounds SET completed_at = now()
WHERE id = (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
            WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official A')
              AND r.completed_at IS NULL);

-- 1: Frank kicked.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official A'),
                      '00000000-0000-0000-0000-00000000ff06'),
          'kicked',
          'Frank (zero activity) kicked from official chat');

-- 2: Bob (proposed) NOT kicked.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official A'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'active',
          'Bob (proposed) stays active');

-- 3: Carol (skipped proposing) NOT kicked.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official A'),
                      '00000000-0000-0000-0000-00000000ff03'),
          'active',
          'Carol (skipped proposing) stays active');

-- 4: Dan (rated) NOT kicked.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official A'),
                      '00000000-0000-0000-0000-00000000ff04'),
          'active',
          'Dan (placed grid ranking) stays active');

-- 5: Eve (skipped rating) NOT kicked.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official A'),
                      '00000000-0000-0000-0000-00000000ff05'),
          'active',
          'Eve (skipped rating) stays active');

-- 9: Alice (host, zero activity) NOT kicked.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official A'),
                      '00000000-0000-0000-0000-00000000ff01'),
          'active',
          'Host is never kicked, even with zero activity');

-- =============================================================================
-- Chat B: INVITE-ONLY (code) chat — host-moderated, no kicks should fire.
-- After 20260430140000 the kick scope is "access_method = 'public'", so
-- invite-only and personal-code chats are the new scope guard.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official, invite_code,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Invite-Only B', 'Q', 'code',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        FALSE, 'INVB01',
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Invite-Only B'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice', 'active', TRUE),
  ((SELECT id FROM chats WHERE name = 'KIF Invite-Only B'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob',   'active', FALSE);

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Invite-Only B'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Invite-Only B') AND completed_at IS NULL),
   1, 'rating', now() - interval '5 minutes');

-- Bob does nothing.
UPDATE rounds SET completed_at = now()
WHERE id = (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
            WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Invite-Only B')
              AND r.completed_at IS NULL);

-- 6: Bob still active — invite-only chat scope guard works.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Invite-Only B'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'active',
          'Inactive participant in INVITE-ONLY chat is NOT kicked');

-- =============================================================================
-- Chat C: OFFICIAL — carried-forward proposition does NOT save the user.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Official C', 'Q', 'public',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        TRUE,
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official C'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice', 'active', TRUE),
  ((SELECT id FROM chats WHERE name = 'KIF Official C'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob',   'active', FALSE);

INSERT INTO cycles (chat_id) VALUES ((SELECT id FROM chats WHERE name = 'KIF Official C'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Official C') AND completed_at IS NULL),
   1, 'proposing', now() - interval '3 minutes');

-- Source for FK
INSERT INTO propositions (round_id, participant_id, content)
SELECT r.id, NULL, 'Source for C'
FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official C')
  AND r.completed_at IS NULL;

-- Carried-forward (NULL participant, with carried_from_id)
INSERT INTO propositions (round_id, participant_id, carried_from_id, content)
SELECT r.id, NULL,
       (SELECT id FROM propositions WHERE content = 'Source for C'),
       'Carried C'
FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official C')
  AND r.completed_at IS NULL;

UPDATE rounds SET completed_at = now()
WHERE id = (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
            WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official C')
              AND r.completed_at IS NULL);

-- 7: Bob still kicked — carried prop doesn't count as Bob's action.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official C'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'kicked',
          'Carried-forward propositions do NOT save inactive participants');

-- =============================================================================
-- Chat D: OFFICIAL — mid-round joiner is NOT kicked.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Official D', 'Q', 'public',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        TRUE,
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official D'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice', 'active', TRUE);

INSERT INTO cycles (chat_id) VALUES ((SELECT id FROM chats WHERE name = 'KIF Official D'));
-- Round created BEFORE Bob joins.
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, created_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Official D') AND completed_at IS NULL),
   1, 'proposing', now() - interval '5 minutes', now() - interval '5 minutes');

-- Bob joins after round started.
INSERT INTO participants (chat_id, user_id, display_name, status, is_host, created_at) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official D'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob', 'active', FALSE,
   now() - interval '1 minute');

UPDATE rounds SET completed_at = now()
WHERE id = (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
            WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official D')
              AND r.completed_at IS NULL);

-- 8: Bob still active — joined after the round started.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official D'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'active',
          'Mid-round joiner is NOT kicked');

-- =============================================================================
-- Chat E: trigger only fires on completed_at NULL → non-NULL.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Official E', 'Q', 'public',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        TRUE,
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official E'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice', 'active', TRUE),
  ((SELECT id FROM chats WHERE name = 'KIF Official E'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob',   'active', FALSE);

INSERT INTO cycles (chat_id) VALUES ((SELECT id FROM chats WHERE name = 'KIF Official E'));
-- Insert a round that's ALREADY completed — trigger should not fire on insert,
-- and on subsequent updates (NULL→non-NULL guard) should not re-kick anyone.
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Official E') AND completed_at IS NULL),
   1, 'rating', now() - interval '5 minutes', now() - interval '4 minutes');

-- Touch completed_at again with a fresh value. Trigger must NOT re-fire
-- (already-completed rounds are skipped by the OLD/NEW guard).
UPDATE rounds SET completed_at = now()
WHERE cycle_id = (SELECT id FROM cycles WHERE chat_id =
                  (SELECT id FROM chats WHERE name = 'KIF Official E'));

-- 10: Bob still active — trigger never fired.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official E'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'active',
          'Trigger does not re-fire on subsequent completed_at updates');

-- =============================================================================
-- Chat F: round still in flight → no kicks.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Official F', 'Q', 'public',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        TRUE,
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official F'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice', 'active', TRUE),
  ((SELECT id FROM chats WHERE name = 'KIF Official F'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob',   'active', FALSE);

INSERT INTO cycles (chat_id) VALUES ((SELECT id FROM chats WHERE name = 'KIF Official F'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Official F') AND completed_at IS NULL),
   1, 'proposing', now());

-- 11: Round still in flight; Bob untouched.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official F'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'active',
          'No kick while the round is still in flight (completed_at IS NULL)');

-- =============================================================================
-- Chat G: a participant who already 'left' must NOT be flipped to 'kicked'.
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Official G', 'Q', 'public',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        TRUE,
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Official G'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice', 'active', TRUE),
  ((SELECT id FROM chats WHERE name = 'KIF Official G'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob',   'left',   FALSE);

INSERT INTO cycles (chat_id) VALUES ((SELECT id FROM chats WHERE name = 'KIF Official G'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Official G') AND completed_at IS NULL),
   1, 'rating', now() - interval '3 minutes');

UPDATE rounds SET completed_at = now()
WHERE id = (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
            WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Official G')
              AND r.completed_at IS NULL);

-- 12: Bob still 'left' — trigger only updates rows with status='active'.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Official G'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'left',
          'Already-left participant is not flipped to kicked');

-- =============================================================================
-- Chat H: NON-OFFICIAL PUBLIC chat — scope expansion. Inactive Bob
-- should now be kicked (was NOT kicked before 20260430140000).
-- =============================================================================
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   is_official,
                   proposing_threshold_count, rating_threshold_count)
VALUES ('KIF Public Non-Official H', 'Q', 'public',
        '00000000-0000-0000-0000-00000000ff01', 'manual',
        FALSE,
        NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status, is_host) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Public Non-Official H'),
   '00000000-0000-0000-0000-00000000ff01', 'Alice', 'active', TRUE),
  ((SELECT id FROM chats WHERE name = 'KIF Public Non-Official H'),
   '00000000-0000-0000-0000-00000000ff02', 'Bob',   'active', FALSE);

INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'KIF Public Non-Official H'));
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id =
      (SELECT id FROM chats WHERE name = 'KIF Public Non-Official H') AND completed_at IS NULL),
   1, 'rating', now() - interval '5 minutes');

-- Bob does nothing.
UPDATE rounds SET completed_at = now()
WHERE id = (SELECT r.id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
            WHERE cy.chat_id = (SELECT id FROM chats WHERE name = 'KIF Public Non-Official H')
              AND r.completed_at IS NULL);

-- 13: Bob kicked — non-official PUBLIC chats are now in scope.
SELECT is(_kif_status((SELECT id FROM chats WHERE name = 'KIF Public Non-Official H'),
                      '00000000-0000-0000-0000-00000000ff02'),
          'kicked',
          'Inactive participant in non-official PUBLIC chat IS kicked (scope expansion)');

SELECT * FROM finish();
ROLLBACK;
