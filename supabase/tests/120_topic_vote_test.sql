-- Topic vote (game mode): start_topic_round RPC + on_round_winner_set topic branch.
BEGIN;
SELECT plan(12);

-- ── fixture: a game chat with a host ──
DO $$
DECLARE
  v_chat bigint;
  v_host_part bigint;
  v_p2_part bigint;
BEGIN
  INSERT INTO chats (name, initial_message, mode, max_cycles, rating_mode,
                     match_objective, confirmation_rounds_required, start_mode,
                     proposing_threshold_count, proposing_threshold_percent,
                     rating_threshold_count, rating_threshold_percent)
  VALUES ('topic game', 'seed', 'game', 1, 'matches', 'winner_only', 2, 'manual',
          NULL, NULL, NULL, NULL)
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'Host', true, 'active')
  RETURNING id INTO v_host_part;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'P2', false, 'active')
  RETURNING id INTO v_p2_part;

  PERFORM set_config('test.chat', v_chat::text, false);
  PERFORM set_config('test.host_part', v_host_part::text, false);
  PERFORM set_config('test.p2_part', v_p2_part::text, false);
END $$;

-- ── start_topic_round (service role) ──
SET LOCAL ROLE service_role;
SELECT lives_ok(
  $$ SELECT start_topic_round(current_setting('test.chat')::bigint, 'What should we decide next?') $$,
  'A1: start_topic_round succeeds for a game chat (service role)');
RESET ROLE;

-- the topic cycle exists, single round in proposing
SELECT is(
  (SELECT is_topic FROM cycles WHERE chat_id = current_setting('test.chat')::bigint ORDER BY id DESC LIMIT 1),
  true, 'A2: newest cycle is a TOPIC cycle (is_topic = true)');

SELECT is(
  (SELECT phase FROM rounds r JOIN cycles c ON c.id = r.cycle_id
   WHERE c.chat_id = current_setting('test.chat')::bigint AND c.is_topic
   ORDER BY r.id DESC LIMIT 1),
  'proposing', 'A3: topic cycle opens with a proposing round');

SELECT is(
  (SELECT initial_message FROM chats WHERE id = current_setting('test.chat')::bigint),
  'What should we decide next?', 'A4: chat question is set to the topic prompt');

-- ── on_round_winner_set topic branch ──
DO $$
DECLARE
  v_chat bigint := current_setting('test.chat')::bigint;
  v_host bigint := current_setting('test.host_part')::bigint;
  v_topic_cycle bigint;
  v_topic_round bigint;
  v_prop1 bigint;
BEGIN
  SELECT id INTO v_topic_cycle FROM cycles
    WHERE chat_id = v_chat AND is_topic ORDER BY id DESC LIMIT 1;
  SELECT id INTO v_topic_round FROM rounds WHERE cycle_id = v_topic_cycle ORDER BY id DESC LIMIT 1;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_topic_round, v_host, 'Where should we travel?') RETURNING id INTO v_prop1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_topic_round, current_setting('test.p2_part')::bigint, 'What movie tonight?');

  PERFORM set_config('test.topic_cycle', v_topic_cycle::text, false);
  PERFORM set_config('test.topic_round', v_topic_round::text, false);
  PERFORM set_config('test.prop1', v_prop1::text, false);

  -- Setting a sole winner on the topic round fires on_round_winner_set -> topic branch.
  UPDATE rounds SET winning_proposition_id = v_prop1, is_sole_winner = true
  WHERE id = v_topic_round;
END $$;

-- the topic round did NOT carry forward / converge — it seeded an answer game
SELECT is(
  (SELECT content FROM propositions WHERE id = current_setting('test.prop1')::bigint),
  (SELECT initial_message FROM chats WHERE id = current_setting('test.chat')::bigint),
  'B1: chat question becomes the winning topic');

SELECT isnt(
  (SELECT completed_at FROM cycles WHERE id = current_setting('test.topic_cycle')::bigint),
  NULL, 'B2: topic cycle is completed');

SELECT is(
  (SELECT ended_at FROM chats WHERE id = current_setting('test.chat')::bigint),
  NULL, 'B3: chat stays open (not ended) through the topic->answer transition');

-- a fresh ANSWER cycle exists (is_topic = false), with a proposing round
SELECT is(
  (SELECT is_topic FROM cycles WHERE chat_id = current_setting('test.chat')::bigint ORDER BY id DESC LIMIT 1),
  false, 'B4: newest cycle is now the ANSWER cycle (is_topic = false)');

SELECT is(
  (SELECT phase FROM rounds r JOIN cycles c ON c.id = r.cycle_id
   WHERE c.chat_id = current_setting('test.chat')::bigint AND NOT c.is_topic
   ORDER BY r.id DESC LIMIT 1),
  'proposing', 'B5: answer cycle opens with a proposing round');

-- the topic round did NOT create a round 2 in the topic cycle (single round only)
SELECT is(
  (SELECT count(*)::int FROM rounds WHERE cycle_id = current_setting('test.topic_cycle')::bigint),
  1, 'B6: topic cycle has exactly ONE round (no convergence / carry-forward)');

-- ── guards ──
SET LOCAL ROLE service_role;
SELECT throws_ok(
  $$ SELECT start_topic_round(current_setting('test.chat')::bigint, '') $$,
  NULL, 'C1: empty prompt is rejected');
RESET ROLE;

-- non-game chat is rejected
DO $$
DECLARE v_dc bigint;
BEGIN
  INSERT INTO chats (name, initial_message, mode) VALUES ('decision', 'q', 'decision')
  RETURNING id INTO v_dc;
  PERFORM set_config('test.decision_chat', v_dc::text, false);
END $$;
SET LOCAL ROLE service_role;
SELECT throws_ok(
  $$ SELECT start_topic_round(current_setting('test.decision_chat')::bigint, 'x') $$,
  NULL, 'C2: non-game chat is rejected');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
