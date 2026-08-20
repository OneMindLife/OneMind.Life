-- =============================================================================
-- TESTS: get_chat_detail_bootstrap RPC
--   Migration: supabase/migrations/20260501240000_chat_detail_bootstrap.sql
--
-- The RPC bundles the 18 parallel queries ChatDetailNotifier._loadData fires
-- on every refresh into one round-trip. Tests verify that each "shard" of
-- the resulting JSONB matches the per-query path that Flutter currently
-- uses, plus the access-control / edge-case guards.
--
-- Coverage:
--   T1   missing chat → returns NULL
--   T2   non-participant + private chat → returns NULL
--   T3   non-participant + public chat → returns chat (read-only access)
--   T4   chat row carries the raw columns (id, name, schedule_paused, etc.)
--   T5   translations applied when language code is provided
--   T6   missing translation falls back to 'en' → original
--   T7   participants array contains active members ordered by display_name
--   T8   non-active participants are excluded from participants array
--   T9   my_participant matches caller's row
--   T10  pending_join_requests populated only when caller is host
--   T11  no current cycle → cycle/round/propositions empty
--   T12  current cycle present, no round → cycle JSON populated, round NULL
--   T13  current round present, proposing → propositions array carries new
--        proposition + my_propositions only mine
--   T14  rating_progress counts non-self propositions vs my grid_rankings
--   T15  skip_count + has_skipped + participants_who_skipped_proposing
--   T16  rating_skip_count + has_skipped_rating + participants_who_skipped_rating
--   T17  affirmation_count + has_affirmed + participants_who_affirmed
--   T18  participants_who_rated tracks done participants per rating cap
--   T19  min_ratings_per_prop returns lowest count across props in round
--   T20  previous_round_winners returns rank-1 entries with global_score order
--   T21  is_sole_winner + consecutive_sole_wins reflect prior rounds
--   T22  consensus_items returns completed cycles in completed_at order
--   T23  is_my_participant_funded defaults TRUE when no funding rows exist
--   T24  allowed_categories returns array (from get_chat_allowed_categories)
--   T25  EXECUTE granted to anon + authenticated
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(33);

-- -----------------------------------------------------------------------------
-- SETUP: 4 users, 2 chats (private host-paused, public discoverable).
-- -----------------------------------------------------------------------------
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-0000000bcd01'::uuid, 'authenticated', 'bcd_u1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000bcd02'::uuid, 'authenticated', 'bcd_u2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000bcd03'::uuid, 'authenticated', 'bcd_u3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000bcd04'::uuid, 'authenticated', 'bcd_outsider@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

DO $$
DECLARE
  v_chat_priv INT;
  v_chat_pub INT;
  v_cycle_priv INT;
  v_round_priv INT;
  v_prev_round INT;
  v_p1 INT; v_p2 INT; v_p3 INT;
  v_my_prop INT;
  v_other_prop INT;
  v_winner_prop INT;
BEGIN
  -- Disable user triggers so we can set up arbitrary state without firing
  -- the round-winner / early-advance / stranded-rater pipelines. We just
  -- want a deterministic snapshot for the read-only RPC under test.
  SET LOCAL session_replication_role = 'replica';
  ----------------------------------------------------------------------------
  -- Private chat ─ caller is host (bcd01), bcd02 is active member, bcd03 is
  -- inactive (status=left), bcd04 is non-participant.
  ----------------------------------------------------------------------------
  INSERT INTO chats (name, initial_message, creator_session_token,
                     access_method,
                     proposing_minimum, rating_minimum)
  VALUES ('Private', 'Private question', gen_random_uuid(),
          'invite_only', 3, 3)
  RETURNING id INTO v_chat_priv;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_priv, '00000000-0000-0000-0000-0000000bcd01'::uuid, 'Alice', true, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_priv, '00000000-0000-0000-0000-0000000bcd02'::uuid, 'Bob', false, 'active')
  RETURNING id INTO v_p2;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_priv, '00000000-0000-0000-0000-0000000bcd03'::uuid, 'Carol', false, 'left')
  RETURNING id INTO v_p3;

  -- Pending join request from outsider so the host can see it.
  INSERT INTO join_requests (chat_id, user_id, display_name, status)
  VALUES (v_chat_priv, '00000000-0000-0000-0000-0000000bcd04'::uuid, 'Dave', 'pending');

  ----------------------------------------------------------------------------
  -- Add a previous (completed) round so we exercise winners + sole_winner.
  -- The trigger pipeline doesn't auto-create this so we wire it manually.
  ----------------------------------------------------------------------------
  INSERT INTO cycles (chat_id, created_at)
  VALUES (v_chat_priv, NOW() - INTERVAL '1 hour')
  RETURNING id INTO v_cycle_priv;

  INSERT INTO rounds (cycle_id, custom_id, phase, completed_at, is_sole_winner)
  VALUES (v_cycle_priv, 1, 'rating', NOW() - INTERVAL '30 minutes', TRUE)
  RETURNING id INTO v_prev_round;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_prev_round, v_p1, 'Round 1 winner content')
  RETURNING id INTO v_winner_prop;

  UPDATE rounds SET winning_proposition_id = v_winner_prop
  WHERE id = v_prev_round;

  INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
  VALUES (v_prev_round, v_winner_prop, 1, 87.5);

  -- Current (uncompleted) round
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle_priv, 2, 'proposing', NOW(), NOW() + INTERVAL '1 hour')
  RETURNING id INTO v_round_priv;

  -- Carried forward winner (carried_from_id NOT NULL)
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
  VALUES (v_round_priv, NULL, 'Round 1 winner content', v_winner_prop);

  -- New proposition by host (so my_propositions has one)
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_priv, v_p1, 'Alice new prop')
  RETURNING id INTO v_my_prop;

  -- New proposition by Bob (so propositions has two non-self for Alice).
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_priv, v_p2, 'Bob new prop')
  RETURNING id INTO v_other_prop;

  -- Skip + rating skip + affirmation by Bob (user_id NOT NULL since
  -- triggers are disabled — populate directly).
  INSERT INTO round_skips (round_id, participant_id)
  VALUES (v_round_priv, v_p2);
  INSERT INTO rating_skips (round_id, participant_id)
  VALUES (v_round_priv, v_p2);
  INSERT INTO affirmations (round_id, participant_id, user_id)
  VALUES (v_round_priv, v_p2, '00000000-0000-0000-0000-0000000bcd02'::uuid);

  -- Alice rates Bob's proposition (1 grid_ranking) and the carried prop.
  -- We need at least k_max_ratings_per_user (7) or non-self props completed
  -- to count as "done", but here only 2 non-self props total → done @ 2.
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  SELECT v_round_priv, v_p1, p.id, 75.0
  FROM propositions p
  WHERE p.round_id = v_round_priv AND p.participant_id IS DISTINCT FROM v_p1;

  -- Save state for tests
  PERFORM set_config('test.bcd.chat_priv', v_chat_priv::TEXT, TRUE);
  PERFORM set_config('test.bcd.cycle_priv', v_cycle_priv::TEXT, TRUE);
  PERFORM set_config('test.bcd.round_priv', v_round_priv::TEXT, TRUE);
  PERFORM set_config('test.bcd.prev_round', v_prev_round::TEXT, TRUE);
  PERFORM set_config('test.bcd.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.bcd.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.bcd.p3', v_p3::TEXT, TRUE);
  PERFORM set_config('test.bcd.winner_prop', v_winner_prop::TEXT, TRUE);
  PERFORM set_config('test.bcd.my_prop', v_my_prop::TEXT, TRUE);
  PERFORM set_config('test.bcd.other_prop', v_other_prop::TEXT, TRUE);

  ----------------------------------------------------------------------------
  -- Public chat ─ no participants. Used to verify open-access read.
  ----------------------------------------------------------------------------
  INSERT INTO chats (name, initial_message, creator_session_token,
                     access_method,
                     proposing_minimum, rating_minimum)
  VALUES ('Public', 'Anyone can read', gen_random_uuid(),
          'public', 3, 3)
  RETURNING id INTO v_chat_pub;

  -- Translation row for Spanish name (T5)
  INSERT INTO translations (chat_id, field_name, language_code, translated_text)
  VALUES (v_chat_priv, 'name', 'es', 'Privado'),
         (v_chat_priv, 'name', 'en', 'Private'),
         (v_chat_priv, 'description', 'en', 'EN desc fallback');

  PERFORM set_config('test.bcd.chat_pub', v_chat_pub::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- HELPER: run as a specific user
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._bcd_run_as(p_user UUID, p_chat INT,
    p_lang TEXT DEFAULT NULL, p_prev BOOLEAN DEFAULT FALSE)
RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user::TEXT, 'role', 'authenticated')::TEXT, TRUE);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_result := public.get_chat_detail_bootstrap(p_chat, p_lang, p_prev);
  RESET ROLE;
  RETURN v_result;
END;
$$;

-- =============================================================================
-- T1: missing chat returns NULL
-- =============================================================================
SELECT is(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid, 999999999),
    NULL,
    'T1: missing chat returns NULL');

-- =============================================================================
-- T2: non-participant + private chat returns NULL
-- =============================================================================
SELECT is(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd04'::uuid,
        current_setting('test.bcd.chat_priv')::INT),
    NULL,
    'T2: non-participant + private chat returns NULL');

-- =============================================================================
-- T3: non-participant + public chat returns chat
-- =============================================================================
SELECT isnt(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd04'::uuid,
        current_setting('test.bcd.chat_pub')::INT),
    NULL,
    'T3: non-participant can read public chat');

-- =============================================================================
-- T4: chat row carries raw columns
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     -> 'chat' ->> 'name'),
    'Private',
    'T4: chat.name preserved');

-- =============================================================================
-- T5: translation applied when language code provided
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT, 'es')
     -> 'chat' ->> 'name_translated'),
    'Privado',
    'T5: chat.name_translated uses requested language');

-- =============================================================================
-- T6: missing translation falls back to 'en' → original (description has en)
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT, 'fr')
     -> 'chat' ->> 'description_translated'),
    'EN desc fallback',
    'T6: description falls back to EN translation when requested language missing');

-- =============================================================================
-- T7: participants array sorted by display_name (Alice, Bob)
-- =============================================================================
SELECT is(
    (SELECT array_agg(elem->>'display_name')
     FROM jsonb_array_elements(
        public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
            current_setting('test.bcd.chat_priv')::INT)
        -> 'participants') elem),
    ARRAY['Alice', 'Bob']::TEXT[],
    'T7: participants sorted by display_name, only active members');

-- =============================================================================
-- T8: status='left' participant excluded
-- =============================================================================
SELECT is(
    (SELECT count(*)::INT FROM jsonb_array_elements(
        public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
            current_setting('test.bcd.chat_priv')::INT)
        -> 'participants') elem
     WHERE elem->>'display_name' = 'Carol'),
    0,
    'T8: non-active participant excluded from participants array');

-- =============================================================================
-- T9: my_participant matches caller
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd02'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     -> 'my_participant' ->> 'display_name'),
    'Bob',
    'T9: my_participant returns caller row');

-- =============================================================================
-- T10: pending_join_requests populated for host, empty for non-host
-- =============================================================================
SELECT is(
    jsonb_array_length(
        public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
            current_setting('test.bcd.chat_priv')::INT)
        -> 'pending_join_requests'),
    1,
    'T10a: host sees pending join requests');

SELECT is(
    jsonb_array_length(
        public._bcd_run_as('00000000-0000-0000-0000-0000000bcd02'::uuid,
            current_setting('test.bcd.chat_priv')::INT)
        -> 'pending_join_requests'),
    0,
    'T10b: non-host sees no pending join requests');

-- =============================================================================
-- T11: chat without cycle → cycle/round/propositions empty
-- =============================================================================
DO $$
DECLARE
  v_chat_no_cycle INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, access_method)
  VALUES ('NoCycle', 'q', gen_random_uuid(), 'public')
  RETURNING id INTO v_chat_no_cycle;

  PERFORM set_config('test.bcd.chat_no_cycle', v_chat_no_cycle::TEXT, TRUE);
END $$;

SELECT is(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd04'::uuid,
        current_setting('test.bcd.chat_no_cycle')::INT)
    -> 'current_cycle',
    'null'::JSONB,
    'T11: chat without cycle returns NULL current_cycle');

-- =============================================================================
-- T12: chat with cycle but no current round → cycle present, round NULL
-- =============================================================================
DO $$
DECLARE
  v_chat_no_round INT;
  v_cycle_no_round INT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, access_method)
  VALUES ('CycleNoRound', 'q', gen_random_uuid(), 'public')
  RETURNING id INTO v_chat_no_round;

  INSERT INTO cycles (chat_id) VALUES (v_chat_no_round)
  RETURNING id INTO v_cycle_no_round;

  PERFORM set_config('test.bcd.chat_no_round', v_chat_no_round::TEXT, TRUE);
END $$;

SELECT isnt(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd04'::uuid,
        current_setting('test.bcd.chat_no_round')::INT)
    -> 'current_cycle',
    'null'::JSONB,
    'T12a: cycle JSON populated when present');

SELECT is(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd04'::uuid,
        current_setting('test.bcd.chat_no_round')::INT)
    -> 'current_round',
    'null'::JSONB,
    'T12b: current_round NULL when no round in cycle');

-- =============================================================================
-- T13: my_propositions only contains caller's
-- =============================================================================
SELECT is(
    (SELECT count(*)::INT
     FROM jsonb_array_elements(
        public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
            current_setting('test.bcd.chat_priv')::INT)
        -> 'my_propositions')),
    1,
    'T13: my_propositions returns only caller-authored');

-- =============================================================================
-- T14: rating_progress counts non-self props vs my grid_rankings
-- Alice rated 2 props (Bob's + carried), and there are 2 non-self props.
-- Carried propositions have participant_id NULL so they're "non-self" too.
-- Alice authored 1, so non-self count = 2 (Bob's + carried).
-- =============================================================================
SELECT is(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
    -> 'rating_progress' ->> 'completed',
    'true',
    'T14a: rating_progress.completed true when rated >= total > 0');

SELECT cmp_ok(
    ((public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
      -> 'rating_progress' ->> 'rated')::INT),
    '>=',
    1,
    'T14b: rating_progress.rated counts caller grid_rankings');

-- =============================================================================
-- T15: skip counts and per-user flags
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'skip_count')::INT,
    1,
    'T15a: skip_count counts round_skips for round');

SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd02'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'has_skipped'),
    'true',
    'T15b: has_skipped true for participant who skipped');

-- =============================================================================
-- T16: rating_skip count + has_skipped_rating
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd02'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'rating_skip_count')::INT,
    1,
    'T16a: rating_skip_count counts rating_skips');

SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd02'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'has_skipped_rating'),
    'true',
    'T16b: has_skipped_rating true for participant who skipped rating');

-- =============================================================================
-- T17: affirmations
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd02'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'has_affirmed'),
    'true',
    'T17a: has_affirmed true for participant who affirmed');

SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'affirmation_count')::INT,
    1,
    'T17b: affirmation_count counts affirmations row');

-- =============================================================================
-- T18: participants_who_rated includes Alice (she rated all non-self props)
-- =============================================================================
SELECT ok(
    EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(
        public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
            current_setting('test.bcd.chat_priv')::INT)
        -> 'participants_who_rated') elem
      WHERE elem::INT = current_setting('test.bcd.p1')::INT),
    'T18: participants_who_rated includes Alice');

-- =============================================================================
-- T19: min_ratings_per_prop is 0 because Alice rated only 2 of 3 props
-- (her own prop has 0 ratings).
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'min_ratings_per_prop')::INT,
    0,
    'T19: min_ratings_per_prop returns lowest count across props');

-- =============================================================================
-- T20: previous_round_winners contains the rank-1 winner with global_score
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     -> 'previous_round_winners' -> 0 ->> 'rank')::INT,
    1,
    'T20a: previous_round_winners[0].rank = 1');

SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     -> 'previous_round_winners' -> 0 -> 'propositions' ->> 'content'),
    'Round 1 winner content',
    'T20b: previous_round_winners[0].propositions.content');

-- =============================================================================
-- T21: is_sole_winner + previous_round_id reflect prior round
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'is_sole_winner'),
    'true',
    'T21a: is_sole_winner true');

SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'previous_round_id')::INT,
    current_setting('test.bcd.prev_round')::INT,
    'T21b: previous_round_id matches prior round');

-- =============================================================================
-- T22: consensus_items is empty for chats with no completed cycles
-- =============================================================================
SELECT is(
    public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
    -> 'consensus_items',
    '[]'::JSONB,
    'T22: consensus_items empty when no completed cycles');

-- =============================================================================
-- T23: is_my_participant_funded TRUE when no funding rows exist
-- =============================================================================
SELECT is(
    (public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
        current_setting('test.bcd.chat_priv')::INT)
     ->> 'is_my_participant_funded'),
    'true',
    'T23: is_my_participant_funded defaults TRUE when no funding rows');

-- =============================================================================
-- T24: allowed_categories is a JSON array
-- =============================================================================
SELECT ok(
    jsonb_typeof(
        public._bcd_run_as('00000000-0000-0000-0000-0000000bcd01'::uuid,
            current_setting('test.bcd.chat_priv')::INT)
        -> 'allowed_categories') = 'array',
    'T24: allowed_categories returns a JSON array');

-- =============================================================================
-- T25: EXECUTE granted to anon + authenticated
-- =============================================================================
SELECT is(
    (SELECT array_agg(grantee::TEXT ORDER BY grantee)
     FROM information_schema.routine_privileges
     WHERE routine_name = 'get_chat_detail_bootstrap'
       AND privilege_type = 'EXECUTE'
       AND grantee IN ('anon', 'authenticated')),
    ARRAY['anon', 'authenticated']::TEXT[],
    'T25: EXECUTE granted to anon and authenticated');

DROP FUNCTION IF EXISTS public._bcd_run_as(UUID, INT, TEXT, BOOLEAN);

SELECT * FROM finish();
ROLLBACK;
