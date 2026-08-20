-- Allow MULTIPLE new propositions per participant per round (the composer
-- no longer disappears after one take — propositions_per_user gates the
-- count per chat), while KEEPING the double-submit/retry TOCTOU protection
-- the old index existed for (a retry carries identical content, so a
-- content-hash column in the key still blocks it).
DROP INDEX IF EXISTS idx_propositions_unique_new_per_round;
CREATE UNIQUE INDEX idx_propositions_unique_new_per_round
ON propositions (round_id, participant_id, md5(content))
WHERE carried_from_id IS NULL AND participant_id IS NOT NULL;
