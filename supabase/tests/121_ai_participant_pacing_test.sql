-- AI game participant pacing (seat-fill model, docs/SOLO_GAME_AI_FILL_SPEC.md).
--
-- A seat-fill 'player' bot's always-on challenger must NOT trip the "everyone
-- responded" gate prematurely (it is counted in the denominator alongside the
-- humans), but DOES force the round to rating (no free unchallenged convergence
-- while a bot is pushing an alternative).
--
-- NB: rewritten 2026-06-25. The old version used mode='game' WITHOUT
-- has_ai_player and a hand-pinned is_agent participant (role 'off') — a config
-- that no longer occurs: wedge always sets has_ai_player=true for games, so the
-- regime selector assigns real roles. Here a 2-human FILL round gives AI 1 the
-- 'player' role, so v_active = 2 humans + 1 player bot = 3.
BEGIN;
SELECT plan(3);

DO $$
DECLARE
  v_chat bigint; v_cycle bigint; v_round bigint; v_r1 bigint;
  v_h1 bigint; v_h2 bigint; v_ai bigint;
  v_root bigint; v_leader bigint;
BEGIN
  -- A quick game chat WITH the AI player (has_ai_player → trigger provisions the
  -- persona-named agent roster). NULL thresholds so only the backend
  -- auto-advance trigger drives R2+ proposing.
  -- last_human_seen_at = NOW() keeps the room "warm": the regime selector's
  -- pause-when-empty cold gate (apply_game_ai_regime, 20260709220000) parks all
  -- agents 'off' when no human has been seen in ~2min. A fresh fixture has no
  -- activity, so without this the FILL bot never gets seated.
  INSERT INTO chats (name, initial_message, mode, has_ai_player, max_cycles,
                     rating_mode, match_objective, confirmation_rounds_required,
                     start_mode, proposing_threshold_count, proposing_threshold_percent,
                     rating_threshold_count, rating_threshold_percent,
                     last_human_seen_at)
  VALUES ('ai game', 'q', 'game', true, 1, 'matches', 'winner_only', 2, 'manual',
          NULL, NULL, NULL, NULL,
          NOW())
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
  VALUES (v_chat, gen_random_uuid(), 'H1', true,  'active', false) RETURNING id INTO v_h1;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
  VALUES (v_chat, gen_random_uuid(), 'H2', false, 'active', false) RETURNING id INTO v_h2;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  -- R1 (done) holds the root winner that R2 carries forward.
  INSERT INTO rounds (cycle_id, custom_id, phase, completed_at)
  VALUES (v_cycle, 1, 'rating', NOW()) RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_h1, 'Root leader') RETURNING id INTO v_root;
  -- H2 also played round 1 (so both humans count as engaged — the regime
  -- selector's phantom filter, 20260625130000, ignores humans who never act).
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_h2, 'H2 round-1 idea');
  -- R2 proposing with the carried leader. Opening it fires the regime selector:
  -- 2 engaged humans → FILL → exactly one agent seated as 'player' (a voter),
  -- the rest 'off'.
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle, 2, 'proposing', NOW()) RETURNING id INTO v_round;
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round, v_h1, 'Carried leader', v_root) RETURNING id INTO v_leader;

  -- The FILL bot is now persona-named (arena_agent_personas, 20260709210000),
  -- not 'AI 1'. Look it up by the role the selector actually assigned.
  SELECT id INTO v_ai FROM participants
   WHERE chat_id = v_chat AND is_agent = true AND agent_role = 'player';

  PERFORM set_config('test.chat', v_chat::text, false);
  PERFORM set_config('test.round', v_round::text, false);
  PERFORM set_config('test.ai', v_ai::text, false);
  PERFORM set_config('test.h1', v_h1::text, false);
  PERFORM set_config('test.h2', v_h2::text, false);
END $$;

-- The player bot proposes its alternative (fires the trigger). v_active = 3
-- (2 humans + the player bot); only the bot has responded → stays proposing.
INSERT INTO propositions (round_id, participant_id, content)
VALUES (current_setting('test.round')::bigint, current_setting('test.ai')::bigint, 'AI alternative');

SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round')::bigint),
  'proposing', 'A: bot challenger alone does NOT advance the round (humans pace)');

-- One human keeps the leader (affirm). bot + 1 human = 2 of 3 → still proposing.
INSERT INTO affirmations (round_id, participant_id, user_id, chat_id)
VALUES (current_setting('test.round')::bigint, current_setting('test.h1')::bigint, gen_random_uuid(), current_setting('test.chat')::bigint);

SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round')::bigint),
  'proposing', 'B: bot + 1 human (2 of 3) still below the gate → stays proposing');

-- Second human keeps the leader. Now all three present have responded → gate
-- met. The bot's challenger means there IS something to vote on → opens RATING.
INSERT INTO affirmations (round_id, participant_id, user_id, chat_id)
VALUES (current_setting('test.round')::bigint, current_setting('test.h2')::bigint, gen_random_uuid(), current_setting('test.chat')::bigint);

SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.round')::bigint),
  'rating', 'C: all responded, but the bot alternative forces a vote → rating');

SELECT * FROM finish();
ROLLBACK;
