-- Increase proposing_minimum from 2 to 3
-- Reason: With "can't rate your own proposition" rule, users need to see at least 2
-- propositions to do grid ranking. With minimum 2 total, each user only sees 1.
-- Minimum 3 ensures each user sees at least 2 (their own excluded).

-- Drop existing constraint
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_proposing_minimum_check;

-- Add new constraint with minimum 3
ALTER TABLE chats ADD CONSTRAINT chats_proposing_minimum_check
    CHECK (proposing_minimum >= 3);

-- Update default value
ALTER TABLE chats ALTER COLUMN proposing_minimum SET DEFAULT 3;

-- Update existing chats that have proposing_minimum = 2
UPDATE chats SET proposing_minimum = 3 WHERE proposing_minimum < 3;

COMMENT ON COLUMN chats.proposing_minimum IS
'Minimum propositions required to advance to rating phase. Must be >= 3 because users cannot rate their own propositions, so each user needs to see at least 2 others.';
