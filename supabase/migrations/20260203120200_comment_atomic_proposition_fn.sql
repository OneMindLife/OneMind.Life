-- Migration: Add documentation comment to submit_proposition_atomic function

COMMENT ON FUNCTION submit_proposition_atomic IS 'Atomically check for duplicates and insert a proposition using advisory locking. Prevents race conditions where concurrent requests could both pass the duplicate check. Returns status="success" with proposition_id, or status="duplicate" with duplicate_id.';
