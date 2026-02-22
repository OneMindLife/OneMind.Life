-- Prevent duplicate new propositions from same participant in same round
-- (needed for retry mechanism TOCTOU safety)
CREATE UNIQUE INDEX IF NOT EXISTS idx_propositions_unique_new_per_round
ON propositions (round_id, participant_id)
WHERE carried_from_id IS NULL AND participant_id IS NOT NULL;
