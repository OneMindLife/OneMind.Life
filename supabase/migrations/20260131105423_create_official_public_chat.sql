-- Create the official OneMind public chat
-- This chat is always open and all new users are auto-joined after tutorial

-- Insert the official chat (idempotent - only if no official chat exists)
INSERT INTO public.chats (
  name,
  initial_message,
  invite_code,
  access_method,
  require_auth,
  require_approval,
  is_active,
  is_official,
  start_mode,
  rating_start_mode,
  auto_start_participant_count,
  proposing_duration_seconds,
  rating_duration_seconds,
  proposing_minimum,
  rating_minimum,
  proposing_threshold_percent,
  proposing_threshold_count,
  rating_threshold_percent,
  rating_threshold_count,
  confirmation_rounds_required,
  show_previous_results,
  propositions_per_user,
  enable_ai_participant,
  adaptive_duration_enabled
)
SELECT
  'Welcome to OneMind',
  'What should we talk about?',
  'ONMIND',        -- invite_code: 6 char max
  'public',
  false,           -- require_auth: false (anonymous auth is fine)
  false,           -- require_approval: false (public = auto-join)
  true,            -- is_active
  true,            -- is_official
  'auto',          -- start_mode: auto-start when threshold reached
  'auto',          -- rating_start_mode: auto-advance to rating
  3,               -- auto_start_participant_count: minimum 3 for meaningful ranking
  1800,            -- proposing_duration_seconds: 30 minutes
  1800,            -- rating_duration_seconds: 30 minutes
  3,               -- proposing_minimum: must be >= 3 per constraint
  2,               -- rating_minimum
  NULL,            -- proposing_threshold_percent: use count instead (avoids ghost user problem)
  10,              -- proposing_threshold_count: early advance when 10 propositions
  NULL,            -- rating_threshold_percent: use count instead (avoids ghost user problem)
  10,              -- rating_threshold_count: early advance when 10 ratings
  2,               -- confirmation_rounds_required
  true,            -- show_previous_results
  1,               -- propositions_per_user
  false,           -- enable_ai_participant
  false            -- adaptive_duration_enabled
WHERE NOT EXISTS (
  SELECT 1 FROM public.chats WHERE is_official = true
);

-- Add a comment explaining this chat's purpose
COMMENT ON INDEX idx_chats_single_official IS 'Ensures only one official OneMind chat exists. This chat is used to onboard new users after they complete the tutorial.';
