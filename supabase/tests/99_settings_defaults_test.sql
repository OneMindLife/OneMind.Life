-- Verifies the DB defaults documented in docs/SETTINGS_REFERENCE.md.
--
-- Inserts a chat with ONLY required columns set, then asserts every
-- other column resolves to the documented default. Catches drift
-- between docs and DB.
--
-- If a documented default changes, the test should be updated together
-- with the doc — they're paired on purpose.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(36);

-- Insert with the absolute minimum columns. Everything else falls back
-- to the column DEFAULT defined in the schema. Capture the new id in a
-- session-local config setting so subsequent assertions can reference it.
DO $$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token)
  VALUES ('SETTINGS DEFAULTS TEST', 'Q', gen_random_uuid())
  RETURNING id INTO v_id;
  PERFORM set_config('test.chat_id', v_id::text, true);
END $$;

-- ============================================================
-- Identity / lifecycle
-- ============================================================

SELECT is(
  (SELECT initial_message FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  'Q'::text,
  'initial_message accepts the inserted value'
);

SELECT is(
  (SELECT description FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  NULL::text,
  'description default is NULL'
);

SELECT is(
  (SELECT access_method FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  'public'::text,
  'access_method default is public'
);

SELECT is(
  (SELECT require_auth FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'require_auth default is false'
);

SELECT is(
  (SELECT require_approval FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'require_approval default is false'
);

SELECT is(
  (SELECT is_active FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  true,
  'is_active default is true'
);

SELECT is(
  (SELECT is_official FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'is_official default is false'
);

-- The COLUMN default is FALSE, but a BEFORE INSERT trigger
-- (apply_anonymous_host_rules from 20260110060000) flips it to TRUE
-- whenever creator_id IS NULL and creator_session_token IS NOT NULL —
-- which is what our test insert does. So the post-insert value is TRUE.
-- Documented in docs/SETTINGS_REFERENCE.md.
SELECT is(
  (SELECT host_was_anonymous FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  true,
  'host_was_anonymous resolves to true for anonymous-creator inserts (trigger override)'
);

-- ============================================================
-- Phase pacing
-- ============================================================

SELECT is(
  (SELECT start_mode FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  'manual'::text,
  'start_mode DB default is manual (wizard overrides to auto)'
);

SELECT is(
  (SELECT rating_start_mode FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  'auto'::text,
  'rating_start_mode default is auto'
);

SELECT is(
  (SELECT auto_start_participant_count FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  3,
  'auto_start_participant_count default is 3 (matches wizard + constraint floor)'
);

SELECT is(
  (SELECT proposing_duration_seconds FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  43200,
  'proposing_duration_seconds default is 43200 (12h; wizard overrides to 60s for demos)'
);

SELECT is(
  (SELECT rating_duration_seconds FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  43200,
  'rating_duration_seconds default is 43200 (12h; wizard overrides to 60s for demos)'
);

-- ============================================================
-- Phase minimums
-- ============================================================

SELECT is(
  (SELECT proposing_minimum FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  3,
  'proposing_minimum default is 3'
);

SELECT is(
  (SELECT rating_minimum FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  2,
  'rating_minimum default is 2'
);

SELECT is(
  (SELECT propositions_per_user FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  1,
  'propositions_per_user default is 1'
);

-- ============================================================
-- Auto-advance thresholds
-- ============================================================

SELECT is(
  (SELECT proposing_threshold_percent FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  100,
  'proposing_threshold_percent default is 100 (matches wizard; advances when all act)'
);

SELECT is(
  (SELECT proposing_threshold_count FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  3,
  'proposing_threshold_count default is 3'
);

SELECT is(
  (SELECT rating_threshold_percent FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  100,
  'rating_threshold_percent default is 100 (matches wizard; advances when all eligible rate)'
);

SELECT is(
  (SELECT rating_threshold_count FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  2,
  'rating_threshold_count default is 2'
);

-- ============================================================
-- Adaptive duration
-- ============================================================

SELECT is(
  (SELECT adaptive_duration_enabled FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'adaptive_duration_enabled default is false'
);

SELECT is(
  (SELECT adaptive_adjustment_percent FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  10,
  'adaptive_adjustment_percent default is 10'
);

SELECT is(
  (SELECT min_phase_duration_seconds FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  60,
  'min_phase_duration_seconds default is 60'
);

SELECT is(
  (SELECT max_phase_duration_seconds FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  86400,
  'max_phase_duration_seconds default is 86400 (24h)'
);

-- ============================================================
-- Consensus
-- ============================================================

SELECT is(
  (SELECT confirmation_rounds_required FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  2,
  'confirmation_rounds_required default is 2'
);

SELECT is(
  (SELECT show_previous_results FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  true,
  'show_previous_results default is true (transparency-first)'
);

-- ============================================================
-- Pause flags
-- ============================================================

SELECT is(
  (SELECT host_paused FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'host_paused default is false'
);

SELECT is(
  (SELECT schedule_paused FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'schedule_paused default is false'
);

-- ============================================================
-- Skip toggles (NOT NULL with default true per migration 20260415100000)
-- ============================================================

SELECT is(
  (SELECT allow_skip_proposing FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  true,
  'allow_skip_proposing default is true'
);

SELECT is(
  (SELECT allow_skip_rating FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  true,
  'allow_skip_rating default is true'
);

-- ============================================================
-- Agents
-- ============================================================

SELECT is(
  (SELECT enable_agents FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'enable_agents default is false'
);

SELECT is(
  (SELECT proposing_agent_count FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  3,
  'proposing_agent_count default is 3'
);

SELECT is(
  (SELECT rating_agent_count FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  0,
  'rating_agent_count default is 0'
);

-- ============================================================
-- Translations
-- ============================================================

SELECT is(
  (SELECT translations_enabled FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  false,
  'translations_enabled default is false'
);

-- ============================================================
-- Schedule
-- ============================================================

SELECT is(
  (SELECT schedule_timezone FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  'UTC'::text,
  'schedule_timezone default is UTC'
);

SELECT is(
  (SELECT visible_outside_schedule FROM chats WHERE id = current_setting('test.chat_id')::bigint),
  true,
  'visible_outside_schedule default is true'
);

SELECT * FROM finish();
ROLLBACK;
