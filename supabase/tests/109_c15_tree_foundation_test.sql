-- =============================================================================
-- C15 tree foundation (migration 20260712200000) — structural + behavioral
-- =============================================================================
-- Covers:
--   1. Schema: cycles.parent_proposition_id, chats.branching_enabled,
--      one-child-per-proposition uniqueness.
--   2. Clock-only constraint: branching chats cannot carry early-advance
--      thresholds (chk_branching_clock_only).
--   3. get_or_create_node_cycle: spawns child cycle + round synced to the
--      root round's window; idempotent; refuses when branching is off or the
--      proposing window is closed.
--   4. on_cycle_winner_set gating: a CHILD cycle sealing spawns NO new root
--      cycle and does not end the chat; a ROOT cycle sealing still spawns the
--      next root cycle (continuous default).

BEGIN;
SELECT plan(15);

-- Schema
SELECT has_column('public', 'cycles', 'parent_proposition_id', 'cycles.parent_proposition_id exists');
SELECT has_column('public', 'chats', 'branching_enabled', 'chats.branching_enabled exists');

-- ── Fixture: branching chat, root cycle+round, two props ─────────────────────
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('c1500000-1111-2222-3333-0000000000a1'::uuid, 'authenticated', 'c15_a@test.com',
   crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('c1500000-1111-2222-3333-0000000000b1'::uuid, 'authenticated', 'c15_b@test.com',
   crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

DO $$
DECLARE
  v_chat BIGINT; v_cycle BIGINT; v_round BIGINT; v_part BIGINT;
  v_prop1 BIGINT; v_prop2 BIGINT;
BEGIN
  INSERT INTO chats (name, mode, initial_message, access_method, host_display_name,
                     branching_enabled, max_cycles,
                     proposing_duration_seconds, rating_duration_seconds,
                     proposing_threshold_percent, proposing_threshold_count,
                     rating_threshold_percent, rating_threshold_count)
  VALUES ('c15-test', 'decision', 'root q', 'code', 'tester', true, NULL, 43200, 43200,
          NULL, NULL, NULL, NULL)
  RETURNING id INTO v_chat;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle, 1, 'proposing', now(), now() + interval '12 hours')
  RETURNING id INTO v_round;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, 'c1500000-1111-2222-3333-0000000000a1'::uuid, 'C15 Tester A', 'active')
  RETURNING id INTO v_part;

  INSERT INTO propositions (round_id, participant_id, chat_id, content)
  VALUES (v_round, v_part, v_chat, 'option A') RETURNING id INTO v_prop1;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, 'c1500000-1111-2222-3333-0000000000b1'::uuid, 'C15 Tester B', 'active')
  RETURNING id INTO v_part;

  INSERT INTO propositions (round_id, participant_id, chat_id, content)
  VALUES (v_round, v_part, v_chat, 'option B') RETURNING id INTO v_prop2;

  PERFORM set_config('test.chat', v_chat::TEXT, TRUE);
  PERFORM set_config('test.cycle', v_cycle::TEXT, TRUE);
  PERFORM set_config('test.round', v_round::TEXT, TRUE);
  PERFORM set_config('test.prop1', v_prop1::TEXT, TRUE);
  PERFORM set_config('test.prop2', v_prop2::TEXT, TRUE);
END $$;

-- Simulate authenticated caller (participant A) for the RPC's guard.
SELECT set_config('request.jwt.claims',
  '{"sub":"c1500000-1111-2222-3333-0000000000a1","role":"authenticated"}', true);

-- 2. Clock-only constraint
SELECT throws_ok(
  format('UPDATE chats SET proposing_threshold_percent = 100 WHERE id = %s',
         current_setting('test.chat')),
  '23514', NULL,
  'branching chat cannot set early-advance thresholds (chk_branching_clock_only)'
);

-- 3. Spawn: creates child cycle + synced round
SELECT lives_ok(
  format('SELECT get_or_create_node_cycle(%s)', current_setting('test.prop1')),
  'get_or_create_node_cycle spawns for prop1'
);

SELECT ok(
  EXISTS (SELECT 1 FROM cycles
          WHERE parent_proposition_id = current_setting('test.prop1')::BIGINT),
  'child cycle exists with parent_proposition_id set'
);

SELECT is(
  (SELECT r.phase_ends_at FROM rounds r
   JOIN cycles c ON c.id = r.cycle_id
   WHERE c.parent_proposition_id = current_setting('test.prop1')::BIGINT),
  (SELECT phase_ends_at FROM rounds WHERE id = current_setting('test.round')::BIGINT),
  'child round clock synced to root round window end'
);

SELECT is(
  get_or_create_node_cycle(current_setting('test.prop1')::BIGINT),
  (SELECT id FROM cycles WHERE parent_proposition_id = current_setting('test.prop1')::BIGINT),
  'spawn is idempotent — returns existing child cycle'
);

-- Window closed → refuse spawn. The window is the newest LIVE round anywhere
-- in the tree, so close ALL live rounds of this chat (root + spawned child).
UPDATE rounds SET phase = 'rating'
WHERE cycle_id IN (SELECT id FROM cycles WHERE chat_id = current_setting('test.chat')::BIGINT)
  AND completed_at IS NULL;
SELECT throws_ok(
  format('SELECT get_or_create_node_cycle(%s)', current_setting('test.prop2')),
  'window_closed',
  'spawn refused outside the proposing window'
);
UPDATE rounds SET phase = 'proposing'
WHERE cycle_id IN (SELECT id FROM cycles WHERE chat_id = current_setting('test.chat')::BIGINT)
  AND completed_at IS NULL;

-- Branching disabled → refuse spawn (fresh non-branching chat)
DO $$
DECLARE v_chat BIGINT; v_cycle BIGINT; v_round BIGINT; v_part BIGINT; v_prop BIGINT;
BEGIN
  INSERT INTO chats (name, mode, initial_message, access_method, host_display_name)
  VALUES ('c15-off', 'decision', 'q', 'code', 'tester') RETURNING id INTO v_chat;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle, 1, 'proposing', now(), now() + interval '12 hours') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, 'c1500000-1111-2222-3333-0000000000a1'::uuid, 'T', 'active') RETURNING id INTO v_part;
  INSERT INTO propositions (round_id, participant_id, chat_id, content)
  VALUES (v_round, v_part, v_chat, 'x') RETURNING id INTO v_prop;
  PERFORM set_config('test.offprop', v_prop::TEXT, TRUE);
END $$;

SELECT throws_ok(
  format('SELECT get_or_create_node_cycle(%s)', current_setting('test.offprop')),
  NULL, NULL,
  'spawn refused when branching_enabled is false'
);

-- 4. on_cycle_winner_set gating
-- Child cycle seals → NO new root cycle, chat not ended.
DO $$
DECLARE v_child BIGINT; v_croot BIGINT;
BEGIN
  SELECT id INTO v_child FROM cycles
  WHERE parent_proposition_id = current_setting('test.prop1')::BIGINT;
  PERFORM set_config('test.child', v_child::TEXT, TRUE);
  SELECT COUNT(*) INTO v_croot FROM cycles
  WHERE chat_id = current_setting('test.chat')::BIGINT AND parent_proposition_id IS NULL;
  PERFORM set_config('test.roots_before', v_croot::TEXT, TRUE);
END $$;

UPDATE cycles SET winning_proposition_id = current_setting('test.prop2')::BIGINT,
                  completed_at = now()
WHERE id = current_setting('test.child')::BIGINT;

SELECT is(
  (SELECT COUNT(*) FROM cycles
   WHERE chat_id = current_setting('test.chat')::BIGINT AND parent_proposition_id IS NULL),
  current_setting('test.roots_before')::BIGINT,
  'child cycle sealing spawns NO new root cycle'
);

SELECT ok(
  (SELECT ended_at IS NULL FROM chats WHERE id = current_setting('test.chat')::BIGINT),
  'child cycle sealing does not end the chat'
);

-- Root cycle seals in a BRANCHING chat → the spine DESCENDS: no new root
-- cycle; the winner's follow-up subround exists (spawned by the seal since
-- prop1's child already existed — here prop1 wins and already has a child,
-- so nothing new; use prop2's win on a fresh root to see the spawn).
UPDATE cycles SET winning_proposition_id = current_setting('test.prop2')::BIGINT,
                  completed_at = now()
WHERE id = current_setting('test.cycle')::BIGINT;

SELECT is(
  (SELECT COUNT(*) FROM cycles
   WHERE chat_id = current_setting('test.chat')::BIGINT AND parent_proposition_id IS NULL),
  current_setting('test.roots_before')::BIGINT,
  'branching: root seal spawns NO new root cycle (spine descends)'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM cycles c JOIN rounds r ON r.cycle_id = c.id
    WHERE c.parent_proposition_id = current_setting('test.prop2')::BIGINT
      AND r.phase = 'proposing'
  ),
  'branching: root seal spawns the winner''s follow-up subround (live tip)'
);

-- Child cycles are excluded from the max_cycles cap count
SELECT ok(
  (SELECT prosrc LIKE '%parent_proposition_id IS NULL%'
   FROM pg_proc WHERE proname = 'on_cycle_winner_set'),
  'on_cycle_winner_set counts only root cycles toward max_cycles'
);

-- notify_push_round: repository (never_seals) chats push root-only — child
-- rounds are excluded. Gate narrowed in 20260715085858 from a blanket
-- parent_proposition_id IS NULL to a never_seals-scoped exclusion (normal
-- branching chats intentionally still push on child rounds).
SELECT ok(
  (SELECT prosrc LIKE '%never_seals = true AND c.parent_proposition_id IS NOT NULL%'
   FROM pg_proc WHERE proname = 'notify_push_round'),
  'notify_push_round gates repository (never_seals) child rounds to root-only'
);

SELECT * FROM finish();
ROLLBACK;
