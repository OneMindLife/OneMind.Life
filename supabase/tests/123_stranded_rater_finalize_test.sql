-- A quick-chat matches RATING round must finalize once every voter who CAN rate
-- has acted. HISTORY: before conditional self-inclusion (20260704160000) the
-- authors of the only two ideas were STRANDED (no votable pair, rateable = 1 <
-- 2) and finalize skipped them — this file was the regression test for that.
-- Under CSI those authors ARE able voters (the pair includes their own idea;
-- voting for the other is an explicit concession), so the round now waits for
-- them too, and "stranded" only exists when the board has < 2 props at all.
BEGIN;
SELECT plan(3);

DO $$
DECLARE
  v_chat bigint; v_cycle bigint; v_r1 bigint; v_r2 bigint;
  v_a bigint; v_b bigint; v_c bigint;
  v_a_tok uuid := gen_random_uuid();
  v_b_tok uuid := gen_random_uuid();
  v_c_tok uuid := gen_random_uuid();
  v_root bigint; v_leader bigint; v_chall bigint;
BEGIN
  INSERT INTO chats (name, initial_message, mode, max_cycles, rating_mode, match_objective,
                     confirmation_rounds_required, start_mode, rating_minimum,
                     proposing_threshold_count, proposing_threshold_percent,
                     rating_threshold_count, rating_threshold_percent)
  VALUES ('stranded finalize', 'q', 'decision', 1, 'matches', 'winner_only', 2, 'manual', 2,
          NULL, NULL, NULL, NULL)
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, v_a_tok, 'A', true, 'active') RETURNING id INTO v_a;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, v_b_tok, 'B', false, 'active') RETURNING id INTO v_b;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
  VALUES (v_chat, v_c_tok, 'C', false, 'active') RETURNING id INTO v_c;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, completed_at)
  VALUES (v_cycle, 1, 'rating', NOW()) RETURNING id INTO v_r1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_a, 'Root A') RETURNING id INTO v_root;

  -- R2 rating: carried leader (A) + one challenger (B). Under CSI all three
  -- participants can vote the leader-vs-challenger pair (A and B get their own
  -- idea included since excluding it leaves them under 2).
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
  VALUES (v_cycle, 2, 'rating', NOW()) RETURNING id INTO v_r2;
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_r2, v_a, 'Leader A', v_root) RETURNING id INTO v_leader;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r2, v_b, 'Challenger B') RETURNING id INTO v_chall;

  PERFORM set_config('test.chat', v_chat::text, false);
  PERFORM set_config('test.r2', v_r2::text, false);
  PERFORM set_config('test.a', v_a::text, false);
  PERFORM set_config('test.b', v_b::text, false);
  PERFORM set_config('test.c', v_c::text, false);
  PERFORM set_config('test.a_tok', v_a_tok::text, false);
  PERFORM set_config('test.b_tok', v_b_tok::text, false);
  PERFORM set_config('test.c_tok', v_c_tok::text, false);
  PERFORM set_config('test.leader', v_leader::text, false);
  PERFORM set_config('test.chall', v_chall::text, false);
END $$;

SELECT is(
  (SELECT completed_at IS NULL FROM rounds WHERE id = current_setting('test.r2')::bigint),
  true, 'A: round is open before anyone acts');

-- C casts a real vote + completes -> under CSI, A and B are still ABLE voters
-- (pending), so the round must stay open.
DO $$
DECLARE v_r2 bigint := current_setting('test.r2')::bigint;
        v_c bigint := current_setting('test.c')::bigint;
BEGIN
  INSERT INTO pairwise_comparisons (round_id, participant_id, session_token,
                                    winner_proposition_id, loser_proposition_id, is_tie, is_skip)
  VALUES (v_r2, v_c, current_setting('test.c_tok')::uuid,
          current_setting('test.leader')::bigint, current_setting('test.chall')::bigint, false, false);
  INSERT INTO rating_completions (round_id, participant_id, session_token, chat_id)
  VALUES (v_r2, v_c, current_setting('test.c_tok')::uuid, current_setting('test.chat')::bigint);
END $$;

SELECT is(
  (SELECT completed_at IS NULL FROM rounds WHERE id = current_setting('test.r2')::bigint),
  true, 'B: round stays open — the authors are able voters under CSI');

-- A and B vote their (own-vs-other) pair and complete -> everyone able has
-- acted -> finalize fires.
DO $$
DECLARE v_r2 bigint := current_setting('test.r2')::bigint;
        v_a bigint := current_setting('test.a')::bigint;
        v_b bigint := current_setting('test.b')::bigint;
BEGIN
  INSERT INTO pairwise_comparisons (round_id, participant_id, session_token,
                                    winner_proposition_id, loser_proposition_id, is_tie, is_skip)
  VALUES (v_r2, v_a, current_setting('test.a_tok')::uuid,
          current_setting('test.leader')::bigint, current_setting('test.chall')::bigint, false, false);
  INSERT INTO rating_completions (round_id, participant_id, session_token, chat_id)
  VALUES (v_r2, v_a, current_setting('test.a_tok')::uuid, current_setting('test.chat')::bigint);

  INSERT INTO pairwise_comparisons (round_id, participant_id, session_token,
                                    winner_proposition_id, loser_proposition_id, is_tie, is_skip)
  VALUES (v_r2, v_b, current_setting('test.b_tok')::uuid,
          current_setting('test.chall')::bigint, current_setting('test.leader')::bigint, false, false);
  INSERT INTO rating_completions (round_id, participant_id, session_token, chat_id)
  VALUES (v_r2, v_b, current_setting('test.b_tok')::uuid, current_setting('test.chat')::bigint);
END $$;

SELECT isnt(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.r2')::bigint),
  NULL, 'C: round finalizes once every able voter (C, A, B) has acted');

SELECT * FROM finish();
ROLLBACK;
