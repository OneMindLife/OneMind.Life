-- =============================================================================
-- SECURITY regression: round-content DEFINER RPCs must gate on membership.
-- Migration: 20260708035156_gate_content_read_rpcs.sql
--
-- Before the fix, get_propositions_with_scores / get_propositions_with_translations
-- / get_unranked_propositions / get_round_winners returned a PRIVATE chat's
-- proposition + winner text to any anon caller who had the round_id. These tests
-- pin: anon non-member gets nothing on a private chat; a participant gets the
-- real rows (functionality preserved); the public-chat exception still returns
-- data.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(13);

DO $$
DECLARE
  v_priv INT; v_pub INT; v_cyc INT; v_pubcyc INT;
  v_round INT; v_pubround INT;
  v_p1 INT; v_p2 INT; v_pubp INT;
  v_pa INT; v_pb INT; v_pubprop INT;
  v_u1 UUID := '00000000-0000-0000-0000-0000000f0001';  -- participant of private chat
  v_u2 UUID := '00000000-0000-0000-0000-0000000f0004';  -- 2nd participant (authors loser)
  v_uo UUID := '00000000-0000-0000-0000-0000000f0002';  -- outsider (non-member)
  v_upub UUID := '00000000-0000-0000-0000-0000000f0003'; -- host of public chat
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_u1,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_u2,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_uo,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID),
    (v_upub,'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  -- PRIVATE chat (access_method='code') with a rating round: 2 props + a winner.
  -- Two participants because one participant can't author two props in a round.
  INSERT INTO chats (name, initial_message, creator_session_token, access_method)
  VALUES ('Private content test', 'Q', gen_random_uuid(), 'code') RETURNING id INTO v_priv;
  INSERT INTO cycles (chat_id) VALUES (v_priv) RETURNING id INTO v_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cyc, 1, 'rating') RETURNING id INTO v_round;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_priv, gen_random_uuid(), v_u1, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_priv, gen_random_uuid(), v_u2, 'P2', FALSE, 'active') RETURNING id INTO v_p2;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p1, 'WINNER-SECRET') RETURNING id INTO v_pa;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round, v_p2, 'LOSER-SECRET') RETURNING id INTO v_pb;
  UPDATE rounds SET winning_proposition_id = v_pa, completed_at = NOW() WHERE id = v_round;
  INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_round, v_pa, 1, 0.9);

  -- PUBLIC chat with a rating round + a proposition + a winner.
  INSERT INTO chats (name, initial_message, creator_session_token, access_method, is_active)
  VALUES ('Public content test', 'Q', gen_random_uuid(), 'public', TRUE) RETURNING id INTO v_pub;
  INSERT INTO cycles (chat_id) VALUES (v_pub) RETURNING id INTO v_pubcyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_pubcyc, 1, 'rating') RETURNING id INTO v_pubround;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_pub, gen_random_uuid(), v_upub, 'PH', TRUE, 'active') RETURNING id INTO v_pubp;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_pubround, v_pubp, 'PUBLIC-PROP') RETURNING id INTO v_pubprop;
  UPDATE rounds SET winning_proposition_id = v_pubprop, completed_at = NOW() WHERE id = v_pubround;
  INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
    VALUES (v_pubround, v_pubprop, 1, 0.8);

  PERFORM set_config('test.cr.privround', v_round::TEXT,    TRUE);
  PERFORM set_config('test.cr.pubround',  v_pubround::TEXT, TRUE);
  PERFORM set_config('test.cr.u1',        v_u1::TEXT,       TRUE);
END $$;

-- Helper exists
SELECT has_function('public','can_read_round_results', ARRAY['bigint'],
  '1: can_read_round_results(bigint) exists');

-- ===== As an anon NON-MEMBER (anon role, no JWT identity) =====
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT is(
  (SELECT count(*) FROM public.get_propositions_with_scores(current_setting('test.cr.privround')::INT))::INT,
  0,
  '2: anon non-member gets 0 rows from get_propositions_with_scores on private chat');

SELECT is(
  (SELECT count(*) FROM public.get_propositions_with_translations(current_setting('test.cr.privround')::INT, 'en'))::INT,
  0,
  '3: anon non-member gets 0 rows from get_propositions_with_translations on private chat');

SELECT is(
  (SELECT count(*) FROM public.get_unranked_propositions(current_setting('test.cr.privround')::INT, NULL, NULL))::INT,
  0,
  '4: anon non-member gets 0 rows from get_unranked_propositions on private chat');

SELECT is(
  (SELECT count(*) FROM public.get_round_winners(current_setting('test.cr.privround')::INT))::INT,
  0,
  '5: anon non-member gets 0 rows from get_round_winners on private chat');

-- Public-chat exception still works for anon.
SELECT is(
  (SELECT count(*) FROM public.get_propositions_with_scores(current_setting('test.cr.pubround')::INT))::INT,
  1,
  '6: anon CAN read get_propositions_with_scores on a PUBLIC chat (exception preserved)');

SELECT is(
  (SELECT count(*) FROM public.get_propositions_with_translations(current_setting('test.cr.pubround')::INT, 'en'))::INT,
  1,
  '7: anon CAN read get_propositions_with_translations on a PUBLIC chat');

SELECT is(
  (SELECT count(*) FROM public.get_round_winners(current_setting('test.cr.pubround')::INT))::INT,
  1,
  '8: anon CAN read get_round_winners on a PUBLIC chat');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

-- ===== As the PARTICIPANT of the private chat =====
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('test.cr.u1'), 'role','authenticated')::TEXT, TRUE);

SELECT is(
  (SELECT count(*) FROM public.get_propositions_with_scores(current_setting('test.cr.privround')::INT))::INT,
  2,
  '9: participant sees both propositions via get_propositions_with_scores (functionality preserved)');

SELECT is(
  (SELECT count(*) FROM public.get_propositions_with_translations(current_setting('test.cr.privround')::INT, 'en'))::INT,
  2,
  '10: participant sees both propositions via get_propositions_with_translations');

-- Rater P1 has authored one of the two props, so 1 remains unranked to them.
SELECT is(
  (SELECT count(*) FROM public.get_unranked_propositions(current_setting('test.cr.privround')::INT,
      (SELECT id FROM participants WHERE user_id = current_setting('test.cr.u1')::UUID
         AND chat_id = (SELECT cy.chat_id FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
                          WHERE r.id = current_setting('test.cr.privround')::INT)), NULL))::INT,
  1,
  '11: participant sees the other participant''s proposition via get_unranked_propositions');

SELECT is(
  (SELECT content FROM public.get_round_winners(current_setting('test.cr.privround')::INT) LIMIT 1),
  'WINNER-SECRET',
  '12: participant sees the real winner content via get_round_winners');

SELECT is(
  (SELECT content FROM public.get_propositions_with_scores(current_setting('test.cr.privround')::INT)
     ORDER BY content LIMIT 1),
  'LOSER-SECRET',
  '13: participant sees real proposition content (not empty)');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT * FROM finish();
ROLLBACK;
