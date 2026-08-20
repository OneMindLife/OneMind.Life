-- =============================================================================
-- Tests for quick-create finalize mechanics — DB layer.
-- Migrations:
--   20260530180000_matches_preview_auto_finalize.sql (matches_preview_maybe_finalize
--                    trigger: PREVIEW matches rounds auto-finalize when done >= eligible)
--   20260530181000_host_end_voting.sql               (host_end_voting RPC)
--   20260530182000_seed_no_timer_option.sql          (NULL duration => no timer)
-- =============================================================================
-- Coverage:
--   A. Preview auto-finalize trigger
--      A1/A2: solo matches PREVIEW — one completion finalizes the round AND ends the chat.
--      A3:    2-eligible preview — one completion does NOT finalize (done 1 < eligible 2).
--      A4:    ...the second completion DOES finalize (done 2 >= 2).
--      A5:    skip path — a rating_skips row also drives the finalize.
--      A6:    REAL chat (is_preview=false) — completion does NOT finalize (preview-scoped).
--      A7:    GRID preview — a rating_completions row does NOT finalize (matches-scoped).
--   B. host_end_voting
--      B1/B2: host ends rating → round completed AND chat ended.
--      B3:    non-host caller throws.
--      B4:    proposing phase throws.
--      B5:    non-quick-create chat (max_cycles NULL) throws.
--      B6:    already-completed round → idempotent success (no throw).
--   C. seed no-timer
--      C1: NULL duration => phase_ends_at IS NULL.
--      C2: numeric duration => phase_ends_at IS NOT NULL.
--
-- complete_round_with_winner falls back to the first proposition when there are no
-- scores, so a finalize always sets rounds.completed_at — no rating data needed.
-- Trigger fires under any role (SECURITY DEFINER); we insert as postgres.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(18);

-- Auth users for the host_end_voting authz tests.
INSERT INTO auth.users (id, aud, role, instance_id)
VALUES
  ('00000000-0000-0000-0000-0000000000d1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
  ('00000000-0000-0000-0000-0000000000d2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
ON CONFLICT (id) DO NOTHING;

-- Reusable builder: a matches chat with a cycle + rating round + 2 ownerless options.
-- Returns nothing; stashes ids in test.* settings keyed by p_key.
CREATE OR REPLACE FUNCTION pg_temp.build_matches_round(
  p_key TEXT, p_name TEXT, p_is_preview BOOLEAN, p_max_cycles INTEGER,
  p_rating_mode TEXT DEFAULT 'matches', p_phase TEXT DEFAULT 'rating',
  p_host_uid UUID DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_chat INT; v_cycle INT; v_round INT; v_host INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, is_preview,
                     max_cycles, confirmation_rounds_required, rating_mode,
                     match_objective, access_method)
  VALUES (p_name, 'Q', gen_random_uuid(), p_is_preview, p_max_cycles, 1,
          p_rating_mode, 'full_rank', 'code')
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), p_host_uid, 'Host', TRUE, 'active')
  RETURNING id INTO v_host;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle, 1, p_phase, NOW()) RETURNING id INTO v_round;
  INSERT INTO propositions (round_id, participant_id, content) VALUES
    (v_round, NULL, 'Option A'), (v_round, NULL, 'Option B');

  PERFORM set_config('test.f.'||p_key||'.chat',  v_chat::TEXT,  FALSE);
  PERFORM set_config('test.f.'||p_key||'.round', v_round::TEXT, FALSE);
  PERFORM set_config('test.f.'||p_key||'.host',  v_host::TEXT,  FALSE);
END $$;

-- =============================================================================
-- A1/A2: solo matches PREVIEW — one completion finalizes the round AND ends chat.
-- =============================================================================
SELECT pg_temp.build_matches_round('a1', 'F A1 solo preview', TRUE, 1);
INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.f.a1.round')::INT, current_setting('test.f.a1.host')::INT);

SELECT ok(
  (SELECT completed_at IS NOT NULL FROM rounds WHERE id = current_setting('test.f.a1.round')::INT),
  'A1: solo matches preview finalizes the round on the host''s completion');
SELECT ok(
  (SELECT ended_at IS NOT NULL FROM chats WHERE id = current_setting('test.f.a1.chat')::INT),
  'A2: ...and the capped (max_cycles=1) chat ends');

-- =============================================================================
-- A3/A4: 2-eligible preview — first completion no-op, second finalizes.
-- =============================================================================
SELECT pg_temp.build_matches_round('a3', 'F A3 two-rater preview', TRUE, 1);
INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
VALUES (current_setting('test.f.a3.chat')::INT, gen_random_uuid(), 'Rater2', FALSE, 'active');

INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.f.a3.round')::INT, current_setting('test.f.a3.host')::INT);
SELECT ok(
  (SELECT completed_at IS NULL FROM rounds WHERE id = current_setting('test.f.a3.round')::INT),
  'A3: one of two raters done → round NOT finalized (done 1 < eligible 2)');

INSERT INTO rating_completions (round_id, participant_id)
SELECT current_setting('test.f.a3.round')::INT, id
FROM participants WHERE chat_id = current_setting('test.f.a3.chat')::INT AND is_host = FALSE;
SELECT ok(
  (SELECT completed_at IS NOT NULL FROM rounds WHERE id = current_setting('test.f.a3.round')::INT),
  'A4: both raters done → round finalized (done 2 >= eligible 2)');

-- =============================================================================
-- A5: skip path — a rating_skips row drives the finalize too (solo preview).
-- =============================================================================
SELECT pg_temp.build_matches_round('a5', 'F A5 skip preview', TRUE, 1);
INSERT INTO rating_skips (round_id, participant_id)
VALUES (current_setting('test.f.a5.round')::INT, current_setting('test.f.a5.host')::INT);
SELECT ok(
  (SELECT completed_at IS NOT NULL FROM rounds WHERE id = current_setting('test.f.a5.round')::INT),
  'A5: a rating_skips row finalizes a solo matches preview');

-- =============================================================================
-- A6: REAL chat (is_preview=false) — completion does NOT finalize (preview-scoped).
-- =============================================================================
SELECT pg_temp.build_matches_round('a6', 'F A6 real chat', FALSE, 1);
INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.f.a6.round')::INT, current_setting('test.f.a6.host')::INT);
SELECT ok(
  (SELECT completed_at IS NULL FROM rounds WHERE id = current_setting('test.f.a6.round')::INT),
  'A6: a REAL chat is NOT auto-finalized by the trigger (it uses host_end_voting)');

-- =============================================================================
-- A7: GRID preview — a rating_completions row does NOT finalize (matches-scoped).
-- =============================================================================
SELECT pg_temp.build_matches_round('a7', 'F A7 grid preview', TRUE, 1, 'grid');
INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.f.a7.round')::INT, current_setting('test.f.a7.host')::INT);
SELECT ok(
  (SELECT completed_at IS NULL FROM rounds WHERE id = current_setting('test.f.a7.round')::INT),
  'A7: a GRID-mode preview is NOT finalized by the matches trigger');

-- =============================================================================
-- B1/B2: host_end_voting — host ends rating → round completed AND chat ended.
-- =============================================================================
SELECT pg_temp.build_matches_round('b1', 'F B1 host end', FALSE, 1, 'matches', 'rating',
  '00000000-0000-0000-0000-0000000000d1'::UUID);

SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000d1')::TEXT, TRUE);
SELECT lives_ok(
  format('SELECT host_end_voting(%s)', current_setting('test.f.b1.chat')),
  'B1a: host can end voting');
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT ok(
  (SELECT completed_at IS NOT NULL FROM rounds WHERE id = current_setting('test.f.b1.round')::INT),
  'B1: host_end_voting finalizes the rating round');
SELECT ok(
  (SELECT ended_at IS NOT NULL FROM chats WHERE id = current_setting('test.f.b1.chat')::INT),
  'B2: ...and the capped chat ends');

-- =============================================================================
-- B3: non-host caller throws.
-- =============================================================================
SELECT pg_temp.build_matches_round('b3', 'F B3 nonhost', FALSE, 1, 'matches', 'rating',
  '00000000-0000-0000-0000-0000000000d1'::UUID);
-- d2 is an auth user but NOT a participant of this chat.
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000d2')::TEXT, TRUE);
SELECT throws_ok(
  format('SELECT host_end_voting(%s)', current_setting('test.f.b3.chat')),
  NULL, 'B3: a non-host caller throws');
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- =============================================================================
-- B4: proposing phase throws.
-- =============================================================================
SELECT pg_temp.build_matches_round('b4', 'F B4 proposing', FALSE, 1, 'matches', 'proposing',
  '00000000-0000-0000-0000-0000000000d1'::UUID);
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000d1')::TEXT, TRUE);
SELECT throws_ok(
  format('SELECT host_end_voting(%s)', current_setting('test.f.b4.chat')),
  NULL, 'B4: ending voting during proposing throws');
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- =============================================================================
-- B5: non-quick-create chat (max_cycles NULL) throws.
-- =============================================================================
SELECT pg_temp.build_matches_round('b5', 'F B5 uncapped', FALSE, NULL, 'matches', 'rating',
  '00000000-0000-0000-0000-0000000000d1'::UUID);
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000d1')::TEXT, TRUE);
SELECT throws_ok(
  format('SELECT host_end_voting(%s)', current_setting('test.f.b5.chat')),
  NULL, 'B5: host_end_voting on a non-quick-create chat (max_cycles NULL) throws');
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- =============================================================================
-- B6: already-completed round → idempotent (lives_ok, returns already_completed).
-- Reuse b1's now-completed chat/round.
-- =============================================================================
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000d1')::TEXT, TRUE);
SELECT lives_ok(
  format('SELECT host_end_voting(%s)', current_setting('test.f.b1.chat')),
  'B6: host_end_voting is idempotent on an already-finalized chat');
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- =============================================================================
-- C1/C2: seed no-timer.
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token, is_preview, max_cycles,
                   confirmation_rounds_required, rating_mode, match_objective, access_method)
VALUES ('F C seed', 'Q', gen_random_uuid(), FALSE, 1, 1, 'matches', 'full_rank', 'code');
DO $$
DECLARE v_chat INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'F C seed';
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000d1'::UUID, 'Host', TRUE, 'active');
  PERFORM set_config('test.f.cseed.chat', v_chat::TEXT, FALSE);
END $$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000d1')::TEXT, TRUE);
SELECT seed_prioritization_round(current_setting('test.f.cseed.chat')::INT,
  ARRAY['X','Y','Z']::TEXT[], NULL);  -- NULL duration => no timer
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT ok(
  (SELECT phase_ends_at IS NULL FROM rounds r JOIN cycles c ON c.id = r.cycle_id
     WHERE c.chat_id = current_setting('test.f.cseed.chat')::INT),
  'C1: seeding with NULL duration creates a round with NO timer (phase_ends_at NULL)');

-- C2: control — a numeric duration sets a timer. (a1's preview was seeded via direct
-- insert with no phase_ends_at, so build a fresh chat seeded WITH a duration.)
INSERT INTO chats (name, initial_message, creator_session_token, is_preview, max_cycles,
                   confirmation_rounds_required, rating_mode, match_objective, access_method)
VALUES ('F C seed timer', 'Q', gen_random_uuid(), TRUE, 1, 1, 'matches', 'full_rank', 'code');
DO $$
DECLARE v_chat INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'F C seed timer';
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000d1'::UUID, 'Host', TRUE, 'active');
  PERFORM set_config('test.f.cseed2.chat', v_chat::TEXT, FALSE);
END $$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-0000000000d1')::TEXT, TRUE);
SELECT seed_prioritization_round(current_setting('test.f.cseed2.chat')::INT,
  ARRAY['X','Y','Z']::TEXT[], 3600);
RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT ok(
  (SELECT phase_ends_at IS NOT NULL FROM rounds r JOIN cycles c ON c.id = r.cycle_id
     WHERE c.chat_id = current_setting('test.f.cseed2.chat')::INT),
  'C2: seeding with a numeric duration sets a timer (phase_ends_at NOT NULL)');

-- =============================================================================
-- D1/D2: capped conf=1 chat — a TIE (is_sole_winner=FALSE) is a final result:
-- the cycle completes, the chat ends, and NO new round is created.
-- (20260530190000_capped_chat_tie_is_final.sql)
-- =============================================================================
SELECT pg_temp.build_matches_round('d1', 'F D1 tie is final', FALSE, 1);
-- Simulate the tie outcome complete_round_with_winner would set: winner + NOT sole.
UPDATE rounds SET winning_proposition_id =
  (SELECT id FROM propositions WHERE round_id = current_setting('test.f.d1.round')::INT ORDER BY id LIMIT 1),
  is_sole_winner = FALSE
WHERE id = current_setting('test.f.d1.round')::INT;

SELECT ok(
  (SELECT ended_at IS NOT NULL FROM chats WHERE id = current_setting('test.f.d1.chat')::INT),
  'D1: a tie in a capped conf=1 chat completes the cycle and ends the chat');
SELECT is(
  (SELECT COUNT(*)::INT FROM rounds r JOIN cycles c ON c.id = r.cycle_id
     WHERE c.chat_id = current_setting('test.f.d1.chat')::INT),
  1,
  'D2: ...and NO new round was created (tie is not re-run)');

SELECT * FROM finish();
ROLLBACK;
