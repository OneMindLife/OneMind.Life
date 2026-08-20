-- =============================================================================
-- Tests for chat_id denormalization on the round-child realtime tables.
-- Migration: 20260602150000_round_child_chat_id_realtime_rls.sql
-- =============================================================================
-- Mirrors 115 (propositions) for rating_completions / rating_skips /
-- round_skips / affirmations: chat_id is NOT NULL, the shared trigger derives
-- it from round_id, and the SELECT policy is the realtime-authorizable
-- is_chat_participant(chat_id) (participant sees, non-participant does not).
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

INSERT INTO auth.users (id, aud, role, instance_id) VALUES
  ('00000000-0000-0000-0000-0000000000f1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
  ('00000000-0000-0000-0000-0000000000f2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE v_chat INT; v_cycle INT; v_round INT; v_member INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('round-child chat_id test', 'q', gen_random_uuid()) RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000f1'::UUID, 'Member', TRUE, 'active')
    RETURNING id INTO v_member;
  PERFORM set_config('test.chat', v_chat::text, false);
  PERFORM set_config('test.round', v_round::text, false);
  PERFORM set_config('test.member', v_member::text, false);
END $$;

-- 1-4. chat_id NOT NULL on all four tables
SELECT col_not_null('public', 'rating_completions', 'chat_id', 'rating_completions.chat_id NOT NULL');
SELECT col_not_null('public', 'rating_skips',       'chat_id', 'rating_skips.chat_id NOT NULL');
SELECT col_not_null('public', 'round_skips',        'chat_id', 'round_skips.chat_id NOT NULL');
SELECT col_not_null('public', 'affirmations',       'chat_id', 'affirmations.chat_id NOT NULL');

-- 5. shared trigger derives chat_id on a rating_completions insert
INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.round')::bigint, current_setting('test.member')::bigint);
SELECT is(
  (SELECT chat_id FROM rating_completions WHERE round_id = current_setting('test.round')::bigint),
  current_setting('test.chat')::bigint,
  'trigger derived chat_id on rating_completions');

-- 6. same shared trigger on a different table (affirmations)
INSERT INTO affirmations (round_id, participant_id, user_id)
VALUES (current_setting('test.round')::bigint, current_setting('test.member')::bigint,
        '00000000-0000-0000-0000-0000000000f1'::UUID);
SELECT is(
  (SELECT chat_id FROM affirmations WHERE round_id = current_setting('test.round')::bigint),
  current_setting('test.chat')::bigint,
  'shared trigger derived chat_id on affirmations too');

-- 7/8. RLS: chat participant sees rating_completions; non-participant does not
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1"}', true);
SELECT ok(
  (SELECT count(*) FROM rating_completions WHERE chat_id = current_setting('test.chat')::bigint) >= 1,
  'active participant CAN see the chat''s rating_completions');

SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f2"}', true);
SELECT is(
  (SELECT count(*) FROM rating_completions WHERE chat_id = current_setting('test.chat')::bigint),
  0::bigint,
  'non-participant CANNOT see the chat''s rating_completions');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
