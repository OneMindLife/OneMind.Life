-- =============================================================================
-- Tests: rounds.participation_percent recomputes when participants join/leave.
-- =============================================================================
-- Migration: 20260706150000_recompute_participation_on_join_leave.sql
--
-- Coverage:
--   1. Both participant triggers exist and are SECURITY DEFINER.
--   2. Wrapper function exists + is DEFINER.
--   3. Baseline: 2 active, 1 proposed → 50%.
--   4. JOIN (INSERT active) → denominator 2→3 → 1 of 3 → 33%.
--   5. LEAVE (UPDATE status='left') → denominator 3→2 → 1 of 2 → 50%.
--   6. DELETE participant → denominator drops → recomputes.
--   7. Status UPDATE that does NOT change status → no spurious change
--      (WHEN guard holds; percent stays consistent with active count).
--   8. REGRESSION: JOIN performed as the authenticated role updates
--      rounds.participation_percent — proves the trigger's cross-table UPDATE
--      goes through the SECURITY DEFINER bypass (the silent-no-op trap).
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(9);

-- =============================================================================
-- SETUP — chat with 2 active participants, P1 has proposed.
-- =============================================================================
DO $$
DECLARE
  v_chat_id  INT;
  v_cycle_id INT;
  v_round_id INT;
  v_p1 INT; v_p2 INT;
  v_uid1 UUID := '00000000-0000-0000-0000-0000000c0001';
  v_uid2 UUID := '00000000-0000-0000-0000-0000000c0002';
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_uid1, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_uid2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  -- High proposing_minimum so a lone proposition never trips the early-advance
  -- trigger (which would flip proposing→rating and switch the formula). We only
  -- exercise the denominator (join/leave) here, so keep the round in proposing.
  INSERT INTO chats (name, initial_message, creator_session_token, proposing_minimum)
  VALUES ('Participation join/leave test', 'Test', gen_random_uuid(), 99)
  RETURNING id INTO v_chat_id;

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'proposing') RETURNING id INTO v_round_id;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_uid1, 'P1', TRUE, 'active') RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat_id, gen_random_uuid(), v_uid2, 'P2', FALSE, 'active') RETURNING id INTO v_p2;

  PERFORM set_config('test.pjl.chat_id',  v_chat_id::TEXT,  TRUE);
  PERFORM set_config('test.pjl.round_id', v_round_id::TEXT, TRUE);
  PERFORM set_config('test.pjl.p1', v_p1::TEXT, TRUE);
  PERFORM set_config('test.pjl.p2', v_p2::TEXT, TRUE);

  -- P1 proposes → numerator = 1 of 2 active.
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_p1, 'Prop from P1');
END $$;

-- =============================================================================
-- 1. Both triggers exist and are SECURITY DEFINER.
-- =============================================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM pg_trigger t
   JOIN pg_proc p ON p.oid = t.tgfoid
   WHERE NOT t.tgisinternal
     AND t.tgrelid = 'public.participants'::regclass
     AND t.tgname IN (
       'sync_round_participation_participant_ins_del',
       'sync_round_participation_participant_status')
     AND p.prosecdef = TRUE),
  2,
  '1: both participant participation triggers exist and are SECURITY DEFINER'
);

-- =============================================================================
-- 2. Wrapper function exists.
-- =============================================================================
SELECT has_function(
  'public', 'refresh_round_participation_from_participant',
  '2: refresh_round_participation_from_participant() exists'
);

-- =============================================================================
-- 3. Baseline: 1 of 2 → 50%.
-- =============================================================================
SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.pjl.round_id')::INT),
  50,
  '3: 1 proposed of 2 active → 50%'
);

-- =============================================================================
-- 4. JOIN — a 3rd participant joins → 1 of 3 → 33%.
--    This is the exact chat-1185 scenario: joiner must dilute the percent.
-- =============================================================================
DO $$
DECLARE
  v_uid3 UUID := '00000000-0000-0000-0000-0000000c0003';
  v_p3 INT;
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_uid3, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (current_setting('test.pjl.chat_id')::INT, gen_random_uuid(), v_uid3, 'P3', FALSE, 'active')
    RETURNING id INTO v_p3;
  PERFORM set_config('test.pjl.p3', v_p3::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.pjl.round_id')::INT),
  33,
  '4: 3rd participant JOINs → 1 of 3 → 33% (denominator recomputed on INSERT)'
);

-- =============================================================================
-- 5. LEAVE — P3 leaves (status='left') → back to 1 of 2 → 50%.
-- =============================================================================
UPDATE participants SET status = 'left'
  WHERE id = current_setting('test.pjl.p3')::INT;

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.pjl.round_id')::INT),
  50,
  '5: P3 LEAVEs (status=left) → 1 of 2 → 50% (recomputed on status UPDATE)'
);

-- =============================================================================
-- 6. DELETE — P2 (the non-actor) is hard-deleted → 1 of 1 → 100%.
-- =============================================================================
DELETE FROM participants WHERE id = current_setting('test.pjl.p2')::INT;

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.pjl.round_id')::INT),
  100,
  '6: non-actor P2 DELETEd → 1 of 1 active → 100% (recomputed on DELETE)'
);

-- =============================================================================
-- 7. No-op status UPDATE (status unchanged) — percent stays 100%.
--    The WHEN guard means the trigger body need not fire; either way the
--    column must remain correct for the current active count (1 of 1).
-- =============================================================================
UPDATE participants SET display_name = 'P1 renamed'
  WHERE id = current_setting('test.pjl.p1')::INT;

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.pjl.round_id')::INT),
  100,
  '7: non-status UPDATE leaves percent correct at 100%'
);

-- =============================================================================
-- 8. REGRESSION — a JOIN (INSERT) from the authenticated role updates
--    rounds.participation_percent. Without SECURITY DEFINER the trigger UPDATE
--    on rounds is silently RLS-filtered to 0 rows and the column never moves.
--    Two active up front (host H proposes, filler F does not) so the effective
--    proposing minimum = min(99, participant_count) = 2 is NOT met by H alone —
--    the round stays in proposing at 1 of 2 = 50%. Authenticated P then joins →
--    denominator 2→3 → 1 of 3 → 33%.
-- =============================================================================
DO $$
DECLARE
  v_chat2 INT; v_cyc2 INT; v_round2 INT; v_ph INT; v_pf INT;
  v_uid_h UUID := '00000000-0000-0000-0000-0000000c0011';
  v_uid_f UUID := '00000000-0000-0000-0000-0000000c0013';
  v_uid_j UUID := '00000000-0000-0000-0000-0000000c0012';
BEGIN
  INSERT INTO auth.users (id, aud, role, instance_id) VALUES
    (v_uid_h, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_uid_f, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID),
    (v_uid_j, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::UUID)
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO chats (name, initial_message, creator_session_token, proposing_minimum)
  VALUES ('Participation join RLS regression', 'Test', gen_random_uuid(), 99)
  RETURNING id INTO v_chat2;
  INSERT INTO cycles (chat_id) VALUES (v_chat2) RETURNING id INTO v_cyc2;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cyc2, 1, 'proposing') RETURNING id INTO v_round2;

  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat2, gen_random_uuid(), v_uid_h, 'H', TRUE, 'active') RETURNING id INTO v_ph;
  INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
    VALUES (v_chat2, gen_random_uuid(), v_uid_f, 'F', FALSE, 'active') RETURNING id INTO v_pf;
  -- Only H proposes → 1 acted of 2 active; effective min = 2, so NO early
  -- advance → phase stays proposing at 50%.
  INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round2, v_ph, 'Host prop');

  PERFORM set_config('test.pjl.r2_chat',  v_chat2::TEXT,  TRUE);
  PERFORM set_config('test.pjl.r2_round', v_round2::TEXT, TRUE);
  PERFORM set_config('test.pjl.r2_uid_j', v_uid_j::TEXT,  TRUE);
END $$;

-- Sanity: baseline is 50% (1 of 2) before the authenticated join.
SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.pjl.r2_round')::INT),
  50,
  '8a (baseline): 1 proposed of 2 active → 50% before authenticated join'
);

-- Join as authenticated (own user_id = auth.uid()) → INSERT allowed by RLS.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', current_setting('test.pjl.r2_uid_j'),
                    'role', 'authenticated')::TEXT, TRUE);

INSERT INTO participants (chat_id, session_token, user_id, display_name, is_host, status)
VALUES (current_setting('test.pjl.r2_chat')::INT, gen_random_uuid(),
        current_setting('test.pjl.r2_uid_j')::UUID, 'Joiner', FALSE, 'active');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT is(
  (SELECT participation_percent FROM rounds
    WHERE id = current_setting('test.pjl.r2_round')::INT),
  33,
  '8: authenticated JOIN → 1 of 3 → 33% (trigger UPDATE on rounds went through SECURITY DEFINER bypass)'
);

SELECT * FROM finish();
ROLLBACK;
