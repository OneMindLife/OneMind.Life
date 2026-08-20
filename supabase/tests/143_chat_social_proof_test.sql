-- =============================================================================
-- Test: get_chat_social_proof (Joel, 2026-07-15).
-- Migration: 20260715145954_chat_social_proof.sql
--   Cumulative human social proof {people, ideas, judgments}:
--   • people   = distinct HUMANS who proposed or voted (AI/bot excluded)
--   • ideas    = human non-carried propositions
--   • judgments = non-skip pairwise comparisons
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(4);

SELECT has_function('get_chat_social_proof', 'get_chat_social_proof exists');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Social Proof Test', '', gen_random_uuid(), 'matches');

DO $$
DECLARE
  ch INT; cyc INT; rnd INT;
  h1 INT; h2 INT; h3 INT; ai INT; bot INT;
  pA INT; pB INT;
BEGIN
  SELECT id INTO ch FROM chats WHERE name = 'Social Proof Test';
  INSERT INTO cycles (chat_id) VALUES (ch) RETURNING id INTO cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cyc, 1, 'rating') RETURNING id INTO rnd;

  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H1', 'active') RETURNING id INTO h1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H2', 'active') RETURNING id INTO h2;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H3', 'active') RETURNING id INTO h3;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'AI', 'active') RETURNING id INTO ai;
  INSERT INTO participants (chat_id, session_token, display_name, status, agent_role) VALUES (ch, gen_random_uuid(), 'Seat 1', 'active', 'proposer') RETURNING id INTO bot;

  -- Two human ideas + an AI idea + a bot idea + a carried dupe (only the 2 human count).
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, h1, 'A') RETURNING id INTO pA;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, h2, 'B') RETURNING id INTO pB;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, ai,  'C-ai');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, bot, 'D-bot');
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id) VALUES (rnd, h1, 'A (carried)', pA);

  -- Two real judgments by the two humans + one skip (skip excluded).
  INSERT INTO pairwise_comparisons (round_id, chat_id, participant_id, winner_proposition_id, loser_proposition_id, is_skip)
  VALUES (rnd, ch, h1, pA, pB, false),
         (rnd, ch, h2, pB, pA, false),
         (rnd, ch, h3, pA, pB, true);  -- h3 only skips → excluded from judgments AND from "people"

  PERFORM set_config('t.ch', ch::text, false);
END $$;

SELECT is(
  (get_chat_social_proof(current_setting('t.ch')::bigint) ->> 'people')::int,
  2,
  'people = 2 distinct humans (AI + bot excluded even though they proposed)'
);
SELECT is(
  (get_chat_social_proof(current_setting('t.ch')::bigint) ->> 'ideas')::int,
  2,
  'ideas = 2 human non-carried (AI, bot, carried excluded)'
);
SELECT is(
  (get_chat_social_proof(current_setting('t.ch')::bigint) ->> 'judgments')::int,
  2,
  'judgments = 2 non-skip comparisons (the skip is excluded)'
);

SELECT * FROM finish();
ROLLBACK;
