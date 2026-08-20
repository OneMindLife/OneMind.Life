-- =============================================================================
-- Test: configurable scoring strategy (Joel, 2026-07-15).
-- Migration: 20260715020000_configurable_scoring_strategy.sql
--   • matches default → bradley_terry (Condorcet winner; definitive ranking
--     even with an uncontested boundary).
--   • chats.scoring_algorithm='head_to_head' switches strategy.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(5);

-- ── Fixture: X>Y, X>Z, Y>Z (transitive); the Y–Z-independent boundary is
--    contested here so both strategies agree X wins. ──────────────────────────
INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Scoring Cfg Test', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE v_chat INT; v_cy INT; v_r INT; pa INT; pb INT; pc INT; r1 INT; r2 INT; x INT; y INT; z INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'Scoring Cfg Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cy;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cy, 1, 'rating') RETURNING id INTO v_r;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'PA', 'active') RETURNING id INTO pa;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'PB', 'active') RETURNING id INTO pb;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'PC', 'active') RETURNING id INTO pc;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'R1', 'active') RETURNING id INTO r1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (v_chat, gen_random_uuid(), 'R2', 'active') RETURNING id INTO r2;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, pa, 'X') RETURNING id INTO x;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, pb, 'Y') RETURNING id INTO y;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r, pc, 'Z') RETURNING id INTO z;
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_r, pa, x, y), (v_r, r1, x, z), (v_r, r2, y, z);
  PERFORM set_config('t.chat', v_chat::text, false);
  PERFORM set_config('t.r', v_r::text, false);
  PERFORM set_config('t.x', x::text, false);
  PERFORM set_config('t.z', z::text, false);
END $$;

SELECT is(
  resolve_scoring_algorithm(current_setting('t.r')::bigint),
  'bradley_terry',
  'matches chat resolves to bradley_terry by default'
);

-- default (bradley_terry)
SELECT calculate_movda_scores_for_round(current_setting('t.r')::bigint);
SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
   WHERE round_id = current_setting('t.r')::bigint ORDER BY global_score DESC LIMIT 1),
  current_setting('t.x')::bigint,
  'BT: Condorcet winner X takes #1'
);
SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
   WHERE round_id = current_setting('t.r')::bigint ORDER BY global_score ASC LIMIT 1),
  current_setting('t.z')::bigint,
  'BT: Z (loses to all) is last'
);
SELECT is(
  (SELECT count(*)::int FROM proposition_global_scores WHERE round_id = current_setting('t.r')::bigint),
  3,
  'BT scores every played proposition (definitive ranking, no coverage gate)'
);

-- switch strategy via config → head_to_head still crowns X here
UPDATE chats SET scoring_algorithm = 'head_to_head' WHERE id = current_setting('t.chat')::bigint;
SELECT calculate_movda_scores_for_round(current_setting('t.r')::bigint);
SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
   WHERE round_id = current_setting('t.r')::bigint ORDER BY global_score DESC LIMIT 1),
  current_setting('t.x')::bigint,
  'config switch to head_to_head is honored (dispatcher routes by chats.scoring_algorithm)'
);

SELECT finish();
ROLLBACK;
