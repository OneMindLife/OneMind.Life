-- =============================================================================
-- Tests for quick-chat ENGAGED-ONLY eligible count.
-- Migration: 20260602120000_quick_chat_engaged_eligible.sql
-- =============================================================================
-- get_matches_rating_progress(round, chat).eligible must:
--   * for a QUICK chat (max_cycles = 1): count only participants who cast >=1
--     vote this round (pairwise / grid / skip / completion) — a peeker who
--     joins but never votes is EXCLUDED.
--   * for a REGULAR chat (max_cycles <> 1): be unchanged — mirror
--     get_rating_eligible_count (every active participant), regardless of votes.
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

-- =============================================================================
-- SETUP: a QUICK chat (max_cycles = 1) and a REGULAR chat (max_cycles = 3),
-- each with a rating round and active participants owning propositions.
-- =============================================================================
DO $$
DECLARE
  v_qchat INT; v_qcycle INT; v_qround INT;
  v_qp1 INT; v_qp2 INT; v_qp3 INT;
  v_qprop_a INT; v_qprop_b INT;
  v_rchat INT; v_rcycle INT; v_rround INT;
  v_rp1 INT; v_rp2 INT; v_rp3 INT;
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES
    ('00000000-0000-0000-0000-0000000000c1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000c2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000c3'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000d1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000d2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000d3'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
  ON CONFLICT (id) DO NOTHING;

  -- ---- QUICK chat (max_cycles = 1) ----
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode, max_cycles)
  VALUES ('Engaged Eligible — Quick', 'Q', gen_random_uuid(), 'matches', 1)
  RETURNING id INTO v_qchat;
  INSERT INTO cycles (chat_id) VALUES (v_qchat) RETURNING id INTO v_qcycle;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_qcycle, 1, 'rating') RETURNING id INTO v_qround;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_qchat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1'::UUID, 'QP1', TRUE, 'active') RETURNING id INTO v_qp1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_qchat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000c2'::UUID, 'QP2', FALSE, 'active') RETURNING id INTO v_qp2;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_qchat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000c3'::UUID, 'QP3', FALSE, 'active') RETURNING id INTO v_qp3;

  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_qround, v_qp1, 'QA') RETURNING id INTO v_qprop_a;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_qround, v_qp2, 'QB') RETURNING id INTO v_qprop_b;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_qround, v_qp3, 'QC');

  -- ---- REGULAR chat (max_cycles = 3) ----
  INSERT INTO chats (name, initial_message, creator_session_token, rating_mode, max_cycles)
  VALUES ('Engaged Eligible — Regular', 'R', gen_random_uuid(), 'matches', 3)
  RETURNING id INTO v_rchat;
  INSERT INTO cycles (chat_id) VALUES (v_rchat) RETURNING id INTO v_rcycle;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_rcycle, 1, 'rating') RETURNING id INTO v_rround;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_rchat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000d1'::UUID, 'RP1', TRUE, 'active') RETURNING id INTO v_rp1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_rchat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000d2'::UUID, 'RP2', FALSE, 'active') RETURNING id INTO v_rp2;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_rchat, gen_random_uuid(), '00000000-0000-0000-0000-0000000000d3'::UUID, 'RP3', FALSE, 'active') RETURNING id INTO v_rp3;

  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_rround, v_rp1, 'RA');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_rround, v_rp2, 'RB');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_rround, v_rp3, 'RC');

  PERFORM set_config('test.qchat', v_qchat::text, false);
  PERFORM set_config('test.qround', v_qround::text, false);
  PERFORM set_config('test.qp1', v_qp1::text, false);
  PERFORM set_config('test.qp2', v_qp2::text, false);
  PERFORM set_config('test.qprop_a', v_qprop_a::text, false);
  PERFORM set_config('test.qprop_b', v_qprop_b::text, false);
  PERFORM set_config('test.rchat', v_rchat::text, false);
  PERFORM set_config('test.rround', v_rround::text, false);
END $$;

-- ---------------------------------------------------------------------------
-- QUICK chat: no votes yet → eligible = 0, done = 0 (no peekers counted).
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  0,
  'quick chat, nobody voted → eligible = 0 (active joiners not yet counted)'
);
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  0,
  'quick chat, nobody voted → done = 0'
);

-- ---------------------------------------------------------------------------
-- QP1 casts one pairwise vote → engaged (eligible = 1) but not done (done = 0).
-- ---------------------------------------------------------------------------
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
VALUES (current_setting('test.qround')::bigint, current_setting('test.qp1')::bigint,
        current_setting('test.qprop_a')::bigint, current_setting('test.qprop_b')::bigint);
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  1,
  'quick chat, QP1 cast a pairwise vote → eligible = 1 (engaged)'
);
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  0,
  'quick chat, QP1 mid-vote (no completion) → done = 0'
);

-- ---------------------------------------------------------------------------
-- QP1 completes → done = 1, eligible still 1.
-- ---------------------------------------------------------------------------
INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.qround')::bigint, current_setting('test.qp1')::bigint);
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  1,
  'quick chat, QP1 completed → done = 1'
);
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  1,
  'quick chat, QP1 completed → eligible still 1'
);

-- ---------------------------------------------------------------------------
-- KEY: QP2 & QP3 are active participants who NEVER voted (peekers) → they do
-- NOT raise eligible. Host sees done(1) = eligible(1) → 100%, no end-early prompt.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  1,
  'KEY: quick chat, 2 active peekers who never voted → eligible still 1'
);

-- ---------------------------------------------------------------------------
-- QP2 finally casts a pairwise vote → now engaged → eligible = 2.
-- ---------------------------------------------------------------------------
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
VALUES (current_setting('test.qround')::bigint, current_setting('test.qp2')::bigint,
        current_setting('test.qprop_b')::bigint, current_setting('test.qprop_a')::bigint);
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.qround')::bigint, current_setting('test.qchat')::bigint)),
  2,
  'quick chat, QP2 now voted → eligible = 2'
);

-- ---------------------------------------------------------------------------
-- REGULAR chat (max_cycles = 3): eligible is UNCHANGED — every active
-- participant counts, even with zero votes cast.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.rround')::bigint, current_setting('test.rchat')::bigint)),
  3,
  'regular chat, nobody voted → eligible = 3 (all active participants)'
);
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.rround')::bigint, current_setting('test.rchat')::bigint)),
  get_rating_eligible_count(current_setting('test.rchat')::bigint),
  'regular chat eligible still mirrors get_rating_eligible_count'
);

SELECT * FROM finish();
ROLLBACK;
