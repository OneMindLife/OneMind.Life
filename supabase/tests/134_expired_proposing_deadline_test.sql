-- =============================================================================
-- TESTS: Deadline rules for expired continuous-chat proposing rounds
--   Migration: supabase/migrations/20260704161000_expired_proposing_deadline_rules.sql
--
-- maybe_resolve_expired_proposing(round_id) is called by process-timers at
-- timer expiry INSTEAD of extending. Gates: continuous chat, R2+ (carried prop
-- exists), grace of 2 × proposing_duration since phase_started_at. Then:
--   0 challengers + >= 1 NON-AUTHOR affirm → 'converged' (carried leader wins)
--   >= 2 challengers, or 1 challenger + >= 1 non-author affirm → 'advanced'
--   otherwise → 'none' (caller extends as before)
--
-- Coverage:
--   T1  'none' before the grace window, even with a valid non-author affirm
--   T2  'none' for an R1 round (no carried proposition)
--   T3  'none' for a quick chat (max_cycles = 1)
--   T4  'none' when ONLY the carried author affirmed (no self-second)
--   T5  'none' with 1 challenger and zero non-author affirms
--   T6  'converged' when seconded and unchallenged
--   T7  ...the carried prop is the round winner (sole winner)
--   T8  ...2nd consecutive win → the cycle sealed (confirmation cap = 2)
--   T9  'advanced' with 1 challenger + 1 non-author affirm
--   T10 ...phase is now 'rating' with a timer set
--   T11 'advanced' with 2 challengers and zero affirms
--   T12 second call after resolution returns 'none' (idempotent)
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-00000000d401'::uuid, 'authenticated', 'ddl_u1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-00000000d402'::uuid, 'authenticated', 'ddl_u2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-00000000d403'::uuid, 'authenticated', 'ddl_u3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

-- Fixture builder: a chat whose R1 was won by P1's prop, leaving R2 in
-- proposing with the winner carried forward. phase_started_at is backdated
-- p_minutes_ago so the grace window (2 × 300s = 10 min) can be controlled.
CREATE TEMP TABLE deadline_fixtures (
  key TEXT PRIMARY KEY,
  chat_id BIGINT, cycle_id BIGINT, r2_id BIGINT,
  carried_id BIGINT, carried_author BIGINT,
  p1 BIGINT, p2 BIGINT, p3 BIGINT
);

CREATE FUNCTION pg_temp.mk_fixture(p_key TEXT, p_max_cycles INT, p_minutes_ago INT)
RETURNS VOID LANGUAGE plpgsql AS $fixture$
DECLARE
  v_chat BIGINT; v_cycle BIGINT; v_r1 BIGINT; v_r2 BIGINT;
  v_p1 BIGINT; v_p2 BIGINT; v_p3 BIGINT;
  v_win BIGINT; v_carried BIGINT; v_carried_author BIGINT;
BEGIN
  -- confirmation_rounds_required = 2 (the DB cap): an unchallenged R2 win by
  -- the carried prop is the 2nd consecutive win → the cycle SEALS. T8 asserts
  -- exactly that.
  INSERT INTO chats (name, initial_message, creator_session_token,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent, proposing_threshold_count,
                     rating_threshold_percent, rating_threshold_count,
                     proposing_duration_seconds, rating_duration_seconds,
                     confirmation_rounds_required, max_cycles)
  VALUES ('Deadline ' || p_key, 'Q?', gen_random_uuid(),
          2, 2, NULL, NULL, NULL, NULL, 300, 300, 2, p_max_cycles)
  RETURNING id INTO v_chat;
  -- start_mode defaults to 'manual', which the deadline function (rightly)
  -- refuses to touch — these fixtures model timer-driven chats.
  UPDATE chats SET start_mode = 'auto' WHERE id = v_chat;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-00000000d401'::uuid, p_key || '-P1', 'active')
  RETURNING id INTO v_p1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-00000000d402'::uuid, p_key || '-P2', 'active')
  RETURNING id INTO v_p2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-00000000d403'::uuid, p_key || '-P3', 'active')
  RETURNING id INTO v_p3;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;

  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, completed_at)
  VALUES (v_cycle, 1, 'rating', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '50 minutes')
  RETURNING id INTO v_r1;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p1, p_key || ' winner') RETURNING id INTO v_win;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_r1, v_p2, p_key || ' runner-up');

  INSERT INTO round_winners (round_id, proposition_id, rank)
  VALUES (v_r1, v_win, 1);
  UPDATE rounds SET winning_proposition_id = v_win, is_sole_winner = TRUE
  WHERE id = v_r1;

  SELECT id INTO v_r2 FROM rounds WHERE cycle_id = v_cycle AND custom_id = 2;
  UPDATE rounds SET phase = 'proposing' WHERE id = v_r2;
  -- Backdate in a SEPARATE statement: phase-transition triggers may stamp
  -- phase_started_at = NOW() on the phase change and would overwrite this.
  UPDATE rounds
  SET phase_started_at = NOW() - make_interval(mins => p_minutes_ago),
      phase_ends_at = NOW() - INTERVAL '1 minute'
  WHERE id = v_r2;

  SELECT id, participant_id INTO v_carried, v_carried_author
  FROM propositions WHERE round_id = v_r2 AND carried_from_id IS NOT NULL
  LIMIT 1;

  INSERT INTO deadline_fixtures VALUES
    (p_key, v_chat, v_cycle, v_r2, v_carried, v_carried_author, v_p1, v_p2, v_p3);
END;
$fixture$;

-- Fixtures: grace satisfied at 15 min (>= 10 min); H is inside grace at 5 min.
SELECT pg_temp.mk_fixture('A', NULL, 15);  -- converge path
SELECT pg_temp.mk_fixture('B', NULL, 15);  -- 1 challenger + non-author affirm
SELECT pg_temp.mk_fixture('C', NULL, 15);  -- 2 challengers
SELECT pg_temp.mk_fixture('D', NULL, 15);  -- 1 challenger only
SELECT pg_temp.mk_fixture('E', NULL, 15);  -- author-only affirm
SELECT pg_temp.mk_fixture('F', 1,    15);  -- quick chat
SELECT pg_temp.mk_fixture('H', NULL, 5);   -- inside grace

-- G: an R1-only chat (no carried prop), expired.
DO $$
DECLARE
  v_chat BIGINT; v_cycle BIGINT; v_r1 BIGINT; v_p1 BIGINT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     proposing_minimum, rating_minimum,
                     proposing_threshold_percent, proposing_threshold_count,
                     proposing_duration_seconds, rating_duration_seconds)
  VALUES ('Deadline G', 'Q?', gen_random_uuid(), 2, 2, NULL, NULL, 300, 300)
  RETURNING id INTO v_chat;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-00000000d401'::uuid, 'G-P1', 'active')
  RETURNING id INTO v_p1;
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle, 1, 'proposing', NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '1 minute')
  RETURNING id INTO v_r1;
  INSERT INTO deadline_fixtures VALUES ('G', v_chat, v_cycle, v_r1, NULL, NULL, v_p1, NULL, NULL);
END $$;

-- Responses per fixture (direct inserts as postgres; RLS bypassed by design).
-- The all-affirm auto-resolve trigger can't fire: each fixture has 3 active
-- participants and at most 2 respond.
CREATE FUNCTION pg_temp.affirm_as(p_round BIGINT, p_participant BIGINT)
RETURNS VOID LANGUAGE sql AS $aff$
  INSERT INTO affirmations (round_id, participant_id, user_id)
  SELECT p_round, p.id, p.user_id FROM participants p WHERE p.id = p_participant;
$aff$;

DO $$
DECLARE f RECORD;
BEGIN
  -- A: P2 affirms (non-author second), nobody challenges.
  SELECT * INTO f FROM deadline_fixtures WHERE key = 'A';
  PERFORM pg_temp.affirm_as(f.r2_id, f.p2);

  -- B: P2 challenges, P3 affirms.
  SELECT * INTO f FROM deadline_fixtures WHERE key = 'B';
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (f.r2_id, f.p2, 'B challenger');
  PERFORM pg_temp.affirm_as(f.r2_id, f.p3);

  -- C: P2 and P3 both challenge.
  SELECT * INTO f FROM deadline_fixtures WHERE key = 'C';
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (f.r2_id, f.p2, 'C challenger 1');
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (f.r2_id, f.p3, 'C challenger 2');

  -- D: P2 challenges, nobody affirms.
  SELECT * INTO f FROM deadline_fixtures WHERE key = 'D';
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (f.r2_id, f.p2, 'D challenger');

  -- E: only the carried author (P1) affirms their own carried idea.
  SELECT * INTO f FROM deadline_fixtures WHERE key = 'E';
  PERFORM pg_temp.affirm_as(f.r2_id, f.carried_author);

  -- F (quick): P2 affirms — would converge if not for the quick-chat gate.
  SELECT * INTO f FROM deadline_fixtures WHERE key = 'F';
  PERFORM pg_temp.affirm_as(f.r2_id, f.p2);

  -- H (inside grace): P2 affirms — would converge if grace had elapsed.
  SELECT * INTO f FROM deadline_fixtures WHERE key = 'H';
  PERFORM pg_temp.affirm_as(f.r2_id, f.p2);
END $$;

-- -----------------------------------------------------------------------------
-- T1: inside grace → 'none'
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'H')),
  'none',
  'T1: no resolution before 2× proposing duration has elapsed'
);

-- -----------------------------------------------------------------------------
-- T2: R1 (no carried prop) → 'none'
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'G')),
  'none',
  'T2: R1 rounds are untouched (no carried proposition)'
);

-- -----------------------------------------------------------------------------
-- T3: quick chat → 'none'
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'F')),
  'none',
  'T3: quick chats (max_cycles = 1) are excluded'
);

-- -----------------------------------------------------------------------------
-- T4: author-only affirm → 'none' (no self-second)
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'E')),
  'none',
  'T4: the carried author''s own affirm does not count as the second'
);

-- -----------------------------------------------------------------------------
-- T5: 1 challenger, no non-author affirm → 'none'
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'D')),
  'none',
  'T5: a lone challenger without an engaged affirmer keeps extending'
);

-- -----------------------------------------------------------------------------
-- T6-T8: seconded + unchallenged → converged, carried prop wins, next round
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'A')),
  'converged',
  'T6: 0 challengers + 1 non-author affirm converges at the deadline'
);

SELECT ok(
  (SELECT r.winning_proposition_id = f.carried_id AND r.is_sole_winner
   FROM rounds r JOIN deadline_fixtures f ON f.key = 'A' AND r.id = f.r2_id),
  'T7: the carried proposition is the round''s sole winner'
);

SELECT ok(
  (SELECT c.completed_at IS NOT NULL AND c.winning_proposition_id IS NOT NULL
   FROM cycles c JOIN deadline_fixtures f ON f.key = 'A' AND c.id = f.cycle_id),
  'T8: the unchallenged win was the 2nd consecutive — the cycle sealed'
);

-- -----------------------------------------------------------------------------
-- T9-T10: 1 challenger + non-author affirm → rating opens
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'B')),
  'advanced',
  'T9: 1 challenger + 1 non-author affirm opens rating at the deadline'
);

SELECT ok(
  (SELECT r.phase = 'rating' AND r.phase_ends_at IS NOT NULL
   FROM rounds r JOIN deadline_fixtures f ON f.key = 'B' AND r.id = f.r2_id),
  'T10: the round is in rating with a timer set'
);

-- -----------------------------------------------------------------------------
-- T11: 2 challengers, zero affirms → rating opens
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'C')),
  'advanced',
  'T11: 2 challengers open rating regardless of affirms'
);

-- -----------------------------------------------------------------------------
-- T12: idempotence — a resolved round returns 'none'
-- -----------------------------------------------------------------------------
SELECT is(
  maybe_resolve_expired_proposing((SELECT r2_id FROM deadline_fixtures WHERE key = 'B')),
  'none',
  'T12: calling again after resolution is a no-op'
);

SELECT * FROM finish();
ROLLBACK;
