-- =============================================================================
-- TESTS: get_chat_detail_bootstrap → participants_who_rated (matches mode)
--   Migration: supabase/migrations/20260628193038_bootstrap_matches_who_rated.sql
--
-- In matches (pairwise) mode, voters finish via rating_completions and never
-- write grid_rankings. The original participants_who_rated logic counted only
-- grid_rankings, so the rating-phase "Done" tag never showed in matches chats.
-- The bootstrap now UNIONs rating_completions into participants_who_rated.
--
-- Coverage:
--   T1  a matches voter (rating_completions, NO grid_rankings) shows in participants_who_rated
--   T2  a participant who did nothing does NOT show
--   T3  participants_who_rated is a JSON array
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-0000000cdf01'::uuid, 'authenticated', 'cdf_u1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000cdf02'::uuid, 'authenticated', 'cdf_u2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

DO $$
DECLARE
  v_chat INT; v_cycle INT; v_round INT; v_voter INT; v_idle INT;
BEGIN
  SET LOCAL session_replication_role = 'replica';

  INSERT INTO chats (name, initial_message, creator_session_token, access_method,
                     rating_mode, proposing_minimum, rating_minimum)
  VALUES ('MWR', 'matches who rated', gen_random_uuid(), 'invite_only', 'matches', 3, 3)
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat, '00000000-0000-0000-0000-0000000cdf01'::uuid, 'Voter', true, 'active')
  RETURNING id INTO v_voter;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat, '00000000-0000-0000-0000-0000000cdf02'::uuid, 'Idle', false, 'active')
  RETURNING id INTO v_idle;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle, 1, 'rating')
  RETURNING id INTO v_round;

  -- Two propositions so v_total_props > 0 (so the who-rated block runs).
  INSERT INTO propositions (chat_id, round_id, participant_id, content) VALUES (v_chat, v_round, v_voter, 'A');
  INSERT INTO propositions (chat_id, round_id, participant_id, content) VALUES (v_chat, v_round, v_idle, 'B');

  -- Matches completion: NO grid_rankings, just a rating_completions row for the voter.
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_round, v_voter);

  PERFORM set_config('test.chat', v_chat::text, false);
  PERFORM set_config('test.voter', v_voter::text, false);
  PERFORM set_config('test.idle', v_idle::text, false);
END $$;

-- Call the bootstrap as the voter (caller must be a participant).
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000cdf01"}', true);

SELECT ok(
  (get_chat_detail_bootstrap(current_setting('test.chat')::bigint, 'en', false)
     ->'participants_who_rated') @> to_jsonb(current_setting('test.voter')::bigint),
  'T1: matches voter (rating_completions, no grid_rankings) shows in participants_who_rated'
);

SELECT ok(
  NOT (
    (get_chat_detail_bootstrap(current_setting('test.chat')::bigint, 'en', false)
       ->'participants_who_rated') @> to_jsonb(current_setting('test.idle')::bigint)
  ),
  'T2: a participant who did nothing does NOT show in participants_who_rated'
);

SELECT is(
  jsonb_typeof(get_chat_detail_bootstrap(current_setting('test.chat')::bigint, 'en', false)
     ->'participants_who_rated'),
  'array',
  'T3: participants_who_rated is a JSON array'
);

SELECT * FROM finish();
ROLLBACK;
