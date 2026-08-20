-- =============================================================================
-- Test: opinion watches — new-reply cache + triggers (2026-07-16).
-- Migrations: 20260716170032_opinion_watches.sql
--             20260716173222_auto_watch_own_opinion.sql
--             20260716173545_watches_new_opinions_not_matches.sql
--   • sync_watch_on_opinion: a new child opinion bumps every watcher of the
--     parent's new_count EXCEPT the author (your own reply isn't "new" to you).
--   • mark_watch_seen resets new_count to 0.
--   • auto_watch_own_opinion: posting in a repository chat auto-watches your own
--     opinion (new_count starts 0).
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(5);

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode, never_seals)
VALUES ('Watch Test', 'Q', gen_random_uuid(), 'matches', true);

-- Real participants always carry user_id (= auth.uid()), and
-- auto_watch_own_opinion bails when it's NULL — so the fixture needs real rows.
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-0000000e4601'::uuid, 'watch-authorp@test.com',  'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000e4602'::uuid, 'watch-watcher@test.com',  'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000e4603'::uuid, 'watch-a1@test.com',       'authenticated', 'authenticated', now(), now());
INSERT INTO public.users (id) VALUES
  ('00000000-0000-0000-0000-0000000e4601'::uuid),
  ('00000000-0000-0000-0000-0000000e4602'::uuid),
  ('00000000-0000-0000-0000-0000000e4603'::uuid)
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_chat int; v_root_cy int; v_root_r int;
  authorP int; watcherW int; a1 int;
  pP int; v_child_cy int; v_child_r int;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Watch Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_root_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_root_cy, 1, 'rating') RETURNING id INTO v_root_r;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, status) VALUES (v_chat, gen_random_uuid(), '00000000-0000-0000-0000-0000000e4601'::uuid, 'AuthorP', 'active') RETURNING id INTO authorP;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, status) VALUES (v_chat, gen_random_uuid(), '00000000-0000-0000-0000-0000000e4602'::uuid, 'Watcher', 'active') RETURNING id INTO watcherW;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, status) VALUES (v_chat, gen_random_uuid(), '00000000-0000-0000-0000-0000000e4603'::uuid, 'A1', 'active') RETURNING id INTO a1;

  -- The watched opinion P (root round) + its (empty) child thread.
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_root_r, authorP, 'P') RETURNING id INTO pP;
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (v_chat, pP) RETURNING id INTO v_child_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_child_cy, 1, 'rating') RETURNING id INTO v_child_r;

  -- Watcher watches P from now on → starts at 0 unseen.
  INSERT INTO opinion_watches (participant_id, proposition_id, user_id, new_count)
  VALUES (watcherW, pP, gen_random_uuid(), 0);

  PERFORM set_config('t.watcher', watcherW::text, false);
  PERFORM set_config('t.pP',      pP::text,       false);
  PERFORM set_config('t.child_r', v_child_r::text,false);
  PERFORM set_config('t.a1',      a1::text,       false);
END $$;

-- 1. Fresh watch: nothing new yet.
SELECT is(
  (SELECT new_count FROM opinion_watches WHERE participant_id = current_setting('t.watcher')::bigint AND proposition_id = current_setting('t.pP')::bigint),
  0, 'a fresh watch starts with 0 new replies'
);

-- 2. Two replies by another participant → new_count = 2.
INSERT INTO propositions (round_id, participant_id, content) VALUES (current_setting('t.child_r')::bigint, current_setting('t.a1')::bigint, 'r1');
INSERT INTO propositions (round_id, participant_id, content) VALUES (current_setting('t.child_r')::bigint, current_setting('t.a1')::bigint, 'r2');
SELECT is(
  (SELECT new_count FROM opinion_watches WHERE participant_id = current_setting('t.watcher')::bigint AND proposition_id = current_setting('t.pP')::bigint),
  2, 'each new reply bumps the watcher''s new_count'
);

-- 3. The watcher's OWN reply must not count as new for them.
INSERT INTO propositions (round_id, participant_id, content) VALUES (current_setting('t.child_r')::bigint, current_setting('t.watcher')::bigint, 'my own reply');
SELECT is(
  (SELECT new_count FROM opinion_watches WHERE participant_id = current_setting('t.watcher')::bigint AND proposition_id = current_setting('t.pP')::bigint),
  2, 'the watcher''s own reply does not bump their own new_count'
);

-- 4. Viewing the thread resets it.
SELECT mark_watch_seen(current_setting('t.watcher')::bigint, current_setting('t.pP')::bigint);
SELECT is(
  (SELECT new_count FROM opinion_watches WHERE participant_id = current_setting('t.watcher')::bigint AND proposition_id = current_setting('t.pP')::bigint),
  0, 'mark_watch_seen resets new_count to 0'
);

-- 5. Auto-watch: posting a new opinion in a repository chat watches it (0 unseen).
DO $$
DECLARE v_newp int;
BEGIN
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (current_setting('t.child_r')::bigint, current_setting('t.a1')::bigint, 'a1 own post')
  RETURNING id INTO v_newp;
  PERFORM set_config('t.newp', v_newp::text, false);
END $$;
SELECT is(
  (SELECT new_count FROM opinion_watches WHERE participant_id = current_setting('t.a1')::bigint AND proposition_id = current_setting('t.newp')::bigint),
  0, 'auto-watch: your own new opinion is watched, starting at 0 new'
);

SELECT * FROM finish();
ROLLBACK;
