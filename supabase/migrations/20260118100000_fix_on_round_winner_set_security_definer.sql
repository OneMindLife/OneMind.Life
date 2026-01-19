-- Migration: Restore SECURITY DEFINER on on_round_winner_set trigger function
--
-- The optimization migration (20260117100000_optimize_cycle_winner_auto_start.sql)
-- recreated on_round_winner_set() without SECURITY DEFINER, which was previously
-- added in 20260112170500_fix_trigger_security_definer.sql.
--
-- Without SECURITY DEFINER, the trigger fails when inserting carried forward
-- propositions because RLS policies on the propositions table prevent inserts
-- with a different participant_id than the current user.

ALTER FUNCTION on_round_winner_set() SECURITY DEFINER;

COMMENT ON FUNCTION on_round_winner_set() IS
  'Handles round completion: tracks consensus, creates next round using shared helper, and carries forward winners. '
  'Uses SECURITY DEFINER to bypass RLS when inserting carried forward propositions.';
