-- Migration: Add round_participant_submissions table
-- One-time submission tracking for ratings per round per participant

CREATE TABLE IF NOT EXISTS round_participant_submissions (
  round_id integer NOT NULL,
  participant_id integer NOT NULL,
  submitted_at timestamptz DEFAULT now(),
  PRIMARY KEY (round_id, participant_id)
);

-- Index for looking up by participant
CREATE INDEX IF NOT EXISTS idx_round_participant_submissions_participant 
  ON round_participant_submissions(participant_id);

-- Enable RLS
ALTER TABLE round_participant_submissions ENABLE ROW LEVEL SECURITY;

-- Allow reading own submissions (for client apps)
CREATE POLICY "Users can read own submissions" 
  ON round_participant_submissions 
  FOR SELECT 
  USING (true);

-- No direct insert policy - only via Edge Function with service role
-- This ensures the one-time submission logic is enforced server-side

COMMENT ON TABLE round_participant_submissions IS 
  'Tracks which participants have submitted ratings for each round (one-time submission enforcement)';
