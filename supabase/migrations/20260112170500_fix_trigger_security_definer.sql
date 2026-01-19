-- Migration: Fix on_round_winner_set trigger to use SECURITY DEFINER
-- The trigger needs elevated privileges to insert carried forward propositions
-- because RLS policies on propositions table block inserts from regular users

ALTER FUNCTION on_round_winner_set() SECURITY DEFINER;

COMMENT ON FUNCTION on_round_winner_set() IS
  'Handles round completion: tracks consensus, creates next round, and carries forward winners. '
  'Uses SECURITY DEFINER to bypass RLS when inserting carried forward propositions.';
