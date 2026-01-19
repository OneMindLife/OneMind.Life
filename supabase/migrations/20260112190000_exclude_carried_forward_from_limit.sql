-- Migration: Exclude carried forward propositions from the per-round limit
-- Carried forward propositions shouldn't count against the user's submission limit
-- because they were automatically copied from the previous round

CREATE OR REPLACE FUNCTION count_participant_propositions_in_round(
    p_participant_id BIGINT,
    p_round_id BIGINT
) RETURNS INTEGER
LANGUAGE plpgsql STABLE SECURITY INVOKER AS $$
DECLARE
    prop_count INTEGER;
BEGIN
    SELECT COUNT(*)::INTEGER INTO prop_count
    FROM propositions
    WHERE participant_id = p_participant_id
      AND round_id = p_round_id
      AND carried_from_id IS NULL;  -- Exclude carried forward propositions

    RETURN COALESCE(prop_count, 0);
END;
$$;

COMMENT ON FUNCTION count_participant_propositions_in_round(BIGINT, BIGINT) IS
  'Count propositions submitted by a participant in a round, excluding carried forward propositions';
