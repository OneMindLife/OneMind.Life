-- Test: get_my_chats_dashboard RPC
-- Verifies participant_count, current_round_phase, current_round_custom_id,
-- phase_ends_at, and NULL cases for the home screen dashboard.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(7);

-- Setup: Create test users
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000f01', 'dash-host@test.com', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000f02', 'dash-user2@test.com', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000f03', 'dash-user3@test.com', 'authenticated', 'authenticated', now(), now());

-- Setup: Create a chat (manual mode = no timers)
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode)
VALUES ('Dashboard Test Chat', 'Test question', 'public', '00000000-0000-0000-0000-000000000f01', 'manual');

-- Setup: Add 3 participants
INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'Dashboard Test Chat'), '00000000-0000-0000-0000-000000000f01', 'Host', 'active'),
  ((SELECT id FROM chats WHERE name = 'Dashboard Test Chat'), '00000000-0000-0000-0000-000000000f02', 'User2', 'active'),
  ((SELECT id FROM chats WHERE name = 'Dashboard Test Chat'), '00000000-0000-0000-0000-000000000f03', 'User3', 'active');

-- =============================================================================
-- Test 1: Correct participant_count
-- =============================================================================
SELECT is(
  (SELECT participant_count FROM get_my_chats_dashboard(
    '00000000-0000-0000-0000-000000000f01', 'en'
  ) WHERE name = 'Dashboard Test Chat'),
  3::BIGINT,
  'Returns correct participant_count for chat with 3 participants'
);

-- =============================================================================
-- Test 2: No active cycle/round → current_round_phase IS NULL
-- =============================================================================
SELECT is(
  (SELECT current_round_phase FROM get_my_chats_dashboard(
    '00000000-0000-0000-0000-000000000f01', 'en'
  ) WHERE name = 'Dashboard Test Chat'),
  NULL::TEXT,
  'Returns NULL current_round_phase when no active cycle/round'
);

-- Setup: Create a cycle and a round in proposing phase
INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'Dashboard Test Chat'));

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id = (SELECT id FROM chats WHERE name = 'Dashboard Test Chat') AND completed_at IS NULL),
   1, 'proposing', now());

-- =============================================================================
-- Test 3: Active round in proposing phase
-- =============================================================================
SELECT is(
  (SELECT current_round_phase FROM get_my_chats_dashboard(
    '00000000-0000-0000-0000-000000000f01', 'en'
  ) WHERE name = 'Dashboard Test Chat'),
  'proposing',
  'Returns current_round_phase = proposing when round is in proposing'
);

-- =============================================================================
-- Test 4: Correct current_round_custom_id (round number)
-- =============================================================================
SELECT is(
  (SELECT current_round_custom_id FROM get_my_chats_dashboard(
    '00000000-0000-0000-0000-000000000f01', 'en'
  ) WHERE name = 'Dashboard Test Chat'),
  1,
  'Returns correct current_round_custom_id (round number 1)'
);

-- =============================================================================
-- Test 5: NULL phase_ends_at for manual mode (no timer)
-- =============================================================================
SELECT is(
  (SELECT current_round_phase_ends_at FROM get_my_chats_dashboard(
    '00000000-0000-0000-0000-000000000f01', 'en'
  ) WHERE name = 'Dashboard Test Chat'),
  NULL::TIMESTAMPTZ,
  'Returns NULL phase_ends_at for manual mode round'
);

-- Move round to rating phase with a timer
UPDATE rounds SET
  phase = 'rating',
  phase_started_at = now(),
  phase_ends_at = now() + interval '5 minutes'
WHERE cycle_id = (
  SELECT id FROM cycles
  WHERE chat_id = (SELECT id FROM chats WHERE name = 'Dashboard Test Chat')
    AND completed_at IS NULL
) AND completed_at IS NULL;

-- =============================================================================
-- Test 6: Active round in rating phase
-- =============================================================================
SELECT is(
  (SELECT current_round_phase FROM get_my_chats_dashboard(
    '00000000-0000-0000-0000-000000000f01', 'en'
  ) WHERE name = 'Dashboard Test Chat'),
  'rating',
  'Returns current_round_phase = rating when round is in rating'
);

-- =============================================================================
-- Test 7: phase_ends_at for timed round
-- =============================================================================
SELECT isnt(
  (SELECT current_round_phase_ends_at FROM get_my_chats_dashboard(
    '00000000-0000-0000-0000-000000000f01', 'en'
  ) WHERE name = 'Dashboard Test Chat'),
  NULL::TIMESTAMPTZ,
  'Returns non-NULL phase_ends_at for timed round'
);

SELECT * FROM finish();
ROLLBACK;
