-- Limit confirmation_rounds_required to 1-2
-- Reasoning: More than 2 consecutive wins is impractical and frustrating for users

-- Drop existing constraint
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_confirmation_rounds_required_check;

-- Add new constraint with both min and max
ALTER TABLE chats ADD CONSTRAINT chats_confirmation_rounds_required_check
CHECK (confirmation_rounds_required >= 1 AND confirmation_rounds_required <= 2);

-- Update any existing values above 2 to 2
UPDATE chats SET confirmation_rounds_required = 2 WHERE confirmation_rounds_required > 2;

COMMENT ON COLUMN chats.confirmation_rounds_required IS
'Number of consecutive round wins required for consensus. Must be 1-2.';
