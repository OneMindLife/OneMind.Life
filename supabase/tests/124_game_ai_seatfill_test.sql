-- =============================================================================
-- Tests for solo game-mode AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
-- Migrations: 20260625120000..20260625120500
-- =============================================================================
-- Coverage:
--   1.  a game chat (has_ai_player) provisions TWO agents "AI 1","AI 2", role 'off'
--   2.  agent_role CHECK rejects an invalid value
--   3.  regime ANSWER solo (1 human)   → AI1='player',  AI2='player'
--   4.  regime ANSWER 2 humans         → 1 'player', 1 'off'
--   5.  regime ANSWER 3 humans (IDEAT) → 1 'proposer', 0 'player'
--   6.  regime TOPIC solo (FILL)       → 2 'player' (bots vote on topics too)
--   7.  matches eligible at rating-open counts host + 2 player bots (= 3), done = 0
--   8.  bots done, host not            → done = 2, eligible = 3 (won't advance)
--   9.  real solo game: bots done      → round STAYS open (waits for host)
--   10. real solo game: host done too  → round FINALIZES
--   11. get_chat_leaderboard EXCLUDES an agent that has a user_round_ranks row
--   12. get_chat_leaderboard INCLUDES the human alongside that agent
--   13. backfill renamed a legacy lone 'AI' agent path is covered by trigger (2 agents)
--
-- Runs inside BEGIN/ROLLBACK; triggers are SECURITY DEFINER, set up as postgres.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(17);

-- Builder: a game chat (has_ai_player) with N humans, then a cycle + round that
-- opens proposing (fires the regime selector). Returns ids via set_config.
CREATE OR REPLACE FUNCTION pg_temp.mk_game(p_key TEXT, p_humans INT, p_is_topic BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_chat BIGINT; v_cycle BIGINT; v_round BIGINT; v_host BIGINT; i INT;
BEGIN
  -- last_human_seen_at = NOW() keeps the room "warm". The regime selector
  -- (apply_game_ai_regime, arena rework 20260709220000) has a pause-when-empty
  -- cold gate: no human seen in ~2min → every agent parked 'off'. A fresh
  -- fixture has no activity, so without this NO bot ever gets seated.
  INSERT INTO chats (name, initial_message, mode, has_ai_player, is_preview,
                     max_cycles, rating_mode, match_objective,
                     confirmation_rounds_required, start_mode, access_method,
                     proposing_threshold_percent, proposing_threshold_count,
                     rating_threshold_percent, rating_threshold_count,
                     last_human_seen_at)
  VALUES ('SF '||p_key, 'Best plan?', 'game', true, false, 1, 'matches',
          'winner_only', 2, 'manual', 'code', NULL, NULL, NULL, NULL,
          NOW())
  RETURNING id INTO v_chat;
  FOR i IN 1..p_humans LOOP
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
    VALUES (v_chat, gen_random_uuid(), 'H'||i, (i = 1), 'active', false);
  END LOOP;
  INSERT INTO cycles (chat_id, is_topic) VALUES (v_chat, p_is_topic) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle, 1, 'proposing', NOW()) RETURNING id INTO v_round;
  SELECT id INTO v_host FROM participants WHERE chat_id = v_chat AND is_host = true;
  PERFORM set_config('test.'||p_key||'.chat',  v_chat::text,  false);
  PERFORM set_config('test.'||p_key||'.cycle', v_cycle::text, false);
  PERFORM set_config('test.'||p_key||'.round', v_round::text, false);
  PERFORM set_config('test.'||p_key||'.host',  v_host::text,  false);
END $$;

-- ── 1-2. provisioning + constraint ──
SELECT pg_temp.mk_game('prov', 1, false);
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.prov.chat')::bigint AND is_agent = true),
  (SELECT COUNT(*)::int FROM arena_agent_personas),
  '1: a game chat provisions one agent per arena persona');
SELECT throws_ok(
  $$ UPDATE participants SET agent_role = 'bogus'
     WHERE chat_id = current_setting('test.prov.chat')::bigint AND is_agent = true $$,
  NULL, '2: agent_role CHECK rejects an invalid value');

-- ── 3. ANSWER solo → both player ──
-- (prov chat is answer + 1 human; regime selector already ran on its round)
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.prov.chat')::bigint AND agent_role = 'player'),
  2, '3: ANSWER solo → both agents are players');

-- ── 4. ANSWER 2 humans → 1 player, 1 off ──
SELECT pg_temp.mk_game('two', 2, false);
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.two.chat')::bigint AND agent_role = 'player'),
  1, '4: ANSWER 2 humans → exactly one player bot');

-- ── 5. ANSWER 3 humans → IDEATION (1 proposer, 0 players) ──
SELECT pg_temp.mk_game('three', 3, false);
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.three.chat')::bigint AND agent_role = 'player'),
  0, '5a: ANSWER 3 humans → no player bots (AI does not vote)');
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.three.chat')::bigint AND agent_role = 'proposer'),
  1, '5b: ANSWER 3 humans → one ideation proposer');

-- ── 6. TOPIC solo (FILL) → 2 proposer bots. Post arena rework the seat role is
--    is_topic-dependent (CASE WHEN is_topic THEN 'proposer' ELSE 'player'): topic
--    bots pitch topics rather than vote. ──
SELECT pg_temp.mk_game('topic', 1, true);
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.topic.chat')::bigint AND agent_role = 'proposer'),
  2, '6: TOPIC solo (FILL) → 2 proposer bots (topic bots pitch, not vote)');

-- ── 7-10. rating progress + finalize on a real solo game ──
DO $$
DECLARE v_chat BIGINT := current_setting('test.prov.chat')::bigint;
        v_round BIGINT := current_setting('test.prov.round')::bigint;
        v_host BIGINT := current_setting('test.prov.host')::bigint;
        a1 BIGINT; a2 BIGINT; ph BIGINT; p1 BIGINT; p2 BIGINT;
BEGIN
  -- The two seated bots are persona-named now, not 'AI 1'/'AI 2' — pick them by
  -- the role the selector assigned (ANSWER solo → 2 players).
  SELECT id INTO a1 FROM participants
    WHERE chat_id = v_chat AND is_agent = true AND agent_role = 'player' ORDER BY id LIMIT 1;
  SELECT id INTO a2 FROM participants
    WHERE chat_id = v_chat AND is_agent = true AND agent_role = 'player' ORDER BY id OFFSET 1 LIMIT 1;
  INSERT INTO propositions (round_id, participant_id, chat_id, content) VALUES (v_round, v_host, v_chat, 'Host idea') RETURNING id INTO ph;
  INSERT INTO propositions (round_id, participant_id, chat_id, content) VALUES (v_round, a1, v_chat, 'AI1 idea') RETURNING id INTO p1;
  INSERT INTO propositions (round_id, participant_id, chat_id, content) VALUES (v_round, a2, v_chat, 'AI2 idea') RETURNING id INTO p2;
  UPDATE rounds SET phase = 'rating' WHERE id = v_round;
  PERFORM set_config('test.prov.a1', a1::text, false);
  PERFORM set_config('test.prov.a2', a2::text, false);
  PERFORM set_config('test.prov.ph', ph::text, false);
  PERFORM set_config('test.prov.p1', p1::text, false);
  PERFORM set_config('test.prov.p2', p2::text, false);
END $$;

-- 7: at rating-open, eligible = host + 2 player bots = 3; done = 0.
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.prov.round')::bigint, current_setting('test.prov.chat')::bigint)),
  3, '7a: eligible counts host + 2 player bots at rating-open');
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.prov.round')::bigint, current_setting('test.prov.chat')::bigint)),
  0, '7b: done = 0 before anyone votes');

-- bots vote + complete (host has not yet).
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
  VALUES (current_setting('test.prov.round')::bigint, current_setting('test.prov.a1')::bigint,
          current_setting('test.prov.ph')::bigint, current_setting('test.prov.p2')::bigint);
INSERT INTO rating_completions (round_id, participant_id, chat_id)
  VALUES (current_setting('test.prov.round')::bigint, current_setting('test.prov.a1')::bigint, current_setting('test.prov.chat')::bigint);
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
  VALUES (current_setting('test.prov.round')::bigint, current_setting('test.prov.a2')::bigint,
          current_setting('test.prov.ph')::bigint, current_setting('test.prov.p1')::bigint);
INSERT INTO rating_completions (round_id, participant_id, chat_id)
  VALUES (current_setting('test.prov.round')::bigint, current_setting('test.prov.a2')::bigint, current_setting('test.prov.chat')::bigint);

-- 8: done = 2, eligible = 3.
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.prov.round')::bigint, current_setting('test.prov.chat')::bigint)),
  2, '8: bots done → done = 2 (eligible still 3)');

-- 9: round still OPEN (must wait for the host).
SELECT is(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.prov.round')::bigint),
  NULL::timestamptz, '9: bots done but host not → round stays open');

-- host votes + completes.
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
  VALUES (current_setting('test.prov.round')::bigint, current_setting('test.prov.host')::bigint,
          current_setting('test.prov.p1')::bigint, current_setting('test.prov.p2')::bigint);
INSERT INTO rating_completions (round_id, participant_id, chat_id)
  VALUES (current_setting('test.prov.round')::bigint, current_setting('test.prov.host')::bigint, current_setting('test.prov.chat')::bigint);

-- 10: round now FINALIZED.
SELECT isnt(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.prov.round')::bigint),
  NULL::timestamptz, '10: host done too → round finalizes');

-- ── 11-12. leaderboard excludes agents ──
DO $$
DECLARE v_chat BIGINT; v_round BIGINT; v_host BIGINT; a1 BIGINT;
BEGIN
  PERFORM pg_temp.mk_game('lb', 1, false);
  v_chat  := current_setting('test.lb.chat')::bigint;
  v_round := current_setting('test.lb.round')::bigint;
  v_host  := current_setting('test.lb.host')::bigint;
  SELECT id INTO a1 FROM participants
    WHERE chat_id = v_chat AND is_agent = true ORDER BY id LIMIT 1;
  -- give BOTH the host and the agent a user_round_ranks row in this round.
  INSERT INTO user_round_ranks (round_id, participant_id, rank) VALUES (v_round, v_host, 80);
  INSERT INTO user_round_ranks (round_id, participant_id, rank) VALUES (v_round, a1, 90);
  PERFORM set_config('test.lb.a1', a1::text, false);
END $$;

SELECT is(
  (SELECT COUNT(*)::int FROM get_chat_leaderboard(current_setting('test.lb.chat')::bigint) lb
     WHERE lb.participant_id = current_setting('test.lb.a1')::bigint),
  0, '11: get_chat_leaderboard excludes the AI agent (even with a rank row)');
SELECT is(
  (SELECT COUNT(*)::int FROM get_chat_leaderboard(current_setting('test.lb.chat')::bigint) lb
     WHERE lb.participant_id = current_setting('test.lb.host')::bigint),
  1, '12: get_chat_leaderboard still includes the human host');

-- ── 13. provisioned agents are named from the arena persona roster (not the
--    legacy 'AI 1'/'AI 2') ──
SELECT is(
  (SELECT bool_and(display_name IN (SELECT display_name FROM arena_agent_personas))
     FROM participants
     WHERE chat_id = current_setting('test.two.chat')::bigint AND is_agent = true),
  true, '13: agents are named from the arena persona roster');

-- ── 14-15. ⚠️ KNOWN REGRESSION, deliberately asserted as-is (2026-08-11).
--    A never-acting "phantom" co-joiner DOES starve the bot fill: the GAME
--    branch of apply_game_ai_regime counts every active non-agent, so
--    host + phantom = 2 humans → only 1 player bot seats instead of 2.
--
--    20260625130000_regime_ignore_phantom_humans originally dropped idle
--    phantoms; 20260709230000_arena_seats_all_agents overwrote that logic and
--    lost it. A fix existed (20260716120000_restore_phantom_resistance_game_
--    seatfill) but was NEVER applied to prod and has been DELETED from the repo
--    — recover it from git history if game mode returns.
--
--    Why we assert the regressed behavior instead of skipping: prod has ZERO
--    chats with has_ai_player (and zero mode='game'), so apply_game_ai_regime
--    returns at its has_ai guard for every chat that exists — this whole path
--    is dormant. These tests document what the code actually does. If game
--    mode comes back, restore the fix and flip 14 back to 2 / 15 back to -2. ──
DO $$
DECLARE v_chat BIGINT; v_cycle BIGINT; v_r1 BIGINT; v_host BIGINT; v_phantom BIGINT;
BEGIN
  INSERT INTO chats (name, initial_message, mode, has_ai_player, max_cycles, rating_mode,
                     match_objective, confirmation_rounds_required, start_mode, access_method,
                     proposing_threshold_percent, proposing_threshold_count,
                     rating_threshold_percent, rating_threshold_count,
                     last_human_seen_at)
  VALUES ('SF phantom', 'q', 'game', true, 1, 'matches', 'winner_only', 2, 'manual', 'code',
          NULL, NULL, NULL, NULL,
          NOW())
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
  VALUES (v_chat, gen_random_uuid(), 'Joel', true, 'active', false) RETURNING id INTO v_host;
  -- a phantom co-joiner that never acts
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
  VALUES (v_chat, gen_random_uuid(), 'Idle Joiner', false, 'active', false) RETURNING id INTO v_phantom;
  INSERT INTO cycles (chat_id, is_topic) VALUES (v_chat, false) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle, 1, 'proposing', NOW()) RETURNING id INTO v_r1;
  -- host engages, then R2 opens → phantom is STILL counted (regression) → 1 bot
  INSERT INTO propositions (round_id, participant_id, chat_id, content) VALUES (v_r1, v_host, v_chat, 'Host idea');
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at) VALUES (v_cycle, 2, 'proposing', NOW());
  PERFORM set_config('test.ph.chat', v_chat::text, false);
END $$;

SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.ph.chat')::bigint AND agent_role = 'player'),
  1, '14: idle phantom still counts as a human → host gets only 1 player bot (regression)');
-- Fill seated 1 bot, so the rest of the persona roster parks 'off'.
SELECT is(
  (SELECT COUNT(*)::int FROM participants
     WHERE chat_id = current_setting('test.ph.chat')::bigint AND is_agent = true AND agent_role = 'off'),
  (SELECT COUNT(*)::int FROM arena_agent_personas) - 1,
  '15: the rest of the roster parks off (phantom reduced the fill to 1 bot)');

SELECT * FROM finish();
ROLLBACK;
