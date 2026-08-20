-- =============================================================================
-- Test: root watches — the chat-level "watch new top-level opinions" (2026-07-18).
-- Migration: 20260718020000_root_watches.sql
--   • Default ON: with no row, watching=true and new_count counts top-level
--     opinions created after the participant joined.
--   • Only NEW (not carried), not-your-own root opinions count.
--   • mark_root_seen resets the badge; set_root_watch mutes/un-mutes.
--
-- NOTE: now() is frozen inside a transaction, so the fixture sets created_at
-- explicitly — join in the past, opinions after it — or the "created after last
-- seen" comparison would see everything as simultaneous. The RPCs gate on
-- auth.uid(), so we set request.jwt.claims to the watcher's user_id.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

SELECT has_table('public', 'root_watches', 'root_watches table exists');
SELECT has_function('public', 'get_root_watch_state', ARRAY['bigint'], 'state RPC exists');
SELECT has_function('public', 'set_root_watch', ARRAY['bigint','boolean'], 'toggle RPC exists');
SELECT has_function('public', 'mark_root_seen', ARRAY['bigint'], 'mark-seen RPC exists');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode, never_seals)
VALUES ('Root Watch Test', 'Q', gen_random_uuid(), 'matches', true);

DO $$
DECLARE
  v_chat int; v_root_cy int; v_root_r int;
  watcherW int; otherA int;
  v_uid uuid := '11111111-1111-1111-1111-111111111111';
  v_root_prop int;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Root Watch Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_root_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_root_cy, 1, 'rating') RETURNING id INTO v_root_r;

  -- The watcher joined an hour ago; auth.uid() will be their user_id.
  -- participants.user_id → users.id → auth.users.id; trg_auth_user_created
  -- mirrors auth.users into public.users, so seeding auth.users suffices.
  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES (v_uid, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid)
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO participants (chat_id, session_token, display_name, status, user_id, created_at)
  VALUES (v_chat, gen_random_uuid(), 'Watcher', 'active', v_uid, now() - interval '1 hour')
  RETURNING id INTO watcherW;
  INSERT INTO participants (chat_id, session_token, display_name, status)
  VALUES (v_chat, gen_random_uuid(), 'Other', 'active') RETURNING id INTO otherA;

  -- Two top-level opinions by SOMEONE ELSE, after the watcher joined → both new.
  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_root_r, otherA, 'other opinion 1', now() - interval '30 min');
  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_root_r, otherA, 'other opinion 2', now() - interval '25 min');
  -- The watcher's OWN top-level opinion → must not count as new for them.
  INSERT INTO propositions (round_id, participant_id, content, created_at)
  VALUES (v_root_r, watcherW, 'my own opinion', now() - interval '20 min')
  RETURNING id INTO v_root_prop;
  -- A carried-forward top-level opinion → must not count either. Inserted here
  -- (pre-auth) so the per-user proposition limit — enforced once auth.uid() is
  -- set — doesn't block it.
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id, created_at)
  VALUES (v_root_r, otherA, 'carried', v_root_prop, now() - interval '10 min');

  PERFORM set_config('t.watcher', watcherW::text, false);
  PERFORM set_config('t.root_r', v_root_r::text, false);
  PERFORM set_config('t.other', otherA::text, false);
  PERFORM set_config('t.uid', v_uid::text, false);
  PERFORM set_config('t.root_prop', v_root_prop::text, false);
END $$;

-- Act as the watcher for the auth.uid()-gated RPCs.
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('t.uid'), 'role', 'authenticated')::text, true);

-- 5-6. Default (no row): watching, and exactly 2 new top-level opinions — the
-- watcher's own opinion and the carried-forward one are both excluded.
SELECT is(
  (SELECT watching FROM get_root_watch_state(current_setting('t.watcher')::bigint)),
  true, 'root watch is ON by default (no row = watching)'
);
SELECT is(
  (SELECT new_count FROM get_root_watch_state(current_setting('t.watcher')::bigint)),
  2, 'new_count counts others'' NEW top-level opinions; own + carried excluded'
);

-- 7-8. Muting hides the unseen: watching=false and new_count forced to 0 even
-- though 2 unseen opinions exist.
SELECT set_root_watch(current_setting('t.watcher')::bigint, false);
SELECT is(
  (SELECT watching FROM get_root_watch_state(current_setting('t.watcher')::bigint)),
  false, 'set_root_watch(false) mutes the root watch'
);
SELECT is(
  (SELECT new_count FROM get_root_watch_state(current_setting('t.watcher')::bigint)),
  0, 'a muted root watch reports new_count 0 despite unseen opinions'
);

-- 9. Un-muting restores watching AND the still-unseen count.
SELECT set_root_watch(current_setting('t.watcher')::bigint, true);
SELECT is(
  (SELECT new_count FROM get_root_watch_state(current_setting('t.watcher')::bigint)),
  2, 'un-muting restores watching and the unseen count'
);

-- 10. Viewing root resets the badge.
SELECT mark_root_seen(current_setting('t.watcher')::bigint);
SELECT is(
  (SELECT new_count FROM get_root_watch_state(current_setting('t.watcher')::bigint)),
  0, 'mark_root_seen resets new_count to 0'
);

SELECT set_config('request.jwt.claims', '', true);
SELECT * FROM finish();
ROLLBACK;
