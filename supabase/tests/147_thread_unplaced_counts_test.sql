-- =============================================================================
-- Test: get_thread_unplaced_counts (Joel, 2026-07-15).
-- Migration: 20260715183531_thread_unplaced_counts.sql
--   For each proposition in a round, the count of PLACEABLE opinions (others',
--   unpaired by this participant, >=2) inside its child thread. Powers the
--   per-option "N to vote inside" attention badge. Threads with <2 placeable,
--   or no thread, are absent.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(5);

SELECT has_function('get_thread_unplaced_counts', 'get_thread_unplaced_counts exists');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Unplaced Counts Test', '', gen_random_uuid(), 'matches');

DO $$
DECLARE
  ch INT; root_cyc INT; root_r INT;
  viewer INT; h2 INT; h3 INT; h4 INT; ai INT;
  pA INT; pB INT; pC INT;
  aCyc INT; aR INT; cCyc INT; cR INT;
  a1 INT;
BEGIN
  SELECT id INTO ch FROM chats WHERE name = 'Unplaced Counts Test';
  INSERT INTO cycles (chat_id) VALUES (ch) RETURNING id INTO root_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (root_cyc, 1, 'rating') RETURNING id INTO root_r;

  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'Viewer', 'active') RETURNING id INTO viewer;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H2', 'active') RETURNING id INTO h2;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H3', 'active') RETURNING id INTO h3;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H4', 'active') RETURNING id INTO h4;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'AI', 'active') RETURNING id INTO ai;

  -- Three root opinions: pA has a rich thread, pB has none, pC has a thin thread.
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, viewer, 'A') RETURNING id INTO pA;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h2, 'B') RETURNING id INTO pB;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h3, 'C') RETURNING id INTO pC;

  -- pA's thread: 3 OTHERS (h2, h3, h4) + viewer's OWN (excluded) + a carried
  -- dupe (excluded). One new prop per participant per round, so the others must
  -- be distinct people. The viewer has paired NONE yet → 3 placeable.
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (ch, pA) RETURNING id INTO aCyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (aCyc, 1, 'rating') RETURNING id INTO aR;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (aR, h2, 'a-reply 1') RETURNING id INTO a1;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (aR, h3, 'a-reply 2');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (aR, h4, 'a-reply 3');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (aR, viewer, 'a-own');   -- own → excluded
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (aR, h3, 'a-carried', a1);                                                          -- carried → excluded

  -- pC's thread: exactly ONE other opinion → below the pair floor → omitted.
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (ch, pC) RETURNING id INTO cCyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cCyc, 1, 'rating') RETURNING id INTO cR;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (cR, h2, 'c-lonely');

  PERFORM set_config('t.rr', root_r::text, false);
  PERFORM set_config('t.viewer', viewer::text, false);
  PERFORM set_config('t.pA', pA::text, false);
  PERFORM set_config('t.pB', pB::text, false);
  PERFORM set_config('t.pC', pC::text, false);
  PERFORM set_config('t.aR', aR::text, false);
  PERFORM set_config('t.a1', a1::text, false);
END $$;

SELECT is(
  (SELECT unplaced FROM get_thread_unplaced_counts(
     current_setting('t.rr')::bigint, current_setting('t.viewer')::bigint)
   WHERE proposition_id = current_setting('t.pA')::bigint),
  3::bigint,
  'idea A: 3 placeable in its thread (own + carried excluded, none paired yet)'
);

SELECT ok(
  NOT EXISTS (SELECT 1 FROM get_thread_unplaced_counts(
     current_setting('t.rr')::bigint, current_setting('t.viewer')::bigint)
   WHERE proposition_id = current_setting('t.pB')::bigint),
  'idea B has no thread → absent'
);

SELECT ok(
  NOT EXISTS (SELECT 1 FROM get_thread_unplaced_counts(
     current_setting('t.rr')::bigint, current_setting('t.viewer')::bigint)
   WHERE proposition_id = current_setting('t.pC')::bigint),
  'idea C thread has only 1 other → below pair floor → absent'
);

-- The viewer judges one pair in A's thread — a single comparison marks BOTH
-- props seen, so 2 of the 3 drop out and only 1 unpaired remains. A fresh pair
-- can't be formed from 1 (pickGlobalPair needs 2), so A falls below the floor
-- and drops off the badge list entirely.
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
SELECT current_setting('t.aR')::bigint, current_setting('t.viewer')::bigint,
       current_setting('t.a1')::bigint,
       (SELECT id FROM propositions WHERE round_id = current_setting('t.aR')::bigint AND content = 'a-reply 2');

SELECT ok(
  NOT EXISTS (SELECT 1 FROM get_thread_unplaced_counts(
     current_setting('t.rr')::bigint, current_setting('t.viewer')::bigint)
   WHERE proposition_id = current_setting('t.pA')::bigint),
  'after the viewer judges one pair (2 of 3 seen), A drops below the pair floor → absent'
);

SELECT * FROM finish();
ROLLBACK;
