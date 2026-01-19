-- Increase threshold_count minimums to match minimum-to-advance settings
-- proposing_threshold_count >= 3 (same as proposing_minimum)
-- rating_threshold_count >= 2 (same as rating_minimum)

-- Update existing chats with values below the new minimums
UPDATE chats SET proposing_threshold_count = 3 WHERE proposing_threshold_count IS NOT NULL AND proposing_threshold_count < 3;
UPDATE chats SET rating_threshold_count = 2 WHERE rating_threshold_count IS NOT NULL AND rating_threshold_count < 2;

-- Drop old constraints
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_proposing_threshold_count_check;
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_rating_threshold_count_check;

-- Add new constraints
ALTER TABLE chats ADD CONSTRAINT chats_proposing_threshold_count_check
    CHECK (proposing_threshold_count IS NULL OR proposing_threshold_count >= 3);

ALTER TABLE chats ADD CONSTRAINT chats_rating_threshold_count_check
    CHECK (rating_threshold_count IS NULL OR rating_threshold_count >= 2);

-- Update defaults
ALTER TABLE chats ALTER COLUMN proposing_threshold_count SET DEFAULT 5;
ALTER TABLE chats ALTER COLUMN rating_threshold_count SET DEFAULT 5;

COMMENT ON COLUMN chats.proposing_threshold_count IS 'Minimum participants who must submit for early advance. Must be >= 3 (same as proposing_minimum).';
COMMENT ON COLUMN chats.rating_threshold_count IS 'Minimum participants who must rate for early advance. Must be >= 2 (same as rating_minimum).';
