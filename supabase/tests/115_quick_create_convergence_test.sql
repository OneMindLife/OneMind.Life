-- =============================================================================
-- Tests for quick-create CONVERGENCE — DB layer.
--
-- Quick chats now default to confirmation_rounds_required = 2 (convergence) while
-- staying max_cycles = 1 (sealed single-use loop). This pins the behaviour of the
-- convergence engine under that *capped* config — the new surface created by the
-- 2026-06-07 default flip (quick_create_screen.dart: confirmationRoundsRequired 1->2):
--
--   E1: a round-1 sole win does NOT seal the chat. It finalizes round 1 (the
--       winner is "delivered" — shown as Current Leader) and creates round 2,
--       which auto-enters proposing (per 20260605181444) with the winner carried
--       forward. So a group that just wanted the answer has it; round 2 is upside.
--   E2: a 2nd consecutive same-ROOT sole win reaches consensus -> the cycle
--       completes -> the capped (max_cycles=1) chat ends. No round 3.
--   E3: a DIFFERENT winner in round 2 resets the streak -> round 3 is created;
--       the chat does NOT seal (convergence keeps going).
--
-- Convergence trigger under test: on_round_winner_set (BEFORE UPDATE OF
-- winning_proposition_id ON rounds) — counts consecutive sole wins of the same
-- root, completes the cycle at >= confirmation_rounds_required, else creates the
-- next round and carries the rank-1 winner forward.
--
-- Behaviour verified against the live prod schema (2026-06-07) via rollback
-- simulation before being encoded here. Runs inside BEGIN/ROLLBACK; prod data is
-- untouched. We drive the trigger as postgres by inserting the round_winners
-- rank-1 row (so carry-forward has a source) then UPDATEing
-- rounds.winning_proposition_id — the same path complete_round_with_winner takes.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- Builder: a CONVERGENCE (confirmation_rounds_required = 2) + capped
-- (max_cycles = 1) matches quick chat with a cycle, a round 1 in rating, and two
-- ownerless options. Stashes ids in test.c.<key>.* settings.
CREATE OR REPLACE FUNCTION pg_temp.build_conv_chat(p_key TEXT, p_name TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_chat INT; v_cycle INT; v_round INT; v_a INT; v_b INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, is_preview,
                     max_cycles, confirmation_rounds_required, rating_mode,
                     match_objective, access_method)
  VALUES (p_name, 'Q', gen_random_uuid(), FALSE, 1, 2, 'matches', 'full_rank', 'code')
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'Host', TRUE, 'active');
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle, 1, 'rating', NOW()) RETURNING id INTO v_round;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round, NULL, 'Option A') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round, NULL, 'Option B') RETURNING id INTO v_b;
  PERFORM set_config('test.c.'||p_key||'.chat',  v_chat::TEXT,  FALSE);
  PERFORM set_config('test.c.'||p_key||'.cycle', v_cycle::TEXT, FALSE);
  PERFORM set_config('test.c.'||p_key||'.r1',    v_round::TEXT, FALSE);
  PERFORM set_config('test.c.'||p_key||'.a',     v_a::TEXT,     FALSE);
  PERFORM set_config('test.c.'||p_key||'.b',     v_b::TEXT,     FALSE);
END $$;

-- Helper: declare proposition p_prop the sole rank-1 winner of round p_round,
-- firing the convergence trigger (round_winners row first for carry-forward).
CREATE OR REPLACE FUNCTION pg_temp.win_round(p_round BIGINT, p_prop BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (p_round, p_prop, 1);
  UPDATE rounds SET winning_proposition_id = p_prop, is_sole_winner = TRUE WHERE id = p_round;
END $$;

-- =============================================================================
-- E1: round-1 sole win does NOT seal a conf=2 capped chat — round 2 is created.
-- =============================================================================
SELECT pg_temp.build_conv_chat('e1', 'C E1 round1 no-seal');
SELECT pg_temp.win_round(current_setting('test.c.e1.r1')::INT, current_setting('test.c.e1.a')::INT);

SELECT ok((SELECT ended_at IS NULL FROM chats WHERE id = current_setting('test.c.e1.chat')::INT),
  'E1a: a round-1 win does NOT end the capped conf=2 chat');
SELECT ok((SELECT completed_at IS NULL FROM cycles WHERE id = current_setting('test.c.e1.cycle')::INT),
  'E1b: ...the cycle is NOT completed');
SELECT is((SELECT COUNT(*)::INT FROM rounds WHERE cycle_id = current_setting('test.c.e1.cycle')::INT), 2,
  'E1c: a round 2 was created');
SELECT ok((SELECT completed_at IS NOT NULL FROM rounds WHERE id = current_setting('test.c.e1.r1')::INT),
  'E1d: round 1 itself is finalized (the winner is delivered)');
SELECT is((SELECT phase FROM rounds WHERE cycle_id = current_setting('test.c.e1.cycle')::INT AND custom_id = 2),
  'proposing',
  'E1e: round 2 auto-enters proposing (no host Start tap needed)');
SELECT is((SELECT COUNT(*)::INT FROM propositions p JOIN rounds r ON r.id = p.round_id
            WHERE r.cycle_id = current_setting('test.c.e1.cycle')::INT AND r.custom_id = 2
              AND p.carried_from_id IS NOT NULL), 1,
  'E1f: the round-1 winner is carried forward into round 2');

-- =============================================================================
-- E2: a 2nd consecutive same-root win reaches consensus -> cycle completes ->
-- the capped chat ends, with NO round 3.
-- =============================================================================
SELECT pg_temp.build_conv_chat('e2', 'C E2 converge');
SELECT pg_temp.win_round(current_setting('test.c.e2.r1')::INT, current_setting('test.c.e2.a')::INT);
-- round 2 exists in proposing with A carried; flip it to rating and win it with
-- the carried (same-root) proposition.
UPDATE rounds SET phase = 'rating'
  WHERE cycle_id = current_setting('test.c.e2.cycle')::INT AND custom_id = 2;
SELECT pg_temp.win_round(
  (SELECT id FROM rounds WHERE cycle_id = current_setting('test.c.e2.cycle')::INT AND custom_id = 2),
  (SELECT p.id FROM propositions p JOIN rounds r ON r.id = p.round_id
     WHERE r.cycle_id = current_setting('test.c.e2.cycle')::INT AND r.custom_id = 2
       AND p.carried_from_id IS NOT NULL LIMIT 1));

SELECT ok((SELECT ended_at IS NOT NULL FROM chats WHERE id = current_setting('test.c.e2.chat')::INT),
  'E2a: 2 consecutive same-root wins end the capped chat');
SELECT ok((SELECT completed_at IS NOT NULL FROM cycles WHERE id = current_setting('test.c.e2.cycle')::INT),
  'E2b: ...the cycle completes');
SELECT ok((SELECT winning_proposition_id IS NOT NULL FROM cycles WHERE id = current_setting('test.c.e2.cycle')::INT),
  'E2c: ...the cycle winner is recorded');
SELECT is((SELECT COUNT(*)::INT FROM rounds WHERE cycle_id = current_setting('test.c.e2.cycle')::INT), 2,
  'E2d: no round 3 is created after convergence');

-- =============================================================================
-- E3: a DIFFERENT winner in round 2 resets the streak -> round 3, no seal.
-- =============================================================================
SELECT pg_temp.build_conv_chat('e3', 'C E3 keep going');
SELECT pg_temp.win_round(current_setting('test.c.e3.r1')::INT, current_setting('test.c.e3.a')::INT);
UPDATE rounds SET phase = 'rating'
  WHERE cycle_id = current_setting('test.c.e3.cycle')::INT AND custom_id = 2;
-- a fresh, different proposition (new root) wins round 2.
DO $$
DECLARE v_r2 INT; v_new INT;
BEGIN
  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = current_setting('test.c.e3.cycle')::INT AND custom_id = 2;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r2, NULL, 'Fresh challenger') RETURNING id INTO v_new;
  PERFORM pg_temp.win_round(v_r2, v_new);
END $$;

SELECT ok((SELECT ended_at IS NULL FROM chats WHERE id = current_setting('test.c.e3.chat')::INT),
  'E3a: a different round-2 winner does NOT seal the chat');
SELECT is((SELECT COUNT(*)::INT FROM rounds WHERE cycle_id = current_setting('test.c.e3.cycle')::INT), 3,
  'E3b: ...a round 3 is created (streak reset, convergence continues)');

SELECT * FROM finish();
ROLLBACK;
