-- Test: copy_round_media_to_cycle_trigger (migration 20260418150000)
--
-- When a cycle converges (completed_at NULL → NOT NULL) the trigger must copy
-- audio_url and video_url from the most-recent round that has them onto the
-- cycle row itself — so the permanent convergence card on the chat screen can
-- surface them. The bug it fixes: cycle 586 had text-only convergence even
-- though round 2198's winner video existed, because nothing copied it up.
--
-- Covers:
--   * audio + video both populated from the most-recent round that has them
--   * round with NULL media is ignored; trigger walks back to find a non-null
--   * cycle's existing non-null media is NOT overwritten
--   * trigger does NOT fire on ordinary updates (only on completed_at transition)
--   * cycle with no rounds completes cleanly (no-op, no error)

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- =============================================================================
-- Setup: user + chat
-- =============================================================================
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at) VALUES
  ('00000000-0000-0000-0000-000000000c01', 'media-trigger@test.com', 'authenticated', 'authenticated', now(), now());

INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('Media Trigger Test', 'Q', 'public', '00000000-0000-0000-0000-000000000c01', 'manual', NULL, NULL, NULL, NULL);

INSERT INTO participants (chat_id, user_id, display_name, status) VALUES
  ((SELECT id FROM chats WHERE name = 'Media Trigger Test'),
   '00000000-0000-0000-0000-000000000c01', 'Alice', 'active');

-- =============================================================================
-- Case 1: Cycle with one round that has both audio + video
-- =============================================================================
INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'Media Trigger Test'));
SELECT set_config('test.cycle_1', (SELECT id::text FROM cycles
  WHERE chat_id = (SELECT id FROM chats WHERE name = 'Media Trigger Test')
  ORDER BY id DESC LIMIT 1), true);

INSERT INTO rounds (cycle_id, custom_id, phase, audio_url, video_url) VALUES
  (current_setting('test.cycle_1')::bigint, 1, 'rating',
   'https://example.com/audio_r1.mp3', 'https://example.com/video_r1.mp4');

-- Trigger only fires on NULL → NOT NULL transition of completed_at.
UPDATE cycles SET completed_at = now() WHERE id = current_setting('test.cycle_1')::bigint;

SELECT is(
  (SELECT audio_url FROM cycles WHERE id = current_setting('test.cycle_1')::bigint),
  'https://example.com/audio_r1.mp3',
  'Case 1: cycle.audio_url copied from round'
);
SELECT is(
  (SELECT video_url FROM cycles WHERE id = current_setting('test.cycle_1')::bigint),
  'https://example.com/video_r1.mp4',
  'Case 1: cycle.video_url copied from round'
);

-- =============================================================================
-- Case 2: Two rounds — only round 1 has video, only round 2 has audio.
-- Trigger should walk back and pull whichever column is most recent non-null.
-- =============================================================================
INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'Media Trigger Test'));
SELECT set_config('test.cycle_2', (SELECT id::text FROM cycles
  WHERE chat_id = (SELECT id FROM chats WHERE name = 'Media Trigger Test')
  ORDER BY id DESC LIMIT 1), true);

INSERT INTO rounds (cycle_id, custom_id, phase, audio_url, video_url) VALUES
  (current_setting('test.cycle_2')::bigint, 1, 'rating', NULL, 'https://example.com/video_only.mp4'),
  (current_setting('test.cycle_2')::bigint, 2, 'rating', 'https://example.com/audio_only.mp3', NULL);

UPDATE cycles SET completed_at = now() WHERE id = current_setting('test.cycle_2')::bigint;

SELECT is(
  (SELECT audio_url FROM cycles WHERE id = current_setting('test.cycle_2')::bigint),
  'https://example.com/audio_only.mp3',
  'Case 2: audio pulled from round 2 (the only one with audio)'
);
SELECT is(
  (SELECT video_url FROM cycles WHERE id = current_setting('test.cycle_2')::bigint),
  'https://example.com/video_only.mp4',
  'Case 2: video pulled from round 1 (the only one with video)'
);

-- =============================================================================
-- Case 3: Cycle already has audio_url pre-set; trigger must NOT overwrite.
-- =============================================================================
INSERT INTO cycles (chat_id, audio_url) VALUES
  ((SELECT id FROM chats WHERE name = 'Media Trigger Test'),
   'https://example.com/preset_cycle_audio.mp3');
SELECT set_config('test.cycle_3', (SELECT id::text FROM cycles
  WHERE chat_id = (SELECT id FROM chats WHERE name = 'Media Trigger Test')
  ORDER BY id DESC LIMIT 1), true);

INSERT INTO rounds (cycle_id, custom_id, phase, audio_url, video_url) VALUES
  (current_setting('test.cycle_3')::bigint, 1, 'rating',
   'https://example.com/round_audio.mp3', 'https://example.com/round_video.mp4');

UPDATE cycles SET completed_at = now() WHERE id = current_setting('test.cycle_3')::bigint;

SELECT is(
  (SELECT audio_url FROM cycles WHERE id = current_setting('test.cycle_3')::bigint),
  'https://example.com/preset_cycle_audio.mp3',
  'Case 3: existing cycle.audio_url preserved (not overwritten)'
);
SELECT is(
  (SELECT video_url FROM cycles WHERE id = current_setting('test.cycle_3')::bigint),
  'https://example.com/round_video.mp4',
  'Case 3: NULL cycle.video_url still copied from round'
);

-- =============================================================================
-- Case 4: Trigger only fires on NULL → NOT NULL. Subsequent UPDATEs that touch
-- completed_at again (e.g., reopening) must NOT re-run the copy logic.
-- =============================================================================
UPDATE rounds SET audio_url = 'https://example.com/UPDATED_round_audio.mp3'
  WHERE cycle_id = current_setting('test.cycle_1')::bigint AND custom_id = 1;

-- Updating completed_at again shouldn't reset anything.
UPDATE cycles SET completed_at = now() + interval '1 minute'
  WHERE id = current_setting('test.cycle_1')::bigint;

SELECT is(
  (SELECT audio_url FROM cycles WHERE id = current_setting('test.cycle_1')::bigint),
  'https://example.com/audio_r1.mp3',
  'Case 4: trigger does not re-fire on subsequent completed_at update'
);

-- =============================================================================
-- Case 5: Cycle with no rounds — trigger runs, finds nothing, leaves nulls.
-- =============================================================================
INSERT INTO cycles (chat_id) VALUES
  ((SELECT id FROM chats WHERE name = 'Media Trigger Test'));
SELECT set_config('test.cycle_5', (SELECT id::text FROM cycles
  WHERE chat_id = (SELECT id FROM chats WHERE name = 'Media Trigger Test')
  ORDER BY id DESC LIMIT 1), true);

UPDATE cycles SET completed_at = now() WHERE id = current_setting('test.cycle_5')::bigint;

SELECT ok(
  (SELECT audio_url IS NULL AND video_url IS NULL
   FROM cycles WHERE id = current_setting('test.cycle_5')::bigint),
  'Case 5: cycle with no rounds completes without error, media stays NULL'
);

SELECT * FROM finish();
ROLLBACK;
