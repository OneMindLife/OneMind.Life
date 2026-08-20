-- =============================================================================
-- Tests for game-mode affirmer scoring — DB layer.
-- Migration: 20260624010100_affirmer_scoring_game_mode.sql
--   In GAME mode, an affirmer is scored on the carried idea's performance THIS
--   round (flat). In DECISION mode, affirmers get no proposing credit (unchanged).
-- =============================================================================
-- Setup per chat: a round 2 with
--   - a CARRIED champion prop (global_score 80, author = P_author),
--   - a NEW challenger prop  (global_score 30, author = P_challenger),
--   - an AFFIRMER (P_affirmer) backing the champion (no new prop).
-- Expected proposing ranks (normalized 0..100 across the field):
--   GAME:    affirmer scored on carried 80 -> top of field (rank 100);
--            challenger on 30 -> bottom (rank 0).
--   DECISION: affirmer absent entirely; only the challenger is ranked.
-- Coverage:
--   G1: game — affirmer is present in proposing ranks
--   G2: game — affirmer avg_score == carried champion's score (80)
--   G3: game — affirmer ranks top of field (100), challenger bottom (0)
--   D1: decision — affirmer is ABSENT from proposing ranks (unchanged)
--   D2: decision — challenger is still ranked (unchanged)
--
-- Runs inside BEGIN/ROLLBACK; calculate_proposing_ranks is SECURITY DEFINER and
-- read-only; we set up + call as postgres.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(5);

-- Builder: a chat (given mode) with a round-2 carried+new+affirmer setup.
CREATE OR REPLACE FUNCTION pg_temp.build_affirm_round(p_key TEXT, p_mode TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v_chat INT; v_cycle INT; v_r1 INT; v_r2 INT;
  v_author INT; v_chal INT; v_affirmer INT;
  v_root INT; v_carried INT; v_new INT;
  v_affirmer_uid UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES (v_affirmer_uid, 'authenticated', 'authenticated',
          '00000000-0000-0000-0000-000000000000'::UUID)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO chats (name, initial_message, creator_session_token, max_cycles,
                     confirmation_rounds_required, rating_mode, match_objective,
                     access_method, mode)
  VALUES ('Aff '||p_key, 'q', gen_random_uuid(), 1, 2, 'matches', 'full_rank', 'code', p_mode)
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'Author', TRUE, 'active') RETURNING id INTO v_author;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'Challenger', FALSE, 'active') RETURNING id INTO v_chal;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), v_affirmer_uid, 'Affirmer', FALSE, 'active')
  RETURNING id INTO v_affirmer;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;

  -- Round 1: the original champion proposition (root of the carry chain).
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating')
  RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_author, 'Champion idea') RETURNING id INTO v_root;

  -- Round 2: champion carried forward + a fresh challenger.
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 2, 'rating')
  RETURNING id INTO v_r2;
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_r2, v_author, 'Champion idea', v_root) RETURNING id INTO v_carried;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r2, v_chal, 'Challenger idea') RETURNING id INTO v_new;

  -- This-round performance: champion 80, challenger 30.
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_carried, v_r2, 80.0), (v_new, v_r2, 30.0);

  -- Affirmer backs the champion (no new prop submitted).
  INSERT INTO affirmations (round_id, participant_id, user_id, chat_id)
  VALUES (v_r2, v_affirmer, v_affirmer_uid, v_chat);

  PERFORM set_config('test.'||p_key||'.round',     v_r2::text,       false);
  PERFORM set_config('test.'||p_key||'.affirmer',  v_affirmer::text, false);
  PERFORM set_config('test.'||p_key||'.chal',      v_chal::text,     false);
END $$;

SELECT pg_temp.build_affirm_round('g', 'game');
SELECT pg_temp.build_affirm_round('d', 'decision');

-- ---------------------------------------------------------------------------
-- GAME mode
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM calculate_proposing_ranks(current_setting('test.g.round')::int)
   WHERE participant_id = current_setting('test.g.affirmer')::int),
  1,
  'G1: game — affirmer is present in proposing ranks');

SELECT is(
  (SELECT round(avg_score)::int FROM calculate_proposing_ranks(current_setting('test.g.round')::int)
   WHERE participant_id = current_setting('test.g.affirmer')::int),
  80,
  'G2: game — affirmer avg_score == carried champion score (80)');

SELECT is(
  (SELECT round(rank)::int FROM calculate_proposing_ranks(current_setting('test.g.round')::int)
   WHERE participant_id = current_setting('test.g.affirmer')::int),
  100,
  'G3: game — affirmer (backed champion) ranks top of field');

-- ---------------------------------------------------------------------------
-- DECISION mode (unchanged)
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM calculate_proposing_ranks(current_setting('test.d.round')::int)
   WHERE participant_id = current_setting('test.d.affirmer')::int),
  0,
  'D1: decision — affirmer is absent from proposing ranks (unchanged)');

SELECT is(
  (SELECT count(*)::int FROM calculate_proposing_ranks(current_setting('test.d.round')::int)
   WHERE participant_id = current_setting('test.d.chal')::int),
  1,
  'D2: decision — challenger is still ranked (unchanged)');

SELECT * FROM finish();
ROLLBACK;
