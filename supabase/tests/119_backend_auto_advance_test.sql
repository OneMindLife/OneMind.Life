-- =============================================================================
-- Tests for backend auto-advance (quick chats) — DB layer.
-- Migration: 20260624030000_backend_auto_advance.sql
--   • RATING auto-finalize for real quick chats (done>=eligible AND >=1 vote).
--   • R2+ PROPOSING auto-advance (responses>=active, >=2): converge if no
--     challenger, else open rating. R1 proposing stays host-paced.
-- =============================================================================
-- Coverage:
--   R. Rating finalize
--      R1: real quick rating round auto-finalizes when all done + >=1 real vote
--      R2: 0-vote real round does NOT finalize (no meaningless winner)
--   P. R2+ proposing
--      P1: a challenger + everyone responded → round opens RATING
--      P2: nobody challenged (all affirm) → carried leader wins (converge)
--      P3: ROUND 1 proposing never auto-advances (assembly = host-paced)
--      P4: not everyone has responded → stays proposing
--
-- Runs inside BEGIN/ROLLBACK. Triggers are SECURITY DEFINER; set up as postgres.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(6);

-- Builder: a real quick chat (max_cycles=1, matches) with N active participants.
CREATE OR REPLACE FUNCTION pg_temp.mk_chat(p_key TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_chat INT; v_p1 INT; v_p2 INT; v_cycle INT;
BEGIN
  -- Mirror real wedge quick chats: NULL proposing/rating thresholds disable the
  -- existing early-advance triggers, so R1 proposing stays host-paced and the
  -- ONLY auto-advance is the new backend logic under test.
  INSERT INTO chats (name, initial_message, creator_session_token, is_preview,
                     max_cycles, confirmation_rounds_required, rating_mode,
                     match_objective, access_method,
                     proposing_threshold_percent, proposing_threshold_count,
                     rating_threshold_percent, rating_threshold_count)
  VALUES ('AA '||p_key, 'q', gen_random_uuid(), false, 1, 2, 'matches',
          'winner_only', 'code', NULL, NULL, NULL, NULL)
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'Host', true, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, gen_random_uuid(), 'Player', false, 'active') RETURNING id INTO v_p2;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  PERFORM set_config('test.'||p_key||'.chat',  v_chat::text,  false);
  PERFORM set_config('test.'||p_key||'.p1',     v_p1::text,    false);
  PERFORM set_config('test.'||p_key||'.p2',     v_p2::text,    false);
  PERFORM set_config('test.'||p_key||'.cycle',  v_cycle::text, false);
END $$;

-- ---------------------------------------------------------------------------
-- R. RATING auto-finalize
-- ---------------------------------------------------------------------------
-- R1: all done + 1 real vote → finalizes.
SELECT pg_temp.mk_chat('rf');
DO $$
DECLARE v_round INT; v_a INT; v_b INT;
  v_p1 INT := current_setting('test.rf.p1')::int;
  v_p2 INT := current_setting('test.rf.p2')::int;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (current_setting('test.rf.cycle')::int, 1, 'rating', NOW()) RETURNING id INTO v_round;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p1, 'Idea A') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p2, 'Idea B') RETURNING id INTO v_b;
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id, is_tie, is_skip)
  VALUES (v_round, v_p1, v_a, v_b, false, false);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p1);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p2);  -- triggers finalize
  PERFORM set_config('test.rf.round', v_round::text, false);
END $$;
SELECT isnt(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.rf.round')::int),
  NULL,
  'R1: real quick rating round auto-finalizes when all done + >=1 real vote');

-- R2: all done but 0 real votes → does NOT finalize.
SELECT pg_temp.mk_chat('rf0');
DO $$
DECLARE v_round INT; v_a INT; v_b INT;
  v_p1 INT := current_setting('test.rf0.p1')::int;
  v_p2 INT := current_setting('test.rf0.p2')::int;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (current_setting('test.rf0.cycle')::int, 1, 'rating', NOW()) RETURNING id INTO v_round;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p1, 'Idea A') RETURNING id INTO v_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p2, 'Idea B') RETURNING id INTO v_b;
  -- no pairwise vote
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p1);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p2);
  PERFORM set_config('test.rf0.round', v_round::text, false);
END $$;
SELECT is(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.rf0.round')::int),
  NULL::timestamptz,
  'R2: 0-vote real quick round does NOT finalize (no meaningless winner)');

-- ---------------------------------------------------------------------------
-- P. R2+ proposing auto-advance.  Helper: build a chat with R1(done) + R2(proposing,carried)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.mk_r2(p_key TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_r1 INT; v_r2 INT; v_root INT; v_carried INT;
  v_p1 INT := current_setting('test.'||p_key||'.p1')::int;
  v_cycle INT := current_setting('test.'||p_key||'.cycle')::int;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cycle, 1, 'rating', NOW(), NOW()) RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p1, 'Champion') RETURNING id INTO v_root;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle, 2, 'proposing', NOW()) RETURNING id INTO v_r2;
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_r2, v_p1, 'Champion', v_root) RETURNING id INTO v_carried;
  PERFORM set_config('test.'||p_key||'.r2', v_r2::text, false);
END $$;

-- P1: a challenger submitted + everyone responded → opens RATING.
SELECT pg_temp.mk_chat('pa');
SELECT pg_temp.mk_r2('pa');
DO $$
DECLARE v_r2 INT := current_setting('test.pa.r2')::int;
  v_p1 INT := current_setting('test.pa.p1')::int;
  v_p2 INT := current_setting('test.pa.p2')::int;
BEGIN
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r2, v_p2, 'A challenger');  -- challenge
  INSERT INTO affirmations (round_id, participant_id, user_id, chat_id)
  VALUES (v_r2, v_p1, gen_random_uuid(), current_setting('test.pa.chat')::int);  -- host keeps → all responded
END $$;
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.pa.r2')::int),
  'rating',
  'P1: challenger + everyone responded → round opens rating');

-- P2: nobody challenged (both affirm) → carried leader wins (converge).
SELECT pg_temp.mk_chat('pb');
SELECT pg_temp.mk_r2('pb');
DO $$
DECLARE v_r2 INT := current_setting('test.pb.r2')::int;
  v_p1 INT := current_setting('test.pb.p1')::int;
  v_p2 INT := current_setting('test.pb.p2')::int;
  v_chat INT := current_setting('test.pb.chat')::int;
BEGIN
  INSERT INTO affirmations (round_id, participant_id, user_id, chat_id) VALUES (v_r2, v_p1, gen_random_uuid(), v_chat);
  INSERT INTO affirmations (round_id, participant_id, user_id, chat_id) VALUES (v_r2, v_p2, gen_random_uuid(), v_chat);  -- all affirm
END $$;
SELECT isnt(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.pb.r2')::int),
  NULL,
  'P2: all affirm, no challenger → carried leader wins (converge)');

-- P3: ROUND 1 proposing never auto-advances (assembly = host-paced).
SELECT pg_temp.mk_chat('pc');
DO $$
DECLARE v_r1 INT;
  v_p1 INT := current_setting('test.pc.p1')::int;
  v_p2 INT := current_setting('test.pc.p2')::int;
BEGIN
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (current_setting('test.pc.cycle')::int, 1, 'proposing', NOW()) RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p1, 'One');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_r1, v_p2, 'Two');  -- both submitted
  PERFORM set_config('test.pc.r1', v_r1::text, false);
END $$;
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.pc.r1')::int),
  'proposing',
  'P3: round 1 proposing stays host-paced (no auto-advance)');

-- P4: not everyone responded → stays proposing.
SELECT pg_temp.mk_chat('pd');
SELECT pg_temp.mk_r2('pd');
DO $$
DECLARE v_r2 INT := current_setting('test.pd.r2')::int;
  v_p1 INT := current_setting('test.pd.p1')::int;
BEGIN
  INSERT INTO affirmations (round_id, participant_id, user_id, chat_id)
  VALUES (v_r2, v_p1, gen_random_uuid(), current_setting('test.pd.chat')::int);  -- only 1 of 2
END $$;
SELECT is(
  (SELECT phase FROM rounds WHERE id = current_setting('test.pd.r2')::int),
  'proposing',
  'P4: not everyone responded → stays proposing');

SELECT * FROM finish();
ROLLBACK;
