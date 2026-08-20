-- =============================================================================
-- Test: inactive-participant auto-kick was REMOVED (Joel, retired 2026-07-16).
--
-- This file used to verify a trigger that kicked inactive participants from
-- official/public chats at round completion. That trigger was intentionally
-- dropped in 20260709190000_drop_kick_inactive_from_official.sql: on the
-- always-running global chat (2-min matches loop) its participation check only
-- read grid_rankings, so it missed matches-mode votes and kicked ~2,074 of
-- ~2,100 lurking/voting humans — catastrophic for a high-churn anonymous room.
--
-- The old behavioural tests are gone (there is nothing left to kick). What
-- remains is a regression guard: the trigger and its function must STAY removed,
-- so nobody accidentally reintroduces the mass-kick on a live public room.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(2);

SELECT is(
  (SELECT count(*)::int FROM pg_trigger WHERE tgname = 'trg_kick_inactive_from_official'),
  0,
  'inactive-kick trigger stays dropped (20260709190000) — no auto-kick on any chat'
);

SELECT is(
  (SELECT count(*)::int FROM pg_proc
     WHERE proname = 'kick_inactive_from_official_on_round_completion'),
  0,
  'inactive-kick function stays dropped — mass-kick cannot be reintroduced'
);

SELECT * FROM finish();
ROLLBACK;
