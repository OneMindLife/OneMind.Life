-- =============================================================================
-- TESTS: get_global_winners RPC
--   Migration: supabase/migrations/20260818170000_get_global_winners.sql
--
-- Single round-trip permanent record for the continuous Global room. Tests that
-- the resolved snapshot matches the old 4-query fan-out the wedge used to run,
-- plus the access-control guards.
--
-- Coverage:
--   T1   missing chat → '[]'
--   T2   non-participant + private chat → '[]'
--   T3   public chat is readable by an outsider
--   T4   only SEALED rounds returned (in-progress round excluded)
--   T5   ordered oldest→newest by r.id
--   T6   text carries the winner's content
--   T7   beat = props-in-round − 1 (3 props → 2)
--   T8   beat clamped to 0 when the round has a single prop
--   T9   voters dedupes across rating_completions ∪ grid_rankings
--   T10  voters counts rating_completions-only round
--   T11  translation applied when language code provided
--   T12  missing translation falls back to the original content
--   T13  winning_participant_id is the winning author
--   T14  time_iso serialized as a JSON string
--   T15  EXECUTE granted to anon + authenticated
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(15);

-- -----------------------------------------------------------------------------
-- SETUP: private chat (participants Alice/Bob) + public chat, each with sealed
-- rounds; a third in-progress round that must be excluded.
-- -----------------------------------------------------------------------------
INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-0000000bcd11'::uuid, 'authenticated', 'gwr_u1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000bcd12'::uuid, 'authenticated', 'gwr_u2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-0000000bcd13'::uuid, 'authenticated', 'gwr_out@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

DO $$
DECLARE
  v_chat_priv INT;
  v_chat_pub  INT;
  v_cyc       INT;
  v_rA        INT;  -- newer sealed round (3 props → beat 2; 2 voters)
  v_rB        INT;  -- older sealed round (1 prop  → beat 0; 1 voter)
  v_rC        INT;  -- in-progress (winner NULL → excluded)
  v_p1        INT;
  v_p2        INT;
  v_propA_win INT;
  v_propB_win INT;
  v_propP_win INT;
BEGIN
  SET LOCAL session_replication_role = 'replica';

  INSERT INTO chats (name, initial_message, creator_session_token, access_method, proposing_minimum, rating_minimum)
  VALUES ('Priv', 'q', gen_random_uuid(), 'invite_only', 3, 3)
  RETURNING id INTO v_chat_priv;

  INSERT INTO chats (name, initial_message, creator_session_token, access_method, proposing_minimum, rating_minimum)
  VALUES ('Pub', 'q', gen_random_uuid(), 'public', 3, 3)
  RETURNING id INTO v_chat_pub;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_priv, '00000000-0000-0000-0000-0000000bcd11'::uuid, 'Alice', true, 'active')
  RETURNING id INTO v_p1;

  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (v_chat_priv, '00000000-0000-0000-0000-0000000bcd12'::uuid, 'Bob', false, 'active')
  RETURNING id INTO v_p2;

  INSERT INTO cycles (chat_id) VALUES (v_chat_priv) RETURNING id INTO v_cyc;

  -- Older sealed round B: 1 prop → beat 0; 1 voter (rating_completions only).
  INSERT INTO rounds (cycle_id, custom_id, phase, completed_at)
  VALUES (v_cyc, 1, 'rating', now() - INTERVAL '2 hours')
  RETURNING id INTO v_rB;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_rB, v_p1, 'B winner')
  RETURNING id INTO v_propB_win;
  UPDATE rounds SET winning_proposition_id = v_propB_win WHERE id = v_rB;
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_rB, v_propB_win, 1);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_rB, v_p1);

  -- Newer sealed round A: 3 props → beat 2; p1 + p2 vote, p2 ALSO in
  -- grid_rankings so the distinct union must still yield 2.
  INSERT INTO rounds (cycle_id, custom_id, phase, completed_at)
  VALUES (v_cyc, 2, 'rating', now() - INTERVAL '1 hour')
  RETURNING id INTO v_rA;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_rA, v_p1, 'A winner')
  RETURNING id INTO v_propA_win;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_rA, v_p2, 'A second');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_rA, v_p2, 'A third');
  UPDATE rounds SET winning_proposition_id = v_propA_win WHERE id = v_rA;
  INSERT INTO round_winners (round_id, proposition_id, rank) VALUES (v_rA, v_propA_win, 1);
  INSERT INTO rating_completions (round_id, participant_id) VALUES (v_rA, v_p1), (v_rA, v_p2);
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
  VALUES (v_rA, v_p2, v_propA_win, 50.0);

  -- Spanish translation for round A's winner (fallback otherwise).
  INSERT INTO translations (proposition_id, entity_type, field_name, language_code, translated_text)
  VALUES (v_propA_win, 'proposition', 'content', 'es', 'Ganador A');

  -- In-progress round (excluded from the record).
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cyc, 3, 'proposing') RETURNING id INTO v_rC;

  -- Public chat: one sealed round with an anon-authored winner (participant NULL).
  INSERT INTO cycles (chat_id) VALUES (v_chat_pub) RETURNING id INTO v_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase, completed_at)
  VALUES (v_cyc, 1, 'rating', now() - INTERVAL '3 hours');
  INSERT INTO propositions (round_id, participant_id, content)
  SELECT id, NULL, 'Pub winner' FROM rounds WHERE cycle_id = v_cyc ORDER BY id DESC LIMIT 1
  RETURNING id INTO v_propP_win;
  UPDATE rounds SET winning_proposition_id = v_propP_win WHERE id = (SELECT id FROM rounds WHERE cycle_id = v_cyc LIMIT 1);

  PERFORM set_config('test.gwr.chat_priv', v_chat_priv::TEXT, TRUE);
  PERFORM set_config('test.gwr.chat_pub', v_chat_pub::TEXT, TRUE);
  PERFORM set_config('test.gwr.rA', v_rA::TEXT, TRUE);
  PERFORM set_config('test.gwr.rB', v_rB::TEXT, TRUE);
  PERFORM set_config('test.gwr.p1', v_p1::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- HELPER: run as a specific user
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._gwr_run_as(p_user UUID, p_chat INT, p_lang TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user::TEXT, 'role', 'authenticated')::TEXT, TRUE);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_result := public.get_global_winners(p_chat, p_lang);
  RESET ROLE;
  RETURN v_result;
END;
$$;

-- =============================================================================
-- T1: missing chat → '[]'
-- =============================================================================
SELECT is(
    public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid, 999999999),
    '[]'::JSONB,
    'T1: missing chat returns empty array');

-- =============================================================================
-- T2: non-participant + private chat → '[]'
-- =============================================================================
SELECT is(
    public._gwr_run_as('00000000-0000-0000-0000-0000000bcd13'::uuid,
        current_setting('test.gwr.chat_priv')::INT),
    '[]'::JSONB,
    'T2: outsider on private chat gets empty array');

-- =============================================================================
-- T3: public chat readable by outsider
-- =============================================================================
SELECT is(
    jsonb_array_length(
        public._gwr_run_as('00000000-0000-0000-0000-0000000bcd13'::uuid,
            current_setting('test.gwr.chat_pub')::INT)),
    1,
    'T3: outsider can read the public chat record');

-- =============================================================================
-- T4: only sealed rounds returned (in-progress excluded)
-- =============================================================================
SELECT is(
    jsonb_array_length(
        public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
            current_setting('test.gwr.chat_priv')::INT)),
    2,
    'T4: in-progress round excluded, 2 sealed rounds returned');

-- =============================================================================
-- T5: ordered oldest→newest by r.id
-- =============================================================================
SELECT is(
    (SELECT array_agg((elem->>'id')::INT)
     FROM jsonb_array_elements(
        public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
            current_setting('test.gwr.chat_priv')::INT)) elem),
    ARRAY[current_setting('test.gwr.rB')::INT, current_setting('test.gwr.rA')::INT]::INT[],
    'T5: ordered oldest→newest by round id');

-- =============================================================================
-- T6: text carries the winner content (index 1 = round A)
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT) -> 1 ->> 'text'),
    'A winner',
    'T6: text is the winning content');

-- =============================================================================
-- T7: beat = props-in-round − 1 (3 props → 2)
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT) -> 1 ->> 'beat')::INT,
    2,
    'T7: beat = 3 props − 1 = 2');

-- =============================================================================
-- T8: beat clamped to 0 when the round has a single prop
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT) -> 0 ->> 'beat')::INT,
    0,
    'T8: single-prop round beat = 0');

-- =============================================================================
-- T9: voters dedupes across rating_completions ∪ grid_rankings (p2 in both)
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT) -> 1 ->> 'voters')::INT,
    2,
    'T9: voters deduped to 2 across both rating tables');

-- =============================================================================
-- T10: voters counts a rating_completions-only round
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT) -> 0 ->> 'voters')::INT,
    1,
    'T10: round B has 1 voter');

-- =============================================================================
-- T11: translation applied when language code provided
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT, 'es') -> 1 ->> 'text'),
    'Ganador A',
    'T11: Spanish translation applied');

-- =============================================================================
-- T12: missing translation falls back to original content
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT, 'fr') -> 1 ->> 'text'),
    'A winner',
    'T12: missing translation falls back to original');

-- =============================================================================
-- T13: winning_participant_id is the winning author
-- =============================================================================
SELECT is(
    (public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
        current_setting('test.gwr.chat_priv')::INT) -> 1 ->> 'winning_participant_id')::INT,
    current_setting('test.gwr.p1')::INT,
    'T13: winning_participant_id is the author');

-- =============================================================================
-- T14: time_iso serialized as a JSON string
-- =============================================================================
SELECT ok(
    jsonb_typeof(
        public._gwr_run_as('00000000-0000-0000-0000-0000000bcd11'::uuid,
            current_setting('test.gwr.chat_priv')::INT) -> 1 -> 'time_iso') = 'string',
    'T14: time_iso is a JSON string');

-- =============================================================================
-- T15: EXECUTE granted to anon + authenticated
-- =============================================================================
SELECT is(
    (SELECT array_agg(grantee::TEXT ORDER BY grantee)
     FROM information_schema.routine_privileges
     WHERE routine_name = 'get_global_winners'
       AND privilege_type = 'EXECUTE'
       AND grantee IN ('anon', 'authenticated')),
    ARRAY['anon', 'authenticated']::TEXT[],
    'T15: EXECUTE granted to anon and authenticated');

DROP FUNCTION IF EXISTS public._gwr_run_as(UUID, INT, TEXT);

SELECT * FROM finish();
ROLLBACK;
