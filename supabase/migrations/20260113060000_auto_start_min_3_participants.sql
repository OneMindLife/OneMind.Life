-- Enforce minimum 3 participants for auto-start
-- Reasoning:
-- 1. Proposing minimum is 3 (need 3+ propositions to advance)
-- 2. Rating requires users to rank OTHER users' propositions (can't rank own)
-- 3. With 2 participants, each sees only 1 proposition (can't rank just 1)
-- 4. With 3 participants, each sees 2 propositions (minimum for grid ranking)
-- Therefore, auto-start must require at least 3 participants

-- Add constraint
ALTER TABLE chats
ADD CONSTRAINT chats_auto_start_participant_count_min_check
CHECK (auto_start_participant_count IS NULL OR auto_start_participant_count >= 3);

-- Update any existing values below 3
UPDATE chats
SET auto_start_participant_count = 3
WHERE auto_start_participant_count IS NOT NULL AND auto_start_participant_count < 3;

-- Add comment explaining the constraint
COMMENT ON COLUMN chats.auto_start_participant_count IS
'Minimum participants to auto-start first round. Must be >= 3 because: (1) proposing_minimum is 3, (2) rating requires 2+ propositions from OTHER users to rank.';
