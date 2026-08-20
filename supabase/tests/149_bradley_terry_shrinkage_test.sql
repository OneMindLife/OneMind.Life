-- =============================================================================
-- Test: Bradley-Terry LOW-SAMPLE SHRINKAGE (20260718170000_bradley_terry_shrinkage)
-- =============================================================================
-- The bug this locks in: the MM fit had no regularization, so an opinion that
-- won its first few matchups got a ~95-99 score off 3-7 votes and leapfrogged
-- opinions vetted over 40+ matchups. Scores are now shrunk toward 50 by matchup
-- count (K=10), so a thinly-voted "perfect" opinion CANNOT out-rank a
-- battle-tested strong one until it earns the exposure.
--
-- Scenario (a realistic field, not a 3-node graph): LOW wins 2/2 (perfect, tiny
-- sample) vs HIGH wins ~30/36 (83% over a big sample), across 6 filler opinions.
-- Pre-shrinkage LOW's perfect record tops the list; with shrinkage HIGH must win.
-- (A tiny field is degenerate here: one never-played super-opponent drags the
-- whole average, which the 97-opinion prod field never does.)
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(3);

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode)
VALUES ('BT Shrinkage Test', 'Q', gen_random_uuid(), 'matches');

DO $$
DECLARE
  v_chat INT; v_cycle INT; v_round INT;
  v_low INT; v_high INT; v_f1 INT;
BEGIN
  SELECT id INTO v_chat FROM chats WHERE name = 'BT Shrinkage Test';
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle, 1, 'rating') RETURNING id INTO v_round;

  -- One proposer per opinion (unique-new-per-round index allows 1 each).
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'P', TRUE, 'active');
  -- LOW, HIGH, and 6 filler opinions F1..F6.
  INSERT INTO propositions (round_id, participant_id, content)
    SELECT v_round, (SELECT id FROM participants WHERE chat_id=v_chat LIMIT 1), c
    FROM (VALUES ('LOW'),('HIGH'),('F1'),('F2'),('F3'),('F4'),('F5'),('F6')) v(c);
  SELECT id INTO v_low  FROM propositions WHERE round_id=v_round AND content='LOW';
  SELECT id INTO v_high FROM propositions WHERE round_id=v_round AND content='HIGH';
  SELECT id INTO v_f1   FROM propositions WHERE round_id=v_round AND content='F1';

  -- 6 raters.
  INSERT INTO participants (chat_id, session_token, display_name, status)
    SELECT v_chat, gen_random_uuid(), 'R'||g, 'active' FROM generate_series(1,6) g;

  -- HIGH vs each of 6 fillers, 6 games each (m=36): raters 1-5 pick HIGH, rater 6
  -- picks the filler → HIGH wins 30/36 (~83%).
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    SELECT v_round, p.id,
      CASE WHEN substring(p.display_name from 2)::int <= 5 THEN v_high ELSE fil.id END,
      CASE WHEN substring(p.display_name from 2)::int <= 5 THEN fil.id ELSE v_high END
    FROM participants p
    CROSS JOIN (SELECT id FROM propositions WHERE round_id=v_round AND content LIKE 'F%') fil(id)
    WHERE p.chat_id=v_chat AND p.display_name LIKE 'R%';

  -- LOW vs F1, 2 games (m=2): raters 1-2 pick LOW → LOW wins 2/2 (100%).
  INSERT INTO pairwise_comparisons (round_id, participant_id, winner_proposition_id, loser_proposition_id)
    SELECT v_round, p.id, v_low, v_f1
    FROM participants p WHERE p.chat_id=v_chat AND p.display_name IN ('R1','R2');

  PERFORM score_bradley_terry(v_round);

  PERFORM set_config('t.round', v_round::text, false);
  PERFORM set_config('t.low',  v_low::text,  false);
  PERFORM set_config('t.high', v_high::text, false);
END $$;

-- 1) The core fix: the well-vetted HIGH out-ranks the thinly-voted "perfect" LOW.
SELECT ok(
  (SELECT global_score FROM proposition_global_scores
     WHERE round_id=current_setting('t.round')::int AND proposition_id=current_setting('t.high')::int)
  >
  (SELECT global_score FROM proposition_global_scores
     WHERE round_id=current_setting('t.round')::int AND proposition_id=current_setting('t.low')::int),
  'HIGH (30/36, ~83%) out-ranks LOW (2/2, 100%) after shrinkage'
);

-- 2) Shrinkage actually pulled the 2-vote perfect opinion toward the middle
--    (an unregularized fit would have put it ~95-100).
SELECT cmp_ok(
  (SELECT global_score FROM proposition_global_scores
     WHERE round_id=current_setting('t.round')::int AND proposition_id=current_setting('t.low')::int)::numeric,
  '<', 70::numeric,
  'LOW (only 2 matchups) is shrunk well below an unregularized ~95+'
);

-- 3) A strong, well-voted opinion still reads clearly above neutral (shrinkage
--    doesn't over-crush earned scores).
SELECT cmp_ok(
  (SELECT global_score FROM proposition_global_scores
     WHERE round_id=current_setting('t.round')::int AND proposition_id=current_setting('t.high')::int)::numeric,
  '>', 50::numeric,
  'HIGH stays clearly above neutral (50)'
);

SELECT * FROM finish();
ROLLBACK;
