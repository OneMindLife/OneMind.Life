-- Test: Public chats RPCs now include dashboard data (phase/timer/pause)
-- Verifies current_round_phase, current_round_custom_id,
-- current_round_phase_ends_at, schedule_paused, and host_paused.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- Setup: Create test users
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000e01', 'pub-dash-host@test.com', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-000000000e02', 'pub-dash-viewer@test.com', 'authenticated', 'authenticated', now(), now());

-- Setup: Create a public chat with proposing round
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode)
VALUES ('Public Dash Chat', 'What should we discuss?', 'public', '00000000-0000-0000-0000-000000000e01', 'manual');

-- Add host as participant
INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'Public Dash Chat'), '00000000-0000-0000-0000-000000000e01', 'Host', 'active');

-- Create cycle + round in proposing phase
INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'Public Dash Chat'));

INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES
  ((SELECT id FROM cycles WHERE chat_id = (SELECT id FROM chats WHERE name = 'Public Dash Chat') AND completed_at IS NULL),
   1, 'proposing', now());

-- =============================================================================
-- Test 1: get_public_chats_translated returns current_round_phase = 'proposing'
-- (Viewer is not a participant, so chat shows up in public list)
-- =============================================================================
SELECT is(
  (SELECT current_round_phase FROM get_public_chats_translated(
    20, 0, '00000000-0000-0000-0000-000000000e02', 'en'
  ) WHERE name = 'Public Dash Chat'),
  'proposing',
  'get_public_chats_translated returns current_round_phase = proposing'
);

-- =============================================================================
-- Test 2: Returns correct current_round_custom_id (round number)
-- =============================================================================
SELECT is(
  (SELECT current_round_custom_id FROM get_public_chats_translated(
    20, 0, '00000000-0000-0000-0000-000000000e02', 'en'
  ) WHERE name = 'Public Dash Chat'),
  1,
  'get_public_chats_translated returns correct current_round_custom_id'
);

-- =============================================================================
-- Test 3: NULL phase_ends_at for manual mode (no timer)
-- =============================================================================
SELECT is(
  (SELECT current_round_phase_ends_at FROM get_public_chats_translated(
    20, 0, '00000000-0000-0000-0000-000000000e02', 'en'
  ) WHERE name = 'Public Dash Chat'),
  NULL::TIMESTAMPTZ,
  'Returns NULL phase_ends_at for manual mode round'
);

-- =============================================================================
-- Test 4: schedule_paused and host_paused default to false
-- =============================================================================
SELECT is(
  (SELECT schedule_paused FROM get_public_chats_translated(
    20, 0, '00000000-0000-0000-0000-000000000e02', 'en'
  ) WHERE name = 'Public Dash Chat'),
  false,
  'Returns schedule_paused = false by default'
);

SELECT is(
  (SELECT host_paused FROM get_public_chats_translated(
    20, 0, '00000000-0000-0000-0000-000000000e02', 'en'
  ) WHERE name = 'Public Dash Chat'),
  false,
  'Returns host_paused = false by default'
);

-- Setup: Create a second chat with NO active cycle/round
INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode)
VALUES ('Idle Public Chat', 'An idle chat', 'public', '00000000-0000-0000-0000-000000000e01', 'manual');

-- =============================================================================
-- Test 5: No active cycle → current_round_phase IS NULL
-- =============================================================================
SELECT is(
  (SELECT current_round_phase FROM get_public_chats_translated(
    20, 0, '00000000-0000-0000-0000-000000000e02', 'en'
  ) WHERE name = 'Idle Public Chat'),
  NULL::TEXT,
  'Returns NULL current_round_phase when no active cycle/round'
);

-- Add timer to existing round
UPDATE rounds SET
  phase_ends_at = now() + interval '5 minutes'
WHERE cycle_id = (
  SELECT id FROM cycles
  WHERE chat_id = (SELECT id FROM chats WHERE name = 'Public Dash Chat')
    AND completed_at IS NULL
) AND completed_at IS NULL;

-- =============================================================================
-- Test 6: phase_ends_at for timed round
-- =============================================================================
SELECT isnt(
  (SELECT current_round_phase_ends_at FROM get_public_chats_translated(
    20, 0, '00000000-0000-0000-0000-000000000e02', 'en'
  ) WHERE name = 'Public Dash Chat'),
  NULL::TIMESTAMPTZ,
  'Returns non-NULL phase_ends_at for timed round'
);

-- =============================================================================
-- Test 7: get_public_chats (non-translated) also returns phase data
-- =============================================================================
SELECT is(
  (SELECT current_round_phase FROM get_public_chats(
    20, 0, '00000000-0000-0000-0000-000000000e02'
  ) WHERE name = 'Public Dash Chat'),
  'proposing',
  'get_public_chats also returns current_round_phase'
);

SELECT * FROM finish();
ROLLBACK;
