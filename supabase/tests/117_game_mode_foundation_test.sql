-- =============================================================================
-- Tests for game-mode foundation — DB layer.
-- Migration: 20260624010000_game_mode_foundation.sql
--   chats.mode flag, cycles.question, start_new_game RPC, get_cycle_leaderboard.
-- =============================================================================
-- Coverage:
--   A. Schema
--      A1: chats.mode defaults to 'decision'
--      A2: chats_mode_check rejects an invalid mode
--      A3: cycles.question column exists
--   B. start_new_game
--      B1: decision-mode chat throws (game-only)
--      B2: empty question throws
--      B3: happy path returns a NEW cycle id
--      B4: chats.ended_at is cleared (room reopened)
--      B5: the new cycle carries the new question
--      B6: a round 1 is created for the new cycle
--      B7: participants carry over (still active, same roster)
--      B8: non-host caller throws
--   C. get_cycle_leaderboard
--      C1: scoped to ONE cycle — only that cycle's ranks are reflected
--      C2: ordered by avg_rank DESC (top scorer first)
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched. start_new_game is SECURITY
-- DEFINER; the happy-path calls run as service_role (bypasses the host check).
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(14);

-- Auth user for the non-host authz test.
INSERT INTO auth.users (id, aud, role, instance_id)
VALUES ('00000000-0000-0000-0000-0000000000e1'::UUID, 'authenticated', 'authenticated',
        '00000000-0000-0000-0000-000000000000'::UUID)
ON CONFLICT (id) DO NOTHING;

-- Builder: a chat (given mode) with a host + one other participant and a single
-- COMPLETED cycle, with the chat sealed (ended_at set) as after a finished game.
CREATE OR REPLACE FUNCTION pg_temp.build_game_chat(p_key TEXT, p_mode TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_chat INT; v_cycle INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, max_cycles,
                     confirmation_rounds_required, rating_mode, match_objective,
                     access_method, mode, ended_at)
  VALUES ('Game '||p_key, 'Original question', gen_random_uuid(), 1, 2, 'matches',
          'full_rank', 'code', p_mode, NOW())
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, created_at)
  VALUES (v_chat, gen_random_uuid(), 'Host', TRUE, 'active', NOW() - INTERVAL '1 hour');
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, created_at)
  VALUES (v_chat, gen_random_uuid(), 'Player', FALSE, 'active', NOW() - INTERVAL '1 hour');

  INSERT INTO cycles (chat_id, completed_at) VALUES (v_chat, NOW()) RETURNING id INTO v_cycle;

  PERFORM set_config('test.'||p_key||'.chat', v_chat::TEXT, FALSE);
  PERFORM set_config('test.'||p_key||'.cycle', v_cycle::TEXT, FALSE);
END $$;

-- ---------------------------------------------------------------------------
-- A. Schema
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT column_default FROM information_schema.columns
   WHERE table_name='chats' AND column_name='mode'),
  '''decision''::text',
  'A1: chats.mode defaults to decision');

SELECT throws_ok(
  $$ INSERT INTO chats (name, initial_message, creator_session_token, max_cycles,
                        confirmation_rounds_required, rating_mode, match_objective,
                        access_method, mode)
     VALUES ('bad', 'q', gen_random_uuid(), 1, 2, 'matches', 'full_rank', 'code', 'bogus') $$,
  '23514', NULL,
  'A2: chats_mode_check rejects an invalid mode');

SELECT has_column('cycles', 'question', 'A3: cycles.question column exists');

-- ---------------------------------------------------------------------------
-- B. start_new_game
-- ---------------------------------------------------------------------------
SELECT pg_temp.build_game_chat('dec', 'decision');
SELECT pg_temp.build_game_chat('game', 'game');

-- B1: decision-mode chat is rejected.
SELECT throws_ok(
  format('SELECT start_new_game(%s, %L)', current_setting('test.dec.chat'), 'New Q'),
  'start_new_game is only available for game-mode chats',
  'B1: start_new_game rejects a decision-mode chat');

-- B2: empty question rejected.
SELECT throws_ok(
  format('SELECT start_new_game(%s, %L)', current_setting('test.game.chat'), '   '),
  'A question is required to start a new game',
  'B2: start_new_game rejects an empty question');

-- B3/B4/B5/B6/B7: happy path (run as service_role to bypass host check).
SET LOCAL ROLE service_role;
SELECT lives_ok(
  format('SELECT set_config(''test.game.newcycle'', start_new_game(%s, %L)::text, false)',
         current_setting('test.game.chat'), 'A brand new question'),
  'B3: start_new_game happy path runs');
RESET ROLE;

SELECT isnt(current_setting('test.game.newcycle'), current_setting('test.game.cycle'),
  'B3b: returns a NEW cycle (not the old one)');

SELECT is(
  (SELECT ended_at FROM chats WHERE id = current_setting('test.game.chat')::int),
  NULL::timestamptz,
  'B4: chats.ended_at cleared (room reopened)');

SELECT is(
  (SELECT question FROM cycles WHERE id = current_setting('test.game.newcycle')::int),
  'A brand new question',
  'B5: new cycle carries the new question');

SELECT is(
  (SELECT count(*)::int FROM rounds WHERE cycle_id = current_setting('test.game.newcycle')::int),
  1,
  'B6: a round was created for the new cycle');

SELECT is(
  (SELECT count(*)::int FROM participants
   WHERE chat_id = current_setting('test.game.chat')::int AND status='active'),
  2,
  'B7: participants carried over (roster intact)');

-- B8: non-host authenticated caller is rejected.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', TRUE);
SELECT throws_ok(
  format('SELECT start_new_game(%s, %L)', current_setting('test.game.chat'), 'Q'),
  'Only the host can start a new game',
  'B8: non-host caller is rejected');
RESET ROLE;
SELECT set_config('request.jwt.claims', NULL, TRUE);

-- ---------------------------------------------------------------------------
-- C. get_cycle_leaderboard (per-game scoping)
-- ---------------------------------------------------------------------------
-- Build a game chat with TWO cycles, each one round, with user_round_ranks.
DO $$
DECLARE v_chat INT; v_c1 INT; v_c2 INT; v_r1 INT; v_r2 INT; v_p1 INT; v_p2 INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, max_cycles,
                     confirmation_rounds_required, rating_mode, match_objective,
                     access_method, mode)
  VALUES ('LB', 'q', gen_random_uuid(), 1, 2, 'matches', 'full_rank', 'code', 'game')
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, created_at)
  VALUES (v_chat, gen_random_uuid(), 'Ana', TRUE, 'active', NOW() - INTERVAL '2 hour')
  RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, created_at)
  VALUES (v_chat, gen_random_uuid(), 'Bo', FALSE, 'active', NOW() - INTERVAL '2 hour')
  RETURNING id INTO v_p2;

  INSERT INTO cycles (chat_id, completed_at) VALUES (v_chat, NOW() - INTERVAL '30 min')
  RETURNING id INTO v_c1;
  INSERT INTO rounds (cycle_id, custom_id, phase, created_at)
  VALUES (v_c1, 1, 'rating', NOW() - INTERVAL '40 min') RETURNING id INTO v_r1;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_c2;
  INSERT INTO rounds (cycle_id, custom_id, phase, created_at)
  VALUES (v_c2, 1, 'rating', NOW() - INTERVAL '5 min') RETURNING id INTO v_r2;

  -- Game 1 ranks: Ana 90, Bo 40.   Game 2 ranks: Ana 10, Bo 100.
  INSERT INTO user_round_ranks (round_id, participant_id, rank, voting_rank, proposing_rank)
  VALUES (v_r1, v_p1, 90, 90, 90), (v_r1, v_p2, 40, 40, 40),
         (v_r2, v_p1, 10, 10, 10), (v_r2, v_p2, 100, 100, 100);

  PERFORM set_config('test.lb.c1', v_c1::text, false);
  PERFORM set_config('test.lb.p1', v_p1::text, false);
  PERFORM set_config('test.lb.p2', v_p2::text, false);
END $$;

-- C1: game 1's leaderboard reflects game 1 ranks only (Ana 90, not her 10 from game 2).
SELECT is(
  (SELECT avg_rank::int FROM get_cycle_leaderboard(current_setting('test.lb.c1')::int)
   WHERE participant_id = current_setting('test.lb.p1')::int),
  90,
  'C1: get_cycle_leaderboard is scoped to a single game/cycle');

-- C2: ordered by avg_rank DESC — in game 1, Ana (90) is ahead of Bo (40).
SELECT is(
  (SELECT participant_id FROM get_cycle_leaderboard(current_setting('test.lb.c1')::int)
   ORDER BY avg_rank DESC LIMIT 1),
  current_setting('test.lb.p1')::bigint,
  'C2: leaderboard ordered by avg_rank DESC (top scorer first)');

SELECT * FROM finish();
ROLLBACK;
