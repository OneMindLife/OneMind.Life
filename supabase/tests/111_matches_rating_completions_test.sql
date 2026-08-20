-- =============================================================================
-- Tests for rating_completions + get_matches_rating_progress.
-- Migration: 20260529210000_matches_rating_completions.sql
-- =============================================================================
-- Coverage:
--   1.  rating_completions table exists
--   2.  rc_has_rater CHECK: neither participant_id nor session_token is rejected
--   3.  unique index: a duplicate (round, participant) completion throws
--   4.  get_matches_rating_progress on an empty round → done = 0
--   5.  eligible mirrors get_rating_eligible_count(chat)
--   6.  one completion marker → done = 1
--   7.  a grid_rankings row for a 2nd participant → done = 2 (union)
--   8.  a rating_skips row for a 3rd participant → done = 3 (union)
--   9.  the same participant signalled twice (completion + grid) counts ONCE
--   10. **REGRESSION (RLS)**: authenticated rater may insert their OWN
--       completion, but NOT another participant's.
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(11);

-- =============================================================================
-- SETUP: one chat / cycle / rating round, 4 participants each owning a prop.
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('Matches Completions Test', 'Test', gen_random_uuid(), 'matches');

DO $$
DECLARE
  v_chat_id INT; v_cycle_id INT; v_round_id INT;
  v_p1 INT; v_p2 INT; v_p3 INT; v_p4 INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Matches Completions Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES
    ('00000000-0000-0000-0000-0000000000b1'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000b2'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000b3'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-0000000000b4'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1'::UUID, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2'::UUID, 'P2', FALSE, 'active') RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000b3'::UUID, 'P3', FALSE, 'active') RETURNING id INTO v_p3;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), '00000000-0000-0000-0000-0000000000b4'::UUID, 'P4', FALSE, 'active') RETURNING id INTO v_p4;

  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p1, 'Prop A');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p2, 'Prop B');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p3, 'Prop C');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (v_round_id, v_p4, 'Prop D');

  PERFORM set_config('test.chat_id', v_chat_id::text, false);
  PERFORM set_config('test.round_id', v_round_id::text, false);
  PERFORM set_config('test.p1', v_p1::text, false);
  PERFORM set_config('test.p2', v_p2::text, false);
  PERFORM set_config('test.p3', v_p3::text, false);
  PERFORM set_config('test.p4', v_p4::text, false);
END $$;

-- 1. table exists
SELECT has_table('public', 'rating_completions', 'rating_completions table exists');

-- 2. rc_has_rater CHECK
SELECT throws_ok(
  format('INSERT INTO rating_completions (round_id, participant_id, session_token) VALUES (%s, NULL, NULL)',
         current_setting('test.round_id')),
  NULL,
  'rc_has_rater rejects null participant_id AND null session_token'
);

-- 3. unique (round, participant)
SELECT lives_ok(
  format('INSERT INTO rating_completions (round_id, participant_id) VALUES (%s, %s)',
         current_setting('test.round_id'), current_setting('test.p1')),
  'first completion for P1 inserts'
);
SELECT throws_ok(
  format('INSERT INTO rating_completions (round_id, participant_id) VALUES (%s, %s)',
         current_setting('test.round_id'), current_setting('test.p1')),
  NULL,
  'duplicate completion for the same (round, participant) throws'
);

-- 4. (after P1 completion) done counts that one
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.round_id')::bigint, current_setting('test.chat_id')::bigint)),
  1,
  'one completion marker → done = 1'
);

-- 5. eligible mirrors get_rating_eligible_count
SELECT is(
  (SELECT eligible FROM get_matches_rating_progress(
     current_setting('test.round_id')::bigint, current_setting('test.chat_id')::bigint)),
  get_rating_eligible_count(current_setting('test.chat_id')::bigint),
  'eligible mirrors get_rating_eligible_count(chat)'
);

-- 6. grid_rankings row for P2 → union → done = 2
-- (a participant with any grid coverage counts as done)
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
SELECT current_setting('test.round_id')::bigint, current_setting('test.p2')::bigint,
       p.id, 50
FROM propositions p WHERE p.round_id = current_setting('test.round_id')::bigint LIMIT 1;
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.round_id')::bigint, current_setting('test.chat_id')::bigint)),
  2,
  'completion (P1) ∪ grid coverage (P2) → done = 2'
);

-- 7. rating_skips row for P3 → union → done = 3
INSERT INTO rating_skips (round_id, participant_id)
VALUES (current_setting('test.round_id')::bigint, current_setting('test.p3')::bigint);
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.round_id')::bigint, current_setting('test.chat_id')::bigint)),
  3,
  'completion ∪ grid ∪ skip → done = 3'
);

-- 8. P1 also gets a grid row → still counts ONCE (distinct)
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
SELECT current_setting('test.round_id')::bigint, current_setting('test.p1')::bigint,
       p.id, 50
FROM propositions p WHERE p.round_id = current_setting('test.round_id')::bigint LIMIT 1;
SELECT is(
  (SELECT done FROM get_matches_rating_progress(
     current_setting('test.round_id')::bigint, current_setting('test.chat_id')::bigint)),
  3,
  'a participant signalled via two tables counts once (still done = 3)'
);

-- 9/10. REGRESSION (RLS): authenticated rater inserts OWN completion, not others'.
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b4"}', true);

SELECT lives_ok(
  format('INSERT INTO rating_completions (round_id, participant_id) VALUES (%s, %s)',
         current_setting('test.round_id'), current_setting('test.p4')),
  'authenticated P4 may insert their OWN completion (RLS allows)'
);

SELECT throws_ok(
  format('INSERT INTO rating_completions (round_id, participant_id) VALUES (%s, %s)',
         current_setting('test.round_id'), current_setting('test.p2')),
  NULL,
  'authenticated P4 may NOT insert another participant''s completion (RLS blocks)'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
