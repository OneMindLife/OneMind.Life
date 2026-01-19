-- Cap phase duration at 1 day (86400 seconds)
-- Longer durations are not supported

-- Add max constraint for proposing_duration_seconds
ALTER TABLE chats
DROP CONSTRAINT IF EXISTS "chats_proposing_duration_max_check";

ALTER TABLE chats
ADD CONSTRAINT "chats_proposing_duration_max_check"
CHECK (proposing_duration_seconds <= 86400);

-- Add max constraint for rating_duration_seconds
ALTER TABLE chats
DROP CONSTRAINT IF EXISTS "chats_rating_duration_max_check";

ALTER TABLE chats
ADD CONSTRAINT "chats_rating_duration_max_check"
CHECK (rating_duration_seconds <= 86400);

-- Update any existing chats that exceed 1 day (shouldn't be any)
UPDATE chats
SET proposing_duration_seconds = 86400
WHERE proposing_duration_seconds > 86400;

UPDATE chats
SET rating_duration_seconds = 86400
WHERE rating_duration_seconds > 86400;

COMMENT ON CONSTRAINT "chats_proposing_duration_max_check" ON chats IS
'Maximum proposing phase duration is 1 day (86400 seconds)';

COMMENT ON CONSTRAINT "chats_rating_duration_max_check" ON chats IS
'Maximum rating phase duration is 1 day (86400 seconds)';
