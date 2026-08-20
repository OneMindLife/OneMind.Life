-- =============================================================================
-- Tests for the Quick-Create / prioritization flow — DB layer.
-- Migrations:
--   20260530000000_stop_after_n_cycles.sql   (chats.max_cycles/ended_at/is_preview
--                                              + max_cycles-aware on_cycle_winner_set)
--   20260530001000_prioritization_seed.sql   (seed_prioritization_round, trigger_process_timers)
-- =============================================================================
-- Coverage:
--   1.  seed_prioritization_round (as host) creates exactly N ownerless
--       (participant_id IS NULL) propositions in one round whose phase = 'rating'
--       and custom_id = 1.
--   2.  The seeded round's cycle exists AND the chat is NOT yet ended (ended_at IS NULL).
--   3.  Seeding with fewer than 2 options throws.
--   4.  Seeding twice on the same chat throws (one cycle per chat).
--   5.  A non-host caller throws.
--   6.  chat_credits balance is bumped high (>= 100000) after seeding.
--   7.  STOP HOOK: a chat with max_cycles = 1 ends (ended_at set, NO new cycle)
--       when its cycle reaches consensus.
--   8.  CONTINUOUS CONTROL: a chat with max_cycles IS NULL gets a SECOND cycle on
--       consensus (ended_at stays NULL) — default continuous behavior preserved.
--
-- Auth note: seed_prioritization_round is SECURITY DEFINER but its host check uses
-- auth.uid(), so it must be invoked under the `authenticated` role with the host's
-- jwt claims (RESET ROLE afterward for the postgres-side assertions).
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(14);

-- =============================================================================
-- SETUP: a prioritization chat with a host (auth user) + a couple of raters.
-- The chat row + its chat_credits row are created by the normal INSERT path
-- (trg_chat_insert_create_credits auto-creates the credits row).
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token, is_preview)
VALUES ('Quick Create Prioritization Test', 'Rank these', gen_random_uuid(), true);

DO $$
DECLARE
  v_chat_id INT;
  v_host INT; v_p2 INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Quick Create Prioritization Test';

  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES
    ('00000000-0000-0000-0000-0000000000c1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000c2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000c9'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1'::UUID, 'Host', TRUE, 'active') RETURNING id INTO v_host;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000c2'::UUID, 'Rater', FALSE, 'active') RETURNING id INTO v_p2;

  -- Knock the balance DOWN first so test 6's "bumped to >= 100000" is observable
  -- (default is already 100000; without this the bump line is unobservable).
  UPDATE chat_credits SET credit_balance = 5 WHERE chat_id = v_chat_id;

  PERFORM set_config('test.qc.chat_id', v_chat_id::TEXT, FALSE);
  PERFORM set_config('test.qc.host',    v_host::TEXT, FALSE);
  PERFORM set_config('test.qc.p2',      v_p2::TEXT, FALSE);
END $$;

-- =============================================================================
-- 1-2. Seed as the host. Invoke under the authenticated role (auth.uid() check).
-- =============================================================================
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000c1')::TEXT, TRUE);

SELECT lives_ok(
  format('SELECT seed_prioritization_round(%s, ARRAY[''Pizza'',''Tacos'',''Sushi'']::TEXT[], 3600)',
         current_setting('test.qc.chat_id')),
  '1a: host can seed a prioritization round'
);

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- Capture the seeded round.
DO $$
DECLARE v_round_id INT;
BEGIN
  SELECT r.id INTO v_round_id
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = current_setting('test.qc.chat_id')::INT
  ORDER BY r.id LIMIT 1;
  PERFORM set_config('test.qc.round_id', v_round_id::TEXT, FALSE);
END $$;

-- 1b: exactly 3 ownerless propositions (participant_id IS NULL) in that round.
SELECT is(
  (SELECT COUNT(*)::INT FROM propositions
     WHERE round_id = current_setting('test.qc.round_id')::INT
       AND participant_id IS NULL),
  3,
  '1b: exactly 3 ownerless (participant_id NULL) propositions seeded'
);

-- 1c: every proposition in the round is ownerless (no non-null owners).
SELECT is(
  (SELECT COUNT(*)::INT FROM propositions
     WHERE round_id = current_setting('test.qc.round_id')::INT
       AND participant_id IS NOT NULL),
  0,
  '1c: no owned propositions exist in the seeded round'
);

-- 1d: the round is in the rating phase with custom_id = 1.
SELECT results_eq(
  format('SELECT phase::TEXT, custom_id FROM rounds WHERE id = %s', current_setting('test.qc.round_id')),
  $q$ VALUES ('rating', 1) $q$,
  '1d: seeded round is phase=rating, custom_id=1'
);

-- 2a: the cycle exists (exactly one for this chat).
SELECT is(
  (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.qc.chat_id')::INT),
  1,
  '2a: exactly one cycle was created for the seeded chat'
);

-- 2b: the chat is not yet ended.
SELECT ok(
  (SELECT ended_at IS NULL FROM chats WHERE id = current_setting('test.qc.chat_id')::INT),
  '2b: chat is not ended after seeding (ended_at IS NULL)'
);

-- =============================================================================
-- 3. < 2 options throws.  4. double-seed throws.  5. non-host throws.
-- All invoked under the authenticated role.
-- =============================================================================
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000c1')::TEXT, TRUE);

-- 4 first: this chat already has a cycle (from test 1), so re-seeding throws
-- regardless of option count. Use a valid 2+ option list so the failure is the
-- one-cycle-per-chat guard, not the option-count guard.
SELECT throws_ok(
  format('SELECT seed_prioritization_round(%s, ARRAY[''A'',''B'']::TEXT[], 3600)',
         current_setting('test.qc.chat_id')),
  NULL, '4: seeding a chat that already has a cycle throws (one cycle per chat)'
);

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- For tests 3 and 5 we need a FRESH chat (no cycle yet) hosted by c1.
INSERT INTO chats (name, initial_message, creator_session_token, is_preview)
VALUES ('Quick Create Prioritization Test 2', 'Rank these', gen_random_uuid(), true);

DO $$
DECLARE v_chat2 INT;
BEGIN
  SELECT id INTO v_chat2 FROM chats WHERE name = 'Quick Create Prioritization Test 2';
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat2, gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1'::UUID, 'Host', TRUE, 'active');
  PERFORM set_config('test.qc.chat2', v_chat2::TEXT, FALSE);
END $$;

-- 3: fewer than 2 options throws (host on a fresh chat).
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000c1')::TEXT, TRUE);
SELECT throws_ok(
  format('SELECT seed_prioritization_round(%s, ARRAY[''Only one'']::TEXT[], 3600)',
         current_setting('test.qc.chat2')),
  NULL, '3: seeding with fewer than 2 options throws'
);
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- 5: a non-host caller throws (c9 is an auth user but NOT a participant/host of chat2).
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000c9')::TEXT, TRUE);
SELECT throws_ok(
  format('SELECT seed_prioritization_round(%s, ARRAY[''A'',''B'']::TEXT[], 3600)',
         current_setting('test.qc.chat2')),
  NULL, '5: a non-host caller throws'
);
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- =============================================================================
-- 6. chat_credits balance bumped high after seeding.
-- The setup knocked it down to 5; the seed RPC's GREATEST(..., 100000) bump raises
-- it, then fund_round_participants funds the host (-1) → lands ~99999. Assert it was
-- bumped well above 5 (tolerant of the funding deduction).
-- =============================================================================
SELECT ok(
  (SELECT credit_balance FROM chat_credits WHERE chat_id = current_setting('test.qc.chat_id')::INT) >= 99000,
  '6: chat_credits balance is bumped high (>= 99000) after seeding'
);

-- =============================================================================
-- 7. STOP HOOK — a chat with max_cycles = 1 ends on consensus, no new cycle.
-- Drive consensus the same way 42_cycle_winner_auto_start_test does: a proposing
-- round with a rated proposition, set winner + is_sole_winner on a chat with
-- confirmation_rounds_required = 1. on_round_winner_set completes the cycle, which
-- fires on_cycle_winner_set — the max_cycles branch under test.
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required, max_cycles, access_method)
VALUES ('Quick Create Capped Test', 'Cap test', gen_random_uuid(), 1, 1, 'code');

DO $$
DECLARE
  v_chat INT; v_cycle INT; v_round INT; v_part INT; v_prop INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Quick Create Capped Test';
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'Host', TRUE, 'active') RETURNING id INTO v_part;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle, 1, 'proposing', NOW()) RETURNING id INTO v_round;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_part, 'Capped Winner') RETURNING id INTO v_prop;
  UPDATE rounds SET phase = 'rating' WHERE id = v_round;
  INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
    VALUES (v_prop, v_round, 90);

  -- Fire consensus.
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_round;

  PERFORM set_config('test.qc.capped_chat', v_chat::TEXT, FALSE);
END $$;

-- 7a: chat is now ended.
SELECT ok(
  (SELECT ended_at IS NOT NULL FROM chats WHERE id = current_setting('test.qc.capped_chat')::INT),
  '7a: capped chat (max_cycles=1) has ended_at set after consensus'
);

-- 7b: still exactly one cycle (no continuation).
SELECT is(
  (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.qc.capped_chat')::INT),
  1,
  '7b: capped chat has exactly one cycle (no new cycle created)'
);

-- =============================================================================
-- 8. CONTINUOUS CONTROL — a chat with max_cycles IS NULL gets a SECOND cycle on
-- consensus and stays live (ended_at NULL).
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token, confirmation_rounds_required, max_cycles, access_method)
VALUES ('Quick Create Continuous Test', 'Continuous test', gen_random_uuid(), 1, NULL, 'code');

DO $$
DECLARE
  v_chat INT; v_cycle INT; v_round INT; v_part INT; v_prop INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Quick Create Continuous Test';
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'Host', TRUE, 'active') RETURNING id INTO v_part;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle, 1, 'proposing', NOW()) RETURNING id INTO v_round;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round, v_part, 'Continuous Winner') RETURNING id INTO v_prop;
  UPDATE rounds SET phase = 'rating' WHERE id = v_round;
  INSERT INTO proposition_movda_ratings (proposition_id, round_id, rating)
    VALUES (v_prop, v_round, 90);

  -- Fire consensus.
  UPDATE rounds SET winning_proposition_id = v_prop, is_sole_winner = TRUE WHERE id = v_round;

  PERFORM set_config('test.qc.cont_chat', v_chat::TEXT, FALSE);
END $$;

-- 8a: a SECOND cycle was created (default continuous behavior).
SELECT is(
  (SELECT COUNT(*)::INT FROM cycles WHERE chat_id = current_setting('test.qc.cont_chat')::INT),
  2,
  '8a: uncapped chat (max_cycles NULL) gets a second cycle on consensus'
);

-- 8b: chat stays live.
SELECT ok(
  (SELECT ended_at IS NULL FROM chats WHERE id = current_setting('test.qc.cont_chat')::INT),
  '8b: uncapped chat stays live (ended_at IS NULL)'
);

SELECT * FROM finish();
ROLLBACK;
