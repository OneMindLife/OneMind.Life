-- =============================================================================
-- Regression: on_proposition_update_activity + on_rating_update_activity
-- must update chats.last_activity_at when fired by a NON-HOST participant.
-- =============================================================================
-- Migration: 20260502160000_fix_activity_triggers_rls.sql
--
-- The bug: chats UPDATE policy is host-only, so the trigger's
-- `UPDATE chats SET last_activity_at = NOW()` was silently filtered to
-- zero rows when the calling user wasn't the host. Fix is SECURITY
-- DEFINER. pgtap normally runs as postgres (BYPASSRLS) so any test that
-- doesn't deliberately switch role + supply a JWT will pass even when
-- the trigger is broken — see test 105 for the same pattern in the L1
-- denorm trigger.
--
-- Coverage:
--   1. Non-host participant submits a proposition → chats.last_activity_at
--      moves forward (this fails on the pre-fix non-DEFINER trigger).
--   2. Non-host participant submits a rating (legacy ratings table) →
--      chats.last_activity_at moves forward.
--   3. Anonymous chat: non-host proposition extends expires_at by 7 days
--      from NOW (the 7-day rolling expiry only kicks in for chats whose
--      creator is anonymous: creator_session_token NOT NULL AND
--      creator_id IS NULL).
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

-- =============================================================================
-- SETUP
-- =============================================================================
DO $$
DECLARE
  v_host_uid    UUID := '00000000-0000-0000-0000-0000000a0001';
  v_other_uid   UUID := '00000000-0000-0000-0000-0000000a0002';
  v_chat_id     INT;
  v_cycle_id    INT;
  v_round_id    INT;
  v_host_part   INT;
  v_other_part  INT;
  v_other_prop  INT;
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES
    (v_host_uid,  'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_other_uid, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
  ON CONFLICT (id) DO NOTHING;

  -- Anonymous-creator chat (creator_session_token NOT NULL, creator_id NULL)
  -- so the expires_at extension branch fires. Seed last_activity_at to
  -- one hour ago — within a single transaction NOW() returns the txn-
  -- start timestamp, so without an explicitly-stale seed the trigger's
  -- `last_activity_at = NOW()` would equal the chat's freshly-defaulted
  -- `last_activity_at = NOW()` and our delta check would always return
  -- zero (false negative even when the fix works).
  INSERT INTO chats (
    name, initial_message, creator_session_token, creator_id,
    last_activity_at, expires_at
  ) VALUES (
    'Activity Trigger Test', 'Test',
    gen_random_uuid(), NULL,
    NOW() - INTERVAL '1 hour',
    NOW() + INTERVAL '1 day'
  ) RETURNING id INTO v_chat_id;

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;

  -- Host participant
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_host_uid, 'Host', TRUE, 'active')
    RETURNING id INTO v_host_part;

  -- Non-host participant (the actor for the regression check)
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_other_uid, 'Other', FALSE, 'active')
    RETURNING id INTO v_other_part;

  -- A pre-existing proposition we can rate against in test 2
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_part, 'Existing prop') RETURNING id INTO v_other_prop;

  PERFORM set_config('test.act.chat_id',    v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.act.round_id',   v_round_id::TEXT, TRUE);
  PERFORM set_config('test.act.host_part',  v_host_part::TEXT, TRUE);
  PERFORM set_config('test.act.other_part', v_other_part::TEXT, TRUE);
  PERFORM set_config('test.act.other_prop', v_other_prop::TEXT, TRUE);
  PERFORM set_config('test.act.other_uid',  v_other_uid::TEXT, TRUE);

  -- Stomp last_activity_at to one hour in the past AFTER all the setup
  -- inserts have run (the participants INSERTs fire
  -- check_auto_start_on_participant_join, which is SECURITY DEFINER and
  -- writes last_activity_at = NOW(), overwriting any value we set in
  -- the chats INSERT). Same for expires_at — host_resume / auto-start
  -- chains push it forward. We do this with role-elevated postgres so
  -- it's never blocked, then snapshot t0 right before flipping role to
  -- authenticated for the actual test action.
  UPDATE chats
  SET last_activity_at = NOW() - INTERVAL '1 hour',
      expires_at = NOW() + INTERVAL '1 day'
  WHERE id = v_chat_id;

  PERFORM set_config('test.act.t0_lat',
    (SELECT last_activity_at::TEXT FROM chats WHERE id = v_chat_id), TRUE);
  PERFORM set_config('test.act.t0_exp',
    (SELECT expires_at::TEXT FROM chats WHERE id = v_chat_id), TRUE);
END $$;

-- =============================================================================
-- 1. Non-host proposition INSERT advances last_activity_at
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object(
    'sub', current_setting('test.act.other_uid'),
    'role', 'authenticated'
  )::TEXT, TRUE);

INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.act.round_id')::INT,
        current_setting('test.act.other_part')::INT,
        'Other''s proposition');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT ok(
  (SELECT last_activity_at FROM chats WHERE id = current_setting('test.act.chat_id')::INT)
    > current_setting('test.act.t0_lat')::TIMESTAMPTZ,
  '1: non-host proposition INSERT advances chats.last_activity_at (was silently a no-op without SECURITY DEFINER)'
);

-- =============================================================================
-- 2. Non-host rating INSERT advances last_activity_at
-- =============================================================================
-- Stomp last_activity_at to the past again — test 1 advanced it to
-- NOW() (txn-start), and the trigger we're about to fire will also set
-- it to NOW() (same value, same txn). Without this, the comparison
-- always returns false even when the trigger works.
UPDATE chats SET last_activity_at = NOW() - INTERVAL '1 hour'
WHERE id = current_setting('test.act.chat_id')::INT;
SELECT set_config('test.act.t1_lat',
  (SELECT last_activity_at::TEXT FROM chats
    WHERE id = current_setting('test.act.chat_id')::INT), TRUE);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object(
    'sub', current_setting('test.act.other_uid'),
    'role', 'authenticated'
  )::TEXT, TRUE);

-- The legacy `ratings` table is what on_rating_update_activity is wired to.
-- It still exists in the schema even if the live app uses grid_rankings.
INSERT INTO ratings (proposition_id, participant_id, rating)
VALUES (current_setting('test.act.other_prop')::INT,
        current_setting('test.act.other_part')::INT,
        80);

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT ok(
  (SELECT last_activity_at FROM chats WHERE id = current_setting('test.act.chat_id')::INT)
    > current_setting('test.act.t1_lat')::TIMESTAMPTZ,
  '2: non-host ratings INSERT advances chats.last_activity_at'
);

-- =============================================================================
-- 3. Anonymous-creator chat: expires_at extends to NOW + 7 days when a
-- non-host action fires the activity trigger. (We seeded expires_at to
-- NOW + 1 day, so the new value should be roughly 6 days into the future.)
-- =============================================================================
SELECT ok(
  (SELECT expires_at FROM chats WHERE id = current_setting('test.act.chat_id')::INT)
    > NOW() + INTERVAL '5 days',
  '3: non-host action extends expires_at to ~NOW + 7 days for anonymous chat'
);

SELECT * FROM finish();
ROLLBACK;
