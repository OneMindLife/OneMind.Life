-- =============================================================================
-- TEST: Orphaned propositions (participant left) are still scored and ranked
-- =============================================================================

BEGIN;
SELECT plan(7);

DO $$
DECLARE
    v_user1 UUID := 'f8880000-aaaa-bbbb-cccc-000000000001';
    v_user2 UUID := 'f8880000-aaaa-bbbb-cccc-000000000002';
    v_user3 UUID := 'f8880000-aaaa-bbbb-cccc-000000000003';
    v_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_part1_id BIGINT;
    v_part2_id BIGINT;
    v_part3_id BIGINT;
    v_prop1_id BIGINT;
    v_prop2_id BIGINT;
    v_prop3_id BIGINT;
BEGIN
    -- Create auth users (trigger auto-creates public.users)
    INSERT INTO auth.users (id) VALUES (v_user1), (v_user2), (v_user3);

    -- Create chat
    INSERT INTO chats (name, access_method, proposing_duration_seconds, rating_duration_seconds,
      proposing_minimum, rating_minimum, start_mode, confirmation_rounds_required,
      rating_threshold_percent, proposing_threshold_percent)
    VALUES ('Orphan Test', 'public', 86400, 86400, 3, 2, 'auto', 2, 100, 100)
    RETURNING id INTO v_chat_id;

    -- Create participants
    INSERT INTO participants (chat_id, user_id, display_name, status)
    VALUES (v_chat_id, v_user1, 'Alice', 'active') RETURNING id INTO v_part1_id;
    INSERT INTO participants (chat_id, user_id, display_name, status)
    VALUES (v_chat_id, v_user2, 'Bob', 'active') RETURNING id INTO v_part2_id;
    INSERT INTO participants (chat_id, user_id, display_name, status)
    VALUES (v_chat_id, v_user3, 'Carol', 'active') RETURNING id INTO v_part3_id;

    -- Create cycle and round
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

    -- Three propositions
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_part1_id, 'Alice idea') RETURNING id INTO v_prop1_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_part2_id, 'Bob idea') RETURNING id INTO v_prop2_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_part3_id, 'Carol idea') RETURNING id INTO v_prop3_id;

    -- Simulate Bob leaving: delete participant, proposition becomes orphaned
    DELETE FROM participants WHERE id = v_part2_id;

    -- Add ratings: Alice rates Bob(80) > Carol(20), Carol rates Bob(90) > Alice(10)
    INSERT INTO grid_rankings (round_id, participant_id, proposition_id, grid_position) VALUES
      (v_round_id, v_part1_id, v_prop2_id, 80),
      (v_round_id, v_part1_id, v_prop3_id, 20),
      (v_round_id, v_part3_id, v_prop1_id, 10),
      (v_round_id, v_part3_id, v_prop2_id, 90);

    -- Run MOVDA
    PERFORM calculate_movda_scores_for_round(v_round_id);

    -- Store IDs in temp table for use in tests outside DO block
    CREATE TEMP TABLE test_ids ON COMMIT DROP AS
    SELECT v_round_id as round_id, v_prop1_id as prop1_id, v_prop2_id as prop2_id, v_prop3_id as prop3_id;
END $$;

-- Test 1: Bob's proposition still exists with NULL participant_id
SELECT is(
  (SELECT participant_id FROM propositions WHERE id = (SELECT prop2_id FROM test_ids)),
  NULL,
  'Orphaned proposition has NULL participant_id'
);

-- Test 2: MOVDA calculates score for orphaned proposition
SELECT isnt(
  (SELECT global_score FROM proposition_global_scores
   WHERE round_id = (SELECT round_id FROM test_ids)
   AND proposition_id = (SELECT prop2_id FROM test_ids)),
  NULL,
  'MOVDA calculates score for orphaned proposition'
);

-- Test 3: Orphaned proposition has highest score
SELECT is(
  (SELECT proposition_id FROM proposition_global_scores
   WHERE round_id = (SELECT round_id FROM test_ids)
   ORDER BY global_score DESC LIMIT 1),
  (SELECT prop2_id FROM test_ids),
  'Orphaned proposition can be top-ranked'
);

-- Test 4: get_propositions_with_scores returns orphaned proposition
SELECT isnt(
  (SELECT COUNT(*)::INTEGER FROM get_propositions_with_scores((SELECT round_id FROM test_ids))
   WHERE proposition_id = (SELECT prop2_id FROM test_ids)),
  0,
  'get_propositions_with_scores includes orphaned proposition'
);

-- Test 5: get_propositions_with_translations returns orphaned proposition
SELECT isnt(
  (SELECT COUNT(*)::INTEGER FROM get_propositions_with_translations((SELECT round_id FROM test_ids), 'en')
   WHERE id = (SELECT prop2_id FROM test_ids)),
  0,
  'get_propositions_with_translations includes orphaned proposition'
);

-- Test 6: calculate_proposing_ranks excludes orphaned proposition
SELECT is(
  (SELECT COUNT(*)::INTEGER FROM calculate_proposing_ranks((SELECT round_id FROM test_ids))
   WHERE participant_id IS NULL),
  0,
  'calculate_proposing_ranks skips orphaned propositions'
);

-- Test 7: complete_round_with_winner can select orphaned proposition as winner
DO $$ BEGIN PERFORM complete_round_with_winner((SELECT round_id FROM test_ids)); END $$;

SELECT is(
  (SELECT winning_proposition_id FROM rounds WHERE id = (SELECT round_id FROM test_ids)),
  (SELECT prop2_id FROM test_ids),
  'Orphaned proposition can win the round'
);

SELECT * FROM finish();
ROLLBACK;
