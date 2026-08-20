-- =============================================================================
-- Test: matches-mode advance gate — only ready when EVERY adjacent boundary in
-- the comparison-sort order has >= 1 vote (Joel, 2026-07-15).
-- Migration: 20260715014000_matches_advance_boundaries_voted.sql
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Boundaries Gate Test', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE
  v_chat INT; v_cy INT; v_r INT; pa INT; pb INT; pc INT; a INT; b INT; cc INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Boundaries Gate Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cy, 1, 'rating') RETURNING id INTO v_r;
  INSERT INTO participants (chat_id, session_token, display_name, status)
    VALUES (v_chat, gen_random_uuid(), 'PA', 'active') RETURNING id INTO pa;
  INSERT INTO participants (chat_id, session_token, display_name, status)
    VALUES (v_chat, gen_random_uuid(), 'PB', 'active') RETURNING id INTO pb;
  INSERT INTO participants (chat_id, session_token, display_name, status)
    VALUES (v_chat, gen_random_uuid(), 'PC', 'active') RETURNING id INTO pc;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, pa, 'A') RETURNING id INTO a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, pb, 'B') RETURNING id INTO b;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, pc, 'C') RETURNING id INTO cc;
  -- Only the A–B boundary voted; the neighbour boundary is missing a vote.
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_r, pa, a, b);
  PERFORM set_config('t.r', v_r::text, false);
END $$;

SELECT is(
  public.matches_all_boundaries_voted(current_setting('t.r')::bigint),
  false,
  'not ready while any adjacent boundary has 0 votes'
);

-- A lone skip on the missing boundary does NOT satisfy it (a skip is not a vote).
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id, is_skip)
SELECT current_setting('t.r')::bigint, p.id, x.id, y.id, true
FROM participants p, propositions x, propositions y
WHERE p.display_name = 'PB' AND x.content = 'B' AND y.content = 'C'
  AND x.round_id = current_setting('t.r')::bigint AND y.round_id = current_setting('t.r')::bigint
LIMIT 1;

SELECT is(
  public.matches_all_boundaries_voted(current_setting('t.r')::bigint),
  false,
  'a skip does not count as a vote on the boundary'
);

-- Now a real vote on the remaining boundary(ies) → ready.
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
SELECT current_setting('t.r')::bigint, p.id, x.id, y.id
FROM participants p, propositions x, propositions y
WHERE p.display_name = 'PC' AND x.content = 'B' AND y.content = 'C'
  AND x.round_id = current_setting('t.r')::bigint AND y.round_id = current_setting('t.r')::bigint
LIMIT 1;
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
SELECT current_setting('t.r')::bigint, p.id, x.id, y.id
FROM participants p, propositions x, propositions y
WHERE p.display_name = 'PC' AND x.content = 'A' AND y.content = 'C'
  AND x.round_id = current_setting('t.r')::bigint AND y.round_id = current_setting('t.r')::bigint
LIMIT 1;

SELECT is(
  public.matches_all_boundaries_voted(current_setting('t.r')::bigint),
  true,
  'ready once every adjacent boundary has a real vote'
);

SELECT finish();
ROLLBACK;
