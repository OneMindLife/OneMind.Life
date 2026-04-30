-- Pull the conservative DB defaults toward saner values that better
-- match how chats are actually created today. The "API-safe" defaults
-- from the original schema were so different from the wizard's that
-- a host scripting a chat via direct SQL would get a wildly different
-- experience (24-hour phases, manual start, no early advance, hidden
-- previous-round results) than a host going through the UI.
--
-- Six changes, all column-default changes only — existing rows are
-- not affected:
--
-- 1. auto_start_participant_count: 5 → 3
--    The constraint floor is 3 (chats_auto_start_participant_count_min_check,
--    added 20260113060000) and the create-chat wizard always sends 3.
--
-- 2. proposing_duration_seconds: 86400 (24h) → 43200 (12h)
-- 3. rating_duration_seconds:    86400 (24h) → 43200 (12h)
--    Original 24h was "leisurely deliberation." 12h fits a
--    "morning + afternoon" cadence and matches the OneMind-chat
--    config that's been running for weeks. Wizard 60s presets
--    unchanged.
--
-- 4. proposing_threshold_percent: NULL → 100
-- 5. rating_threshold_percent:    NULL → 100
--    NULL meant "percent-based auto-advance disabled." 100% means
--    "advance as soon as everyone has acted" — the wizard already
--    sends 100. Aligning the DB default makes API-created chats
--    auto-advance like wizard-created ones.
--
-- 6. show_previous_results: false → true
--    DB default of false hid the previous round's full ratings from
--    participants — strange for a transparency-first product. Wizard
--    already sends true. Aligning closes the gap.

ALTER TABLE chats
ALTER COLUMN auto_start_participant_count SET DEFAULT 3;

ALTER TABLE chats
ALTER COLUMN proposing_duration_seconds SET DEFAULT 43200;

ALTER TABLE chats
ALTER COLUMN rating_duration_seconds SET DEFAULT 43200;

ALTER TABLE chats
ALTER COLUMN proposing_threshold_percent SET DEFAULT 100;

ALTER TABLE chats
ALTER COLUMN rating_threshold_percent SET DEFAULT 100;

ALTER TABLE chats
ALTER COLUMN show_previous_results SET DEFAULT true;

COMMENT ON COLUMN chats.auto_start_participant_count IS
'Minimum participants to auto-start first round. Must be >= 3 because: '
'(1) proposing_minimum is 3, (2) rating requires 2+ propositions from '
'OTHER users to rank. Default now matches the constraint floor (was 5 '
'before 20260430160000).';

COMMENT ON COLUMN chats.proposing_duration_seconds IS
'Length of the proposing phase in seconds. Default 12 hours (43200) '
'as of 20260430160000. Wizard tunes per-create (default 60s). Hard '
'floor is 60s (chats_proposing_duration_seconds_check).';

COMMENT ON COLUMN chats.rating_duration_seconds IS
'Length of the rating phase in seconds. Default 12 hours (43200) as '
'of 20260430160000. Wizard tunes per-create (default 60s).';

COMMENT ON COLUMN chats.proposing_threshold_percent IS
'Percent of participants who must act before proposing auto-advances. '
'Default 100 as of 20260430160000 (was NULL = disabled). Combined '
'with proposing_threshold_count via MAX logic.';

COMMENT ON COLUMN chats.rating_threshold_percent IS
'Percent of eligible raters who must rate each proposition before '
'rating auto-advances. Default 100 as of 20260430160000 (was NULL = '
'disabled). Combined with rating_threshold_count via MAX logic.';

COMMENT ON COLUMN chats.show_previous_results IS
'Whether previous round''s full rating results are shown to '
'participants. Default true as of 20260430160000 (was false). '
'Transparency-first.';
