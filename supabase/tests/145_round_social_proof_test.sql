-- =============================================================================
-- Test: get_round_social_proof (Joel, 2026-07-15).
-- Migration: 20260715160729_round_social_proof.sql
--   Per-level {opinions, votes} for ONE round: human non-carried opinions +
--   non-skip votes; AI/bot and other rounds excluded.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

SELECT has_function('get_round_social_proof', 'get_round_social_proof exists');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Round Proof Test', '', gen_random_uuid(), 'matches');

DO $$
DECLARE
  ch INT; cyc INT; rnd INT; other_rnd INT;
  h1 INT; h2 INT; h3 INT; ai INT;
  pA INT; pB INT;
BEGIN
  SELECT id INTO ch FROM chats WHERE name = 'Round Proof Test';
  INSERT INTO cycles (chat_id) VALUES (ch) RETURNING id INTO cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cyc, 1, 'rating') RETURNING id INTO rnd;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cyc, 2, 'rating') RETURNING id INTO other_rnd;

  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H1', 'active') RETURNING id INTO h1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H2', 'active') RETURNING id INTO h2;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H3', 'active') RETURNING id INTO h3;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'AI', 'active') RETURNING id INTO ai;

  -- Round rnd: 2 human opinions (counted) + AI (excluded) + carried (excluded).
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, h1, 'A') RETURNING id INTO pA;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, h2, 'B') RETURNING id INTO pB;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, ai, 'C-ai');
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id) VALUES (rnd, h1, 'A (carried)', pA);
  -- Another round's opinion — must NOT be counted for rnd.
  INSERT INTO propositions (round_id, participant_id, content) VALUES (other_rnd, h2, 'other-round');

  -- 1 real vote + 1 skip (skip excluded).
  INSERT INTO pairwise_comparisons (round_id, chat_id, participant_id, winner_proposition_id, loser_proposition_id, is_skip)
  VALUES (rnd, ch, h1, pA, pB, false),
         (rnd, ch, h3, pA, pB, true);

  PERFORM set_config('t.rnd', rnd::text, false);
END $$;

SELECT is(
  (get_round_social_proof(current_setting('t.rnd')::bigint) ->> 'opinions')::int,
  2,
  'opinions = 2 human non-carried in this round (AI, carried, other round excluded)'
);
SELECT is(
  (get_round_social_proof(current_setting('t.rnd')::bigint) ->> 'votes')::int,
  1,
  'votes = 1 non-skip comparison in this round (skip excluded)'
);

SELECT * FROM finish();
ROLLBACK;
