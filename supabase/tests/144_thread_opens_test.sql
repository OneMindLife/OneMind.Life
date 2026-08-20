-- =============================================================================
-- Test: thread-open tracking (Joel, 2026-07-15).
-- Migration: 20260715151541_proposition_thread_opens.sql
--   record_thread_open: idempotent per (proposition, participant).
--   get_round_open_counts: DISTINCT openers per idea in a round.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(4);

SELECT has_function('record_thread_open', 'record_thread_open exists');
SELECT has_function('get_round_open_counts', 'get_round_open_counts exists');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Opens Test', '', gen_random_uuid(), 'matches');

DO $$
DECLARE ch INT; cyc INT; rnd INT; h1 INT; h2 INT; pA INT; pB INT;
BEGIN
  SELECT id INTO ch FROM chats WHERE name = 'Opens Test';
  INSERT INTO cycles (chat_id) VALUES (ch) RETURNING id INTO cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cyc, 1, 'rating') RETURNING id INTO rnd;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H1', 'active') RETURNING id INTO h1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H2', 'active') RETURNING id INTO h2;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, h1, 'A') RETURNING id INTO pA;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rnd, h2, 'B') RETURNING id INTO pB;

  PERFORM record_thread_open(pA, h1);
  PERFORM record_thread_open(pA, h2);
  PERFORM record_thread_open(pA, h1);  -- duplicate — must be deduped
  PERFORM record_thread_open(pB, h1);

  PERFORM set_config('t.rnd', rnd::text, false);
  PERFORM set_config('t.pA', pA::text, false);
  PERFORM set_config('t.pB', pB::text, false);
END $$;

SELECT is(
  (SELECT opens FROM get_round_open_counts(current_setting('t.rnd')::bigint)
   WHERE proposition_id = current_setting('t.pA')::bigint),
  2::bigint,
  'idea A: 2 distinct openers (the duplicate open is deduped)'
);
SELECT is(
  (SELECT opens FROM get_round_open_counts(current_setting('t.rnd')::bigint)
   WHERE proposition_id = current_setting('t.pB')::bigint),
  1::bigint,
  'idea B: 1 opener'
);

SELECT * FROM finish();
ROLLBACK;
