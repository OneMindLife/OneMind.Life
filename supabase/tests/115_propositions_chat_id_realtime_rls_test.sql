-- =============================================================================
-- Tests for propositions.chat_id denormalization + realtime-friendly RLS.
-- Migration: 20260602140000_propositions_chat_id_realtime_rls.sql
-- =============================================================================
-- Covers:
--   1. chat_id column exists and is NOT NULL
--   2. BEFORE INSERT trigger sets chat_id from round_id (server-derived)
--   3. trigger OVERRIDES a client-supplied chat_id (unspoofable)
--   4. backfill: chat_id matches round -> cycle -> chat
--   5/6/7. SELECT policy access is correct: chat participant sees props,
--          a non-participant does NOT, anon does NOT (same access as the old
--          deep-join policy, but realtime-authorizable).
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

-- SETUP -----------------------------------------------------------------------
INSERT INTO auth.users (id, aud, role, instance_id) VALUES
  ('00000000-0000-0000-0000-0000000000e1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
  ('00000000-0000-0000-0000-0000000000e2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_chat INT; v_other_chat INT; v_cycle INT; v_round INT; v_round2 INT; v_member INT; v_prop INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('prop chat_id test', 'q', gen_random_uuid()) RETURNING id INTO v_chat;
  INSERT INTO chats (name, initial_message, creator_session_token)
    VALUES ('other chat', 'q', gen_random_uuid()) RETURNING id INTO v_other_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'proposing') RETURNING id INTO v_round;
  -- second round so the spoof-override prop doesn't trip the one-new-per-round unique
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 2, 'proposing') RETURNING id INTO v_round2;

  -- e1 is an active participant of v_chat; e2 is NOT.
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000e1'::UUID, 'Member', TRUE, 'active')
    RETURNING id INTO v_member;

  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_member, 'Backfill/trigger target') RETURNING id INTO v_prop;

  PERFORM set_config('test.chat', v_chat::text, false);
  PERFORM set_config('test.other_chat', v_other_chat::text, false);
  PERFORM set_config('test.round', v_round::text, false);
  PERFORM set_config('test.round2', v_round2::text, false);
  PERFORM set_config('test.member', v_member::text, false);
  PERFORM set_config('test.prop', v_prop::text, false);
END $$;

-- 1. column exists + NOT NULL
SELECT has_column('public', 'propositions', 'chat_id', 'propositions.chat_id exists');
SELECT col_not_null('public', 'propositions', 'chat_id', 'propositions.chat_id is NOT NULL');

-- 2. trigger set chat_id on the inserted prop = the round's chat
SELECT is(
  (SELECT chat_id FROM propositions WHERE id = current_setting('test.prop')::int),
  current_setting('test.chat')::bigint,
  'trigger/backfill set chat_id from round -> cycle -> chat'
);

-- 3. trigger OVERRIDES a client-supplied (wrong) chat_id — unspoofable
INSERT INTO propositions (round_id, participant_id, content, chat_id)
VALUES (current_setting('test.round2')::bigint, current_setting('test.member')::bigint,
        'spoof attempt', current_setting('test.other_chat')::bigint);
SELECT is(
  (SELECT chat_id FROM propositions WHERE content = 'spoof attempt'),
  current_setting('test.chat')::bigint,
  'BEFORE INSERT trigger overrides a client-supplied chat_id (cannot spoof)'
);

-- 4/5/6. RLS visibility under the new single-table policy
-- participant (e1) CAN see the chat's propositions
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1"}', true);
SELECT ok(
  (SELECT count(*) FROM propositions WHERE chat_id = current_setting('test.chat')::bigint) >= 1,
  'active participant CAN see the chat''s propositions'
);

-- non-participant (e2) CANNOT see them
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2"}', true);
SELECT is(
  (SELECT count(*) FROM propositions WHERE chat_id = current_setting('test.chat')::bigint),
  0::bigint,
  'non-participant CANNOT see the chat''s propositions'
);

-- anon CANNOT see them
RESET ROLE;
SET ROLE anon;
SELECT is(
  (SELECT count(*) FROM propositions WHERE chat_id = current_setting('test.chat')::bigint),
  0::bigint,
  'anon CANNOT see the chat''s propositions'
);

RESET ROLE;

-- 8. ENABLE ALWAYS: the trigger fires even with triggers disabled (replica
--    mode), so chat_id is still derived — bulk loads / trigger-off test setups
--    can't leave it NULL.
SET LOCAL session_replication_role = 'replica';
INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.round2')::bigint, NULL, 'replica-mode insert');
SET LOCAL session_replication_role = 'origin';
SELECT is(
  (SELECT chat_id FROM propositions WHERE content = 'replica-mode insert'),
  current_setting('test.chat')::bigint,
  'chat_id is still derived when session_replication_role = replica (ENABLE ALWAYS)'
);

SELECT * FROM finish();
ROLLBACK;
