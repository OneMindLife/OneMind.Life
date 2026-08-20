-- =============================================================================
-- Test: get_thread_reply_counts (Joel, 2026-07-15).
-- Migrations: 20260715173914_thread_reply_counts.sql
--             20260715201202_thread_reply_counts_include_ai.sql
--   For each proposition in a round, the count of ALL replies in its thread
--   (child cycle) — human AND AI, matching the list shown when the thread opens.
--   Carried excluded; props with no thread are absent.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

SELECT has_function('get_thread_reply_counts', 'get_thread_reply_counts exists');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Reply Counts Test', '', gen_random_uuid(), 'matches');

DO $$
DECLARE
  ch INT; root_cyc INT; root_r INT; child_cyc INT; child_r INT;
  h1 INT; h2 INT; h3 INT; ai INT;
  pA INT; pB INT;
BEGIN
  SELECT id INTO ch FROM chats WHERE name = 'Reply Counts Test';
  INSERT INTO cycles (chat_id) VALUES (ch) RETURNING id INTO root_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (root_cyc, 1, 'rating') RETURNING id INTO root_r;

  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H1', 'active') RETURNING id INTO h1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H2', 'active') RETURNING id INTO h2;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H3', 'active') RETURNING id INTO h3;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'AI', 'active') RETURNING id INTO ai;

  -- Two root opinions. Only pA has a thread.
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h1, 'A') RETURNING id INTO pA;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h2, 'B') RETURNING id INTO pB;

  -- pA's thread: 2 human replies + 1 AI (excluded) + a carried dupe (excluded).
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (ch, pA) RETURNING id INTO child_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (child_cyc, 1, 'proposing') RETURNING id INTO child_r;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (child_r, h2, 'reply 1');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (child_r, h3, 'reply 2');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (child_r, ai, 'ai reply');
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (child_r, h2, 'carried', (SELECT id FROM propositions WHERE round_id=child_r AND content='reply 1'));

  PERFORM set_config('t.rr', root_r::text, false);
  PERFORM set_config('t.pA', pA::text, false);
  PERFORM set_config('t.pB', pB::text, false);
END $$;

SELECT is(
  (SELECT replies FROM get_thread_reply_counts(current_setting('t.rr')::bigint)
   WHERE proposition_id = current_setting('t.pA')::bigint),
  3::bigint,
  'idea A: 3 replies in its thread (2 human + 1 AI; carried excluded)'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM get_thread_reply_counts(current_setting('t.rr')::bigint)
             WHERE proposition_id = current_setting('t.pB')::bigint),
  'idea B has no thread → absent from the result'
);

SELECT * FROM finish();
ROLLBACK;
