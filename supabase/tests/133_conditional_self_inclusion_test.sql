-- =============================================================================
-- TESTS: Conditional self-inclusion (CSI)
--   Migration: supabase/migrations/20260704160000_conditional_self_inclusion.sql
--
-- A rater never rates their own proposition — unless excluding it would leave
-- them with fewer than 2 votable props (with propositions_per_user = 1 that
-- means: the round has exactly 2 propositions). Rounds with >= 3 props keep
-- strict self-exclusion.
--
-- Coverage:
--   T1  LRP, 3-prop round: caller's own prop excluded (strict exclusion holds)
--   T2  LRP, 2-prop round: caller's own prop INCLUDED (CSI active)
--   T3  get_propositions_for_rating, 2-prop round: own included (as user)
--   T4  get_propositions_for_rating, 3-prop round with AI prop: AI kept, own out
--   T5  early advance (grid, 2 props, 2 raters): ONE rater done ≠ advance
--       (threshold is active_raters − 0 = 2, not the old −1 = 1)
--   T6  participation percent after one rater: 50 (denominator 2, not 1)
--   T7  early advance fires once BOTH raters rated both props
--   T8  matches finalize (quick, 2 users, 2 props): first completion + 1 real
--       vote does NOT finalize (the other user is a pending ABLE voter now)
--   T9  second completion finalizes the round
--   T10 proposing→rating flip of a 2-prop/2-author round inserts NO stranded
--       auto-skips (regression: prod chat 1179 round 3594 self-destructed —
--       both marked stranded → active_raters 0 → completed with zero votes)
--   T11 ...and the round is still open after the flip
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(11);

-- -----------------------------------------------------------------------------
-- SETUP
-- -----------------------------------------------------------------------------

INSERT INTO auth.users (id, role, email, encrypted_password, instance_id, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-00000000c301'::uuid, 'authenticated', 'csi_u1@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-00000000c302'::uuid, 'authenticated', 'csi_u2@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now()),
  ('00000000-0000-0000-0000-00000000c303'::uuid, 'authenticated', 'csi_u3@test.com', crypt('password', gen_salt('bf')), '00000000-0000-0000-0000-000000000000', 'authenticated', now(), now());

DO $$
DECLARE
  v_chat2 INT; v_cycle2 INT; v_round2 INT;         -- 2-prop grid chat (X)
  v_chat3 INT; v_cycle3 INT; v_round3 INT;         -- 3-prop chat w/ AI (Y)
  v_chatm INT; v_cyclem INT; v_roundm INT;         -- 2-prop matches quick chat (M)
  v_x1 INT; v_x2 INT;
  v_y1 INT; v_y2 INT; v_y3 INT;
  v_m1 INT; v_m2 INT;
  v_px1 INT; v_px2 INT;
  v_py1 INT; v_py2 INT; v_pai INT;
  v_pm1 INT; v_pm2 INT;
BEGIN
  -- X: grid chat, 2 participants, rating round with 2 props (one each).
  -- Rating thresholds enabled so the early-advance trigger evaluates.
  INSERT INTO chats (name, initial_message, creator_session_token,
                     proposing_minimum, rating_minimum,
                     rating_threshold_percent, rating_threshold_count,
                     proposing_duration_seconds, rating_duration_seconds,
                     start_mode)
  VALUES ('CSI Grid 2p', 'Q?', gen_random_uuid(), 2, 2, 100, 2, 300, 300,
          'auto')  -- start_mode defaults to 'manual', which bails the trigger
  RETURNING id INTO v_chat2;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat2, '00000000-0000-0000-0000-00000000c301'::uuid, 'X1', 'active')
  RETURNING id INTO v_x1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat2, '00000000-0000-0000-0000-00000000c302'::uuid, 'X2', 'active')
  RETURNING id INTO v_x2;

  INSERT INTO cycles (chat_id) VALUES (v_chat2) RETURNING id INTO v_cycle2;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle2, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
  RETURNING id INTO v_round2;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round2, v_x1, 'X1 idea') RETURNING id INTO v_px1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round2, v_x2, 'X2 idea') RETURNING id INTO v_px2;

  PERFORM set_config('test.chat2', v_chat2::TEXT, TRUE);
  PERFORM set_config('test.round2', v_round2::TEXT, TRUE);
  PERFORM set_config('test.x1', v_x1::TEXT, TRUE);
  PERFORM set_config('test.x2', v_x2::TEXT, TRUE);
  PERFORM set_config('test.px1', v_px1::TEXT, TRUE);
  PERFORM set_config('test.px2', v_px2::TEXT, TRUE);

  -- Y: 3 participants, proposing... set to rating; 3 props: Y1, Y2, and an AI
  -- (NULL author). For Y1 the non-own set is {Y2, AI} = 2 → strict exclusion.
  INSERT INTO chats (name, initial_message, creator_session_token,
                     proposing_minimum, rating_minimum)
  VALUES ('CSI Grid 3p', 'Q?', gen_random_uuid(), 2, 2)
  RETURNING id INTO v_chat3;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat3, '00000000-0000-0000-0000-00000000c301'::uuid, 'Y1', 'active')
  RETURNING id INTO v_y1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat3, '00000000-0000-0000-0000-00000000c302'::uuid, 'Y2', 'active')
  RETURNING id INTO v_y2;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat3, '00000000-0000-0000-0000-00000000c303'::uuid, 'Y3', 'active')
  RETURNING id INTO v_y3;

  INSERT INTO cycles (chat_id) VALUES (v_chat3) RETURNING id INTO v_cycle3;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle3, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
  RETURNING id INTO v_round3;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round3, v_y1, 'Y1 idea') RETURNING id INTO v_py1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round3, v_y2, 'Y2 idea') RETURNING id INTO v_py2;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round3, NULL, 'AI idea') RETURNING id INTO v_pai;

  PERFORM set_config('test.round3', v_round3::TEXT, TRUE);
  PERFORM set_config('test.y1', v_y1::TEXT, TRUE);
  PERFORM set_config('test.py1', v_py1::TEXT, TRUE);
  PERFORM set_config('test.py2', v_py2::TEXT, TRUE);
  PERFORM set_config('test.pai', v_pai::TEXT, TRUE);

  -- M: quick matches chat (max_cycles = 1), 2 participants, rating round with
  -- 2 props (one each) — the wedge leader-vs-challenger shape at n = 2.
  INSERT INTO chats (name, initial_message, creator_session_token,
                     proposing_minimum, rating_minimum,
                     rating_mode, max_cycles)
  VALUES ('CSI Matches 2p', 'Q?', gen_random_uuid(), 2, 2, 'matches', 1)
  RETURNING id INTO v_chatm;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chatm, '00000000-0000-0000-0000-00000000c301'::uuid, 'M1', 'active')
  RETURNING id INTO v_m1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chatm, '00000000-0000-0000-0000-00000000c302'::uuid, 'M2', 'active')
  RETURNING id INTO v_m2;

  INSERT INTO cycles (chat_id) VALUES (v_chatm) RETURNING id INTO v_cyclem;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cyclem, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
  RETURNING id INTO v_roundm;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_roundm, v_m1, 'M1 idea') RETURNING id INTO v_pm1;
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_roundm, v_m2, 'M2 idea') RETURNING id INTO v_pm2;

  PERFORM set_config('test.roundm', v_roundm::TEXT, TRUE);
  PERFORM set_config('test.m1', v_m1::TEXT, TRUE);
  PERFORM set_config('test.m2', v_m2::TEXT, TRUE);
  PERFORM set_config('test.pm1', v_pm1::TEXT, TRUE);
  PERFORM set_config('test.pm2', v_pm2::TEXT, TRUE);
END $$;

-- -----------------------------------------------------------------------------
-- T1: LRP, 3-prop round — strict exclusion still holds
-- -----------------------------------------------------------------------------
SELECT is(
  (SELECT COUNT(*)::INT FROM get_least_rated_propositions(
     current_setting('test.round3')::BIGINT,
     current_setting('test.y1')::BIGINT, 10, '{}')
   WHERE participant_id = current_setting('test.y1')::BIGINT),
  0,
  'T1: LRP excludes own prop when the round has 3 props'
);

-- -----------------------------------------------------------------------------
-- T2: LRP, 2-prop round — CSI includes the caller''s own prop
-- -----------------------------------------------------------------------------
SELECT is(
  (SELECT COUNT(*)::INT FROM get_least_rated_propositions(
     current_setting('test.round2')::BIGINT,
     current_setting('test.x1')::BIGINT, 10, '{}')),
  2,
  'T2: LRP returns both props (own included) in a 2-prop round'
);

-- -----------------------------------------------------------------------------
-- T3: get_propositions_for_rating, 2-prop round, as the authenticated user
-- -----------------------------------------------------------------------------
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c301"}', true);

SELECT is(
  (SELECT COUNT(*)::INT FROM get_propositions_for_rating(
     current_setting('test.round2')::BIGINT,
     current_setting('test.x1')::BIGINT)),
  2,
  'T3: get_propositions_for_rating returns both props (own included) at 2 props'
);

-- -----------------------------------------------------------------------------
-- T4: get_propositions_for_rating, 3-prop round with AI prop — AI kept, own out
-- -----------------------------------------------------------------------------
SELECT results_eq(
  $$SELECT id FROM get_propositions_for_rating(
      current_setting('test.round3')::BIGINT,
      current_setting('test.y1')::BIGINT)
    ORDER BY id$$,
  $$SELECT id FROM propositions
    WHERE round_id = current_setting('test.round3')::BIGINT
      AND (participant_id IS NULL
           OR participant_id != current_setting('test.y1')::BIGINT)
    ORDER BY id$$,
  'T4: 3-prop round returns AI + other human props, never the caller''s own'
);

RESET ROLE;

-- -----------------------------------------------------------------------------
-- T5: grid early advance — one rater finishing both props must NOT advance
-- (threshold = active_raters − 0 = 2 in a CSI round; the old −1 gave 1)
-- -----------------------------------------------------------------------------
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
VALUES
  (current_setting('test.round2')::BIGINT, current_setting('test.px1')::BIGINT,
   current_setting('test.x1')::BIGINT, 90),
  (current_setting('test.round2')::BIGINT, current_setting('test.px2')::BIGINT,
   current_setting('test.x1')::BIGINT, 60);

SELECT is(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.round2')::BIGINT),
  NULL,
  'T5: round does NOT complete after a single rater (threshold is 2, not 1)'
);

-- -----------------------------------------------------------------------------
-- T6: participation percent uses the CSI denominator (min 1 rating / 2 = 50)
-- -----------------------------------------------------------------------------
SELECT recompute_round_participation_percent(current_setting('test.round2')::BIGINT);

SELECT is(
  (SELECT participation_percent FROM rounds WHERE id = current_setting('test.round2')::BIGINT),
  50,
  'T6: participation percent is 50 after one of two raters (denominator 2)'
);

-- -----------------------------------------------------------------------------
-- T7: both raters done → early advance completes the round
-- -----------------------------------------------------------------------------
INSERT INTO grid_rankings (round_id, proposition_id, participant_id, grid_position)
VALUES
  (current_setting('test.round2')::BIGINT, current_setting('test.px1')::BIGINT,
   current_setting('test.x2')::BIGINT, 40),
  (current_setting('test.round2')::BIGINT, current_setting('test.px2')::BIGINT,
   current_setting('test.x2')::BIGINT, 85);

SELECT isnt(
  (SELECT winning_proposition_id FROM rounds WHERE id = current_setting('test.round2')::BIGINT),
  NULL,
  'T7: round completes once both raters rated both props'
);

-- -----------------------------------------------------------------------------
-- T8: matches finalize — first completion (with 1 real vote) does NOT finalize:
-- the other participant is an ABLE voter under CSI (2 props on the board)
-- -----------------------------------------------------------------------------
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
VALUES (current_setting('test.roundm')::BIGINT, current_setting('test.m1')::BIGINT,
        current_setting('test.pm2')::BIGINT, current_setting('test.pm1')::BIGINT);

INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.roundm')::BIGINT, current_setting('test.m1')::BIGINT);

SELECT is(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.roundm')::BIGINT),
  NULL,
  'T8: matches round does NOT finalize while an able voter is pending'
);

-- -----------------------------------------------------------------------------
-- T9: second completion finalizes
-- -----------------------------------------------------------------------------
INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
VALUES (current_setting('test.roundm')::BIGINT, current_setting('test.m2')::BIGINT,
        current_setting('test.pm2')::BIGINT, current_setting('test.pm1')::BIGINT);

INSERT INTO rating_completions (round_id, participant_id)
VALUES (current_setting('test.roundm')::BIGINT, current_setting('test.m2')::BIGINT);

SELECT isnt(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.roundm')::BIGINT),
  NULL,
  'T9: matches round finalizes once both voters completed'
);

-- -----------------------------------------------------------------------------
-- T10-T11: the prod self-destruct regression. A 2-prop / 2-author round that
-- transitions proposing → rating (firing trg_mark_stranded_raters) must NOT
-- auto-skip anyone: under CSI both authors are able voters. Pre-CSI, both got
-- skipped → active_raters 0 → complete_round_with_winner with zero votes.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_chat BIGINT; v_cycle BIGINT; v_round BIGINT;
  v_z1 BIGINT; v_z2 BIGINT;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token,
                     proposing_minimum, rating_minimum, start_mode)
  VALUES ('CSI Stranded Regression', 'Q?', gen_random_uuid(), 2, 2, 'auto')
  RETURNING id INTO v_chat;

  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-00000000c301'::uuid, 'Z1', 'active')
  RETURNING id INTO v_z1;
  INSERT INTO participants (chat_id, user_id, display_name, status)
  VALUES (v_chat, '00000000-0000-0000-0000-00000000c302'::uuid, 'Z2', 'active')
  RETURNING id INTO v_z2;

  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
  RETURNING id INTO v_round;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round, v_z1, 'Z1 idea');
  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round, v_z2, 'Z2 idea');

  -- The flip that fires trg_mark_stranded_raters.
  UPDATE rounds SET phase = 'rating' WHERE id = v_round;

  PERFORM set_config('test.roundz', v_round::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT COUNT(*)::INT FROM rating_skips
   WHERE round_id = current_setting('test.roundz')::BIGINT),
  0,
  'T10: no stranded auto-skips in a 2-prop/2-author round (CSI: both can vote)'
);

SELECT is(
  (SELECT completed_at FROM rounds WHERE id = current_setting('test.roundz')::BIGINT),
  NULL,
  'T11: the round survives entering rating (no zero-vote self-destruct)'
);

SELECT * FROM finish();
ROLLBACK;
