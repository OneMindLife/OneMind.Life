-- Enforce minimum constraints for proposing and rating
-- proposing_minimum >= 2: Need at least 2 propositions to compare
-- rating_minimum >= 2: Need at least 2 raters for meaningful alignment

-- First, update any existing rows that violate the new constraints
UPDATE chats SET proposing_minimum = 2 WHERE proposing_minimum < 2;
UPDATE chats SET rating_minimum = 2 WHERE rating_minimum < 2;

-- Drop existing constraints if they exist (they check >= 1)
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_proposing_minimum_check;
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_rating_minimum_check;

-- Add new constraints enforcing >= 2
ALTER TABLE chats ADD CONSTRAINT chats_proposing_minimum_check
    CHECK (proposing_minimum >= 2);

ALTER TABLE chats ADD CONSTRAINT chats_rating_minimum_check
    CHECK (rating_minimum >= 2);

-- Update default values to be explicit
ALTER TABLE chats ALTER COLUMN proposing_minimum SET DEFAULT 2;
ALTER TABLE chats ALTER COLUMN rating_minimum SET DEFAULT 2;

COMMENT ON COLUMN chats.proposing_minimum IS 'Minimum number of propositions required before advancing to rating. Must be >= 2 for meaningful comparison.';
COMMENT ON COLUMN chats.rating_minimum IS 'Minimum average raters per proposition required. Must be >= 2 for meaningful alignment (requires 3+ participants).';
