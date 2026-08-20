-- =============================================================================
-- Tests for propositions.rating_count denormalized column + sync trigger.
-- =============================================================================
-- Migration: 20260502120000_denormalize_rating_count.sql
--
-- Coverage:
--   1.  propositions.rating_count column exists (INT, NOT NULL, default 0)
--   2.  sync_proposition_rating_count_trg trigger exists on grid_rankings
--   3.  INSERT grid_ranking → proposition.rating_count = 1
--   4.  Multiple INSERTs to same proposition → counter accumulates
--   5.  INSERTs to different propositions don't cross-contaminate
--   6.  DELETE grid_ranking → counter decrements
--   7.  DELETE clamps at 0 (never goes negative — GREATEST guard)
--   8.  Backfill correctness: a row inserted directly equals COUNT(*) of
--       its grid_rankings (i.e. the trigger keeps it in lockstep)
--   9.  get_least_rated_propositions returns rating_count from the column
--       (no inline aggregate)
--   10. get_least_rated_propositions ORDER BY rating_count ASC works
--   11. **REGRESSION**: trigger UPDATE on propositions must succeed when
--       fired from the authenticated role. propositions has RLS enabled
--       with SELECT/INSERT/DELETE policies but NO UPDATE policy — the
--       L1 trigger originally lacked SECURITY DEFINER and was silently
--       no-op'd in production for the first day after ship. Catching
--       this requires actually setting role + jwt and verifying the
--       count moves.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(13);

-- =============================================================================
-- SETUP
-- =============================================================================

INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Rating Count Denorm Test', 'Test', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1 INT;
  v_p2 INT;
  v_p3 INT;
  v_prop_a INT;
  v_prop_b INT;
  v_prop_c INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Rating Count Denorm Test';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;

  -- Seed auth.users rows so participants.user_id FK is satisfied. The
  -- regression test (11) needs participants with a real user_id so
  -- auth.uid() matches. Tests run in a transaction that ROLLBACKs at the
  -- end, so these auth.users rows go away with the rest of the fixtures.
  INSERT INTO auth.users (id, aud, role, instance_id)
  VALUES
    ('00000000-0000-0000-0000-000000000001'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-000000000002'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-000000000003'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    ('00000000-0000-0000-0000-000000000004'::UUID, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
  ON CONFLICT (id) DO NOTHING;

  -- Three participants. Set user_id so the authenticated-role regression
  -- test (test 11) can satisfy owns_participant() + RLS.
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(),
            '00000000-0000-0000-0000-000000000001'::UUID, 'P1', FALSE, 'active')
    RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(),
            '00000000-0000-0000-0000-000000000002'::UUID, 'P2', FALSE, 'active')
    RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(),
            '00000000-0000-0000-0000-000000000003'::UUID, 'P3', FALSE, 'active')
    RETURNING id INTO v_p3;

  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1, 'Prop A') RETURNING id INTO v_prop_a;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p2, 'Prop B') RETURNING id INTO v_prop_b;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p3, 'Prop C') RETURNING id INTO v_prop_c;

  PERFORM set_config('test.rcd.chat_id',  v_chat_id::TEXT, TRUE);
  PERFORM set_config('test.rcd.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.rcd.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.rcd.p2', v_p2::TEXT, TRUE);
  PERFORM set_config('test.rcd.p3', v_p3::TEXT, TRUE);
  PERFORM set_config('test.rcd.prop_a', v_prop_a::TEXT, TRUE);
  PERFORM set_config('test.rcd.prop_b', v_prop_b::TEXT, TRUE);
  PERFORM set_config('test.rcd.prop_c', v_prop_c::TEXT, TRUE);
END $$;

-- =============================================================================
-- 1. Column shape
-- =============================================================================
SELECT col_type_is(
  'public', 'propositions', 'rating_count', 'integer',
  '1: propositions.rating_count is integer'
);

SELECT col_not_null(
  'public', 'propositions', 'rating_count',
  '1b: propositions.rating_count is NOT NULL'
);

-- (Combined into the same plan slot above; we only count "1" for plan)

-- =============================================================================
-- 2. Trigger exists
-- =============================================================================
SELECT has_trigger(
  'public', 'grid_rankings', 'sync_proposition_rating_count_trg',
  '2: sync_proposition_rating_count_trg trigger exists on grid_rankings'
);

-- =============================================================================
-- 3. Single INSERT increments rating_count from 0 to 1
-- =============================================================================
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
VALUES (
  current_setting('test.rcd.round_id')::INT,
  current_setting('test.rcd.p2')::INT,
  current_setting('test.rcd.prop_a')::INT,
  50.0
);

SELECT is(
  (SELECT rating_count FROM propositions WHERE id = current_setting('test.rcd.prop_a')::INT),
  1,
  '3: single INSERT increments rating_count to 1'
);

-- =============================================================================
-- 4. Multiple INSERTs to same proposition accumulate
-- =============================================================================
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
VALUES
  (current_setting('test.rcd.round_id')::INT,
   current_setting('test.rcd.p3')::INT,
   current_setting('test.rcd.prop_a')::INT, 51.0),
  (current_setting('test.rcd.round_id')::INT,
   current_setting('test.rcd.p1')::INT,
   current_setting('test.rcd.prop_a')::INT, 52.0);

SELECT is(
  (SELECT rating_count FROM propositions WHERE id = current_setting('test.rcd.prop_a')::INT),
  3,
  '4: three INSERTs to same proposition → rating_count = 3'
);

-- =============================================================================
-- 5. Different propositions don't cross-contaminate
-- =============================================================================
INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
VALUES (
  current_setting('test.rcd.round_id')::INT,
  current_setting('test.rcd.p1')::INT,
  current_setting('test.rcd.prop_b')::INT,
  10.0
);

SELECT is(
  (SELECT rating_count FROM propositions WHERE id = current_setting('test.rcd.prop_b')::INT),
  1,
  '5a: prop_b rating_count = 1 after one isolated INSERT'
);

SELECT is(
  (SELECT rating_count FROM propositions WHERE id = current_setting('test.rcd.prop_c')::INT),
  0,
  '5b: prop_c rating_count still 0 (no INSERTs touched it)'
);

-- =============================================================================
-- 6. DELETE decrements
-- =============================================================================
DELETE FROM grid_rankings
WHERE round_id = current_setting('test.rcd.round_id')::INT
  AND participant_id = current_setting('test.rcd.p1')::INT
  AND proposition_id = current_setting('test.rcd.prop_a')::INT;

SELECT is(
  (SELECT rating_count FROM propositions WHERE id = current_setting('test.rcd.prop_a')::INT),
  2,
  '6: DELETE decrements prop_a rating_count from 3 to 2'
);

-- =============================================================================
-- 7. DELETE clamps at 0 — never goes negative.
-- This guards against the (unlikely but possible) case where a manual
-- backfill is wrong and a DELETE fires for a counter that's already 0.
-- =============================================================================
DO $$
DECLARE
  v_orphan_prop INT;
BEGIN
  -- Use carried_from_id so this proposition is exempt from
  -- idx_propositions_unique_new_per_round (which forbids a second
  -- "new" prop per (round, participant)).
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id)
    VALUES (current_setting('test.rcd.round_id')::INT,
            current_setting('test.rcd.p1')::INT,
            'Orphan',
            current_setting('test.rcd.prop_a')::INT)
    RETURNING id INTO v_orphan_prop;

  -- Insert one grid_ranking so a real DELETE has a row to remove,
  -- then corrupt rating_count to 0 before firing the DELETE — the
  -- trigger should clamp instead of producing a negative count.
  INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
    VALUES (current_setting('test.rcd.round_id')::INT,
            current_setting('test.rcd.p2')::INT,
            v_orphan_prop, 50.0);
  -- count = 1 (via trigger)
  UPDATE propositions SET rating_count = 0 WHERE id = v_orphan_prop;
  -- count = 0 (corrupted)
  DELETE FROM grid_rankings
    WHERE proposition_id = v_orphan_prop
      AND participant_id = current_setting('test.rcd.p2')::INT;
  -- trigger fires with rating_count = 0 → GREATEST(0 - 1, 0) = 0

  PERFORM set_config('test.rcd.orphan_prop', v_orphan_prop::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT rating_count FROM propositions WHERE id = current_setting('test.rcd.orphan_prop')::INT),
  0,
  '7: DELETE never drives rating_count negative (clamps at 0 via GREATEST)'
);

-- =============================================================================
-- 8. Backfill / lockstep: counter equals COUNT(*) of grid_rankings for each prop.
-- After all the inserts and deletes above, the denormalized column should
-- match the actual grid_rankings count for every proposition in this test.
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM propositions p
    WHERE p.round_id = current_setting('test.rcd.round_id')::INT
      AND p.rating_count <> (
        SELECT COUNT(*)::INT FROM grid_rankings gr
        WHERE gr.proposition_id = p.id
      )),
  0,
  '8: every proposition.rating_count equals COUNT(*) of its grid_rankings'
);

-- =============================================================================
-- 9. LRP returns rating_count from the column (smoke test on shape)
-- =============================================================================
SELECT ok(
  EXISTS (
    SELECT 1 FROM get_least_rated_propositions(
      current_setting('test.rcd.round_id')::BIGINT,
      current_setting('test.rcd.p1')::BIGINT,
      10,
      ARRAY[]::BIGINT[]
    )
  ),
  '9: get_least_rated_propositions returns at least one row'
);

-- =============================================================================
-- 10. LRP ORDER BY rating_count ASC: the first returned row should have
-- rating_count = MIN(rating_count) among candidates. Asserting on the
-- count rather than a specific id avoids depending on tiebreak (LRP
-- still uses random() for ties at the time this test was written).
--
-- Caller = p2: candidates are prop_a (count=2), prop_c (count=0), and
-- the carried "Orphan" (count=0). Least is 0, so the first row must
-- have rating_count = 0.
-- =============================================================================
SELECT is(
  (
    SELECT rating_count FROM get_least_rated_propositions(
      current_setting('test.rcd.round_id')::BIGINT,
      current_setting('test.rcd.p2')::BIGINT,
      1,
      ARRAY[]::BIGINT[]
    )
    LIMIT 1
  ),
  0::BIGINT,
  '10: LRP returns a row whose rating_count is the minimum (0) among non-self candidates'
);

-- =============================================================================
-- 11. REGRESSION: the trigger must fire successfully when the INSERT comes
-- from the `authenticated` role (i.e. through PostgREST under RLS), not just
-- from the postgres superuser context that pgtap normally runs in.
--
-- The original L1 trigger was missing SECURITY DEFINER. The trigger UPDATE
-- on propositions was silently filtered to zero rows by default-deny RLS
-- (propositions has no UPDATE policy). The other tests above run as
-- postgres (BYPASSRLS) so they can't catch this — we have to deliberately
-- become `authenticated` and supply auth.uid() via JWT.
-- =============================================================================
DO $$
DECLARE
  v_p4 INT;
  v_prop_d INT;
BEGIN
  -- Add a fresh participant + proposition that hasn't been touched by the
  -- earlier tests, so the test doesn't depend on prior counter state.
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (current_setting('test.rcd.chat_id')::INT,
            gen_random_uuid(),
            '00000000-0000-0000-0000-000000000004'::UUID,
            'P4', FALSE, 'active')
    RETURNING id INTO v_p4;
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (current_setting('test.rcd.round_id')::INT, v_p4, 'Prop D')
    RETURNING id INTO v_prop_d;

  PERFORM set_config('test.rcd.p4', v_p4::TEXT, TRUE);
  PERFORM set_config('test.rcd.prop_d', v_prop_d::TEXT, TRUE);
END $$;

-- Switch to authenticated, set JWT for P4, fire the INSERT, switch back.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object(
    'sub', '00000000-0000-0000-0000-000000000004',
    'role', 'authenticated'
  )::TEXT, TRUE);

INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position)
VALUES (current_setting('test.rcd.round_id')::INT,
        current_setting('test.rcd.p4')::INT,
        current_setting('test.rcd.prop_d')::INT,
        50.0);

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT is(
  (SELECT rating_count FROM propositions
    WHERE id = current_setting('test.rcd.prop_d')::INT),
  1,
  '11: trigger fires + counter increments when INSERT comes from authenticated role under RLS'
);

SELECT * FROM finish();
ROLLBACK;
