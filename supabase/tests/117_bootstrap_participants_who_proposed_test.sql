-- =============================================================================
-- TESTS: get_chat_detail_bootstrap → participants_who_proposed
--   Migration: supabase/migrations/20260628143659_bootstrap_participants_who_proposed.sql
--
-- The proposing-phase "Done" tag on the participants leaderboard needs a
-- who-proposed signal (proposition authorship is hidden client-side during
-- proposing). The bootstrap RPC now returns `participants_who_proposed`: the
-- DISTINCT authors of a NEW proposition (carried_from_id IS NULL) in the
-- current round. It exposes participation only, never idea content (the RPC is
-- SECURITY DEFINER).
--
-- Coverage:
--   T1  participants_who_proposed contains the proposer (Bob)
--   T2  participants_who_proposed excludes the skipper (Carol)
--   T3  participants_who_proposed excludes the inactive caller who did nothing (Alice)
--   T4  participants_who_skipped_proposing contains the skipper (Carol)
--   T5  participants_who_proposed is a JSON array
--   T6  carried-forward winner (participant_id NULL) is NOT counted → exactly 1 proposer
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(6);

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-0000000cde01'::uuid, 'authenticated', 'cde_u1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000cde02'::uuid, 'authenticated', 'cde_u2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000cde03'::uuid, 'authenticated', 'cde_u3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

DO $$
DECLARE
  v_chat INT;
  v_cycle INT;
  v_prev_round INT;
  v_round INT;
  v_p1 INT;  -- Alice (host/caller, does nothing)
  v_p2 INT;  -- Bob (proposes a NEW prop)
  v_p3 INT;  -- Carol (skips proposing)
  v_winner_prop INT;
BEGIN
  -- Disable user triggers so we can stage a deterministic snapshot for the
  -- read-only RPC under test without firing the advance / winner pipelines.
  SET LOCAL session_replication_role = 'replica';

  INSERT INTO chats (name, initial_message, creator_session_token,
                     access_method, proposing_minimum, rating_minimum)
  VALUES ('PWP', 'who proposed?', gen_random_uuid(), 'invite_only', 3, 3)
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat, '00000000-0000-0000-0000-0000000cde01'::uuid, 'Alice', true, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat, '00000000-0000-0000-0000-0000000cde02'::uuid, 'Bob', false, 'active')
  RETURNING id INTO v_p2;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat, '00000000-0000-0000-0000-0000000cde03'::uuid, 'Carol', false, 'active')
  RETURNING id INTO v_p3;

  INSERT INTO cycles (chat_id, created_at)
  VALUES (v_chat, NOW() - INTERVAL '1 hour')
  RETURNING id INTO v_cycle;

  -- Previous completed round + a winner proposition to carry forward.
  INSERT INTO rounds (cycle_id, custom_id, phase, completed_at, is_sole_winner)
  VALUES (v_cycle, 1, 'rating', NOW() - INTERVAL '30 minutes', TRUE)
  RETURNING id INTO v_prev_round;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_prev_round, v_p2, 'Round 1 winner')
  RETURNING id INTO v_winner_prop;

  UPDATE rounds SET winning_proposition_id = v_winner_prop WHERE id = v_prev_round;

  -- Current round in PROPOSING.
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle, 2, 'proposing', NOW(), NOW() + INTERVAL '1 hour')
  RETURNING id INTO v_round;

  -- Carried-forward winner (participant_id NULL, carried_from_id set) — MUST
  -- NOT be counted as a proposer.
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round, NULL, 'Round 1 winner', v_winner_prop);

  -- Bob submits a NEW proposition (carried_from_id NULL).
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round, v_p2, 'Bob fresh idea');

  -- Carol skips proposing (does NOT submit).
  INSERT INTO round_skips (round_id, participant_id)
  VALUES (v_round, v_p3);

  PERFORM set_config('test.pwp.chat', v_chat::TEXT, TRUE);
  PERFORM set_config('test.pwp.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.pwp.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.pwp.p3', v_p3::TEXT, TRUE);
END $$;

-- HELPER: run the RPC as a specific authenticated user.
CREATE OR REPLACE FUNCTION public._pwp_run_as(p_user UUID, p_chat INT)
RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user::TEXT, 'role', 'authenticated')::TEXT, TRUE);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_result := public.get_chat_detail_bootstrap(p_chat, NULL, FALSE);
  RESET ROLE;
  RETURN v_result;
END;
$$;

-- =============================================================================
-- T1: participants_who_proposed contains Bob (proposed a new prop)
-- =============================================================================
SELECT ok(
    EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(
        public._pwp_run_as('00000000-0000-0000-0000-0000000cde01'::uuid,
            current_setting('test.pwp.chat')::INT)
        -> 'participants_who_proposed') elem
      WHERE elem::INT = current_setting('test.pwp.p2')::INT),
    'T1: participants_who_proposed includes Bob (the proposer)');

-- =============================================================================
-- T2: participants_who_proposed excludes Carol (skipped, did not propose)
-- =============================================================================
SELECT ok(
    NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(
        public._pwp_run_as('00000000-0000-0000-0000-0000000cde01'::uuid,
            current_setting('test.pwp.chat')::INT)
        -> 'participants_who_proposed') elem
      WHERE elem::INT = current_setting('test.pwp.p3')::INT),
    'T2: participants_who_proposed excludes Carol (the skipper)');

-- =============================================================================
-- T3: participants_who_proposed excludes Alice (did nothing)
-- =============================================================================
SELECT ok(
    NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(
        public._pwp_run_as('00000000-0000-0000-0000-0000000cde01'::uuid,
            current_setting('test.pwp.chat')::INT)
        -> 'participants_who_proposed') elem
      WHERE elem::INT = current_setting('test.pwp.p1')::INT),
    'T3: participants_who_proposed excludes Alice (no action)');

-- =============================================================================
-- T4: participants_who_skipped_proposing contains Carol
-- =============================================================================
SELECT ok(
    EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(
        public._pwp_run_as('00000000-0000-0000-0000-0000000cde01'::uuid,
            current_setting('test.pwp.chat')::INT)
        -> 'participants_who_skipped_proposing') elem
      WHERE elem::INT = current_setting('test.pwp.p3')::INT),
    'T4: participants_who_skipped_proposing includes Carol (the skipper)');

-- =============================================================================
-- T5: participants_who_proposed is a JSON array
-- =============================================================================
SELECT is(
    jsonb_typeof(
        public._pwp_run_as('00000000-0000-0000-0000-0000000cde01'::uuid,
            current_setting('test.pwp.chat')::INT)
        -> 'participants_who_proposed'),
    'array',
    'T5: participants_who_proposed is a JSON array');

-- =============================================================================
-- T6: carried-forward winner (participant_id NULL) not counted → exactly 1
-- proposer (Bob).
-- =============================================================================
SELECT is(
    jsonb_array_length(
        public._pwp_run_as('00000000-0000-0000-0000-0000000cde01'::uuid,
            current_setting('test.pwp.chat')::INT)
        -> 'participants_who_proposed'),
    1,
    'T6: carried-forward winner excluded; exactly one new proposer');

DROP FUNCTION IF EXISTS public._pwp_run_as(UUID, INT);

SELECT * FROM finish();
ROLLBACK;
