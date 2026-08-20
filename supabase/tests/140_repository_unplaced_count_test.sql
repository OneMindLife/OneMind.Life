-- =============================================================================
-- Test: repository mode primitives (Joel, 2026-07-15).
-- Migrations: 20260715073833_repository_mode_never_seals.sql
--             20260715080053_unplaced_opinion_count_rpc.sql
--             20260715131652_unplaced_count_needs_pair.sql
--   • chats.never_seals column exists, defaults false.
--   • get_unplaced_opinion_count: others' opinions this participant hasn't
--     placed (no pairwise comparison involving them); own + carried excluded;
--     isolated per participant; decremented by that participant's own votes.
--   • Placing needs a PAIR, so the count returns 0 unless >=2 unplaced remain
--     (a lone leftover / single-opinion thread can't be served by
--     pickGlobalPair — the banner must not advertise it).
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(7);

SELECT has_column('chats', 'never_seals', 'chats has never_seals column');

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Unplaced Test', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE
  v_chat INT; v_cy INT; v_r INT;
  aa INT; ab INT; ac INT; vv INT;
  pA INT; pB INT; pC INT; pD INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Unplaced Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cy, 1, 'rating') RETURNING id INTO v_r;

  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'AuthorA', 'active') RETURNING id INTO aa;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'AuthorB', 'active') RETURNING id INTO ab;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'AuthorC', 'active') RETURNING id INTO ac;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'Voter',   'active') RETURNING id INTO vv;

  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, aa, 'A') RETURNING id INTO pA;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, ab, 'B') RETURNING id INTO pB;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, ac, 'C') RETURNING id INTO pC;
  -- A carried-forward duplicate — must never be counted.
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id) VALUES (v_r, aa, 'A (carried)', pA) RETURNING id INTO pD;

  PERFORM set_config('t.r',  v_r::text,  false);
  PERFORM set_config('t.vv', vv::text,  false);
  PERFORM set_config('t.aa', aa::text,  false);
  PERFORM set_config('t.ab', ab::text,  false);
  PERFORM set_config('t.pA', pA::text,  false);
  PERFORM set_config('t.pB', pB::text,  false);
  PERFORM set_config('t.pC', pC::text,  false);
END $$;

-- Fresh chat defaults never_seals = false.
SELECT is(
  (SELECT never_seals FROM chats WHERE name = 'Unplaced Test'),
  false,
  'never_seals defaults to false on a new chat'
);

-- Voter has placed nothing → 3 others' opinions (A,B,C); carried D excluded.
SELECT is(
  get_unplaced_opinion_count(current_setting('t.r')::bigint, current_setting('t.vv')::bigint),
  3,
  'fresh voter: all 3 real opinions unplaced (carried excluded)'
);

-- Another participant's comparison must NOT change the voter's count (isolated).
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
VALUES (current_setting('t.r')::bigint, current_setting('t.ab')::bigint,
        current_setting('t.pA')::bigint, current_setting('t.pC')::bigint);
SELECT is(
  get_unplaced_opinion_count(current_setting('t.r')::bigint, current_setting('t.vv')::bigint),
  3,
  'another participant''s vote does not reduce the voter''s unplaced count'
);

-- Voter compares A vs B → both now placed by the voter → only C remains (1 raw).
-- A lone leftover can't form a fresh pair, so the count returns 0 (not 1): the
-- banner must never say "1 opinion to place" when the picker has nothing to
-- serve. This is the dead-end bug the pair requirement fixes.
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
VALUES (current_setting('t.r')::bigint, current_setting('t.vv')::bigint,
        current_setting('t.pA')::bigint, current_setting('t.pB')::bigint);
SELECT is(
  get_unplaced_opinion_count(current_setting('t.r')::bigint, current_setting('t.vv')::bigint),
  0,
  'a single leftover opinion is not placeable (needs a pair) → count is 0, not 1'
);

-- Author A: own opinion excluded → sees B and C (fresh, no A-votes) = 2 >= pair.
SELECT is(
  get_unplaced_opinion_count(current_setting('t.r')::bigint, current_setting('t.aa')::bigint),
  2,
  'own opinion is excluded; the two others still form a pair → 2'
);

-- A round holding a single opinion can NEVER be placed (no pair possible) — the
-- exact case that produced the "1 to place → no opinions to place" dead-end.
DO $$
DECLARE v_chat INT; v_cy INT; v_r1 INT; solo INT; onlooker INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Unplaced Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cy, 1, 'rating') RETURNING id INTO v_r1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'Solo', 'active') RETURNING id INTO solo;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'Onlooker', 'active') RETURNING id INTO onlooker;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, solo, 'lonely take');
  PERFORM set_config('t.r1', v_r1::text, false);
  PERFORM set_config('t.onlooker', onlooker::text, false);
END $$;

SELECT is(
  get_unplaced_opinion_count(current_setting('t.r1')::bigint, current_setting('t.onlooker')::bigint),
  0,
  'single-opinion thread: nothing to place (no pair) → 0, not 1'
);

SELECT * FROM finish();
ROLLBACK;
