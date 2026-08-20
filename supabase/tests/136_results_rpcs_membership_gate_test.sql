-- =============================================================================
-- SECURITY regression: results/history DEFINER RPCs must gate on membership.
-- Migration: 20260707120000_gate_results_rpcs_membership.sql
--
-- Before the fix, get_round_history / get_chat_result_meta / get_round_voter_count
-- returned a PRIVATE chat's winning proposition text + counts to any anon caller
-- with the chat_id. These tests pin: anon non-member gets nothing on a private
-- chat; a participant gets real data; the public-chat exception still works.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(8);

DO $$
DECLARE
  v_priv INT; v_pub INT; v_cyc INT; v_pubcyc INT;
  v_round INT; v_pubround INT;
  v_p1 INT; v_p2 INT; v_pa INT; v_pb INT; v_pubp INT; v_pubprop INT;
  v_u1 UUID := '00000000-0000-0000-0000-0000000e0001';  -- participant of private chat
  v_u2 UUID := '00000000-0000-0000-0000-0000000e0004';  -- 2nd participant (authors loser)
  v_uo UUID := '00000000-0000-0000-0000-0000000e0002';  -- outsider (non-member)
  v_upub UUID := '00000000-0000-0000-0000-0000000e0003'; -- host of public chat
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_u1,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_u2,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_uo,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_upub,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  -- PRIVATE chat (access_method='code') with a completed round + winner + 1 voter.
  INSERT INTO chats (name, initial_message, creator_session_token, access_method)
  VALUES ('Private results test', 'Q', gen_random_uuid(), 'code') RETURNING id INTO v_priv;
  INSERT INTO cycles (chat_id) VALUES (v_priv) RETURNING id INTO v_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cyc, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_priv, gen_random_uuid(), v_u1, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_priv, gen_random_uuid(), v_u2, 'P2', FALSE, 'active') RETURNING id INTO v_p2;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p1, 'WINNER-SECRET') RETURNING id INTO v_pa;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p2, 'LOSER-SECRET') RETURNING id INTO v_pb;
  UPDATE rounds SET winning_proposition_id = v_pa, completed_at = NOW() WHERE id = v_round;
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    VALUES (v_round, v_p1, v_pa, v_pb);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_p1);

  -- PUBLIC chat with a completed round + winner.
  INSERT INTO chats (name, initial_message, creator_session_token, access_method, is_active)
  VALUES ('Public results test', 'Q', gen_random_uuid(), 'public', TRUE) RETURNING id INTO v_pub;
  INSERT INTO cycles (chat_id) VALUES (v_pub) RETURNING id INTO v_pubcyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_pubcyc, 1, 'rating') RETURNING id INTO v_pubround;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_pub, gen_random_uuid(), v_upub, 'PH', TRUE, 'active') RETURNING id INTO v_pubp;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_pubround, v_pubp, 'PUBLIC-WINNER') RETURNING id INTO v_pubprop;
  UPDATE rounds SET winning_proposition_id = v_pubprop, completed_at = NOW() WHERE id = v_pubround;

  PERFORM set_config('test.rg.priv',  v_priv::TEXT,  TRUE);
  PERFORM set_config('test.rg.pub',   v_pub::TEXT,   TRUE);
  PERFORM set_config('test.rg.round', v_round::TEXT, TRUE);
  PERFORM set_config('test.rg.u1',    v_u1::TEXT,    TRUE);
END $$;

-- Helper exists
SELECT has_function('public','can_read_chat_results', ARRAY['bigint'],
  '1: can_read_chat_results(bigint) exists');

-- ===== As an anon NON-MEMBER (anon role, no JWT identity) =====
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT is(
  public.get_round_history(current_setting('test.rg.priv')::INT),
  '[]'::jsonb,
  '2: anon non-member gets EMPTY round history on a private chat (no winner text leak)');

SELECT is(
  public.get_chat_result_meta(current_setting('test.rg.priv')::INT),
  NULL::jsonb,
  '3: anon non-member gets NULL result meta on a private chat');

SELECT is(
  public.get_round_voter_count(current_setting('test.rg.round')::INT),
  0,
  '4: anon non-member gets 0 voter count on a private chat round');

-- Public-chat exception still works for anon.
SELECT isnt(
  public.get_round_history(current_setting('test.rg.pub')::INT),
  '[]'::jsonb,
  '5: anon CAN read round history on a PUBLIC chat (exception preserved)');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- ===== As the PARTICIPANT of the private chat =====
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('test.rg.u1'), 'role','authenticated')::TEXT, TRUE);

SELECT is(
  (public.get_round_history(current_setting('test.rg.priv')::INT) -> 0 ->> 'winner'),
  'WINNER-SECRET',
  '6: participant DOES see the winner text (functionality preserved)');

SELECT is(
  public.get_round_voter_count(current_setting('test.rg.round')::INT),
  1,
  '7: participant sees the real voter count (1)');

SELECT isnt(
  public.get_chat_result_meta(current_setting('test.rg.priv')::INT),
  NULL::jsonb,
  '8: participant gets non-null result meta');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT * FROM finish();
ROLLBACK;
