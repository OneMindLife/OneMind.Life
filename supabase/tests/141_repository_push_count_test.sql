-- =============================================================================
-- Test: repository push count (Joel, 2026-07-15).
-- Migration: 20260715085858_repository_push_root_only_chatwide_count.sql
--   get_chat_new_opinion_count: human, non-carried opinions added CHAT-WIDE
--   (across all rounds) since a cutoff. Excludes AI, carried-forward, opinions
--   older than the cutoff, and other chats.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

SELECT has_function('get_chat_new_opinion_count', 'RPC exists');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Push Count X', 'Q', gen_random_uuid(), 'matches'),
       ('Push Count Y', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE
  cx INT; cy INT; cyc1 INT; cyc2 INT; r1 INT; r2 INT; author INT; ai INT; p1 INT;
  oy INT; ocy INT; oround INT; oauth INT;
BEGIN
  SELECT id INTO cx FROM chats WHERE name = 'Push Count X';
  SELECT id INTO cy FROM chats WHERE name = 'Push Count Y';

  INSERT INTO cycles (chat_id) VALUES (cx) RETURNING id INTO cyc1;
  INSERT INTO cycles (chat_id) VALUES (cx) RETURNING id INTO cyc2;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cyc1, 1, 'proposing') RETURNING id INTO r1;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cyc2, 1, 'proposing') RETURNING id INTO r2;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (cx, gen_random_uuid(), 'Author', 'active') RETURNING id INTO author;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (cx, gen_random_uuid(), 'AI', 'active') RETURNING id INTO ai;

  -- Two fresh human opinions across two rounds → both counted.
  INSERT INTO propositions (round_id, participant_id, content, created_at) VALUES (r1, author, 'fresh 1', now()) RETURNING id INTO p1;
  INSERT INTO propositions (round_id, participant_id, content, created_at) VALUES (r2, author, 'fresh 2', now());
  -- Older than 12h → excluded from the default window, included in 48h.
  INSERT INTO propositions (round_id, participant_id, content, created_at) VALUES (r1, author, 'stale', now() - interval '24 hours');
  -- AI → excluded.
  INSERT INTO propositions (round_id, participant_id, content, created_at) VALUES (r1, ai, 'ai take', now());
  -- Carried-forward → excluded.
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id, created_at) VALUES (r1, author, 'carried', p1, now());

  -- A different chat's fresh opinion → excluded.
  INSERT INTO cycles (chat_id) VALUES (cy) RETURNING id INTO ocy;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (ocy, 1, 'proposing') RETURNING id INTO oround;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (cy, gen_random_uuid(), 'Other', 'active') RETURNING id INTO oauth;
  INSERT INTO propositions (round_id, participant_id, content, created_at) VALUES (oround, oauth, 'other chat', now());

  PERFORM set_config('t.cx', cx::text, false);
END $$;

SELECT is(
  get_chat_new_opinion_count(current_setting('t.cx')::bigint),
  2,
  'default 12h window: 2 fresh human opinions (AI, carried, stale, other-chat excluded)'
);

SELECT is(
  get_chat_new_opinion_count(current_setting('t.cx')::bigint, now() - interval '48 hours'),
  3,
  '48h window: the 24h-old opinion is now included → 3'
);

SELECT * FROM finish();
ROLLBACK;
