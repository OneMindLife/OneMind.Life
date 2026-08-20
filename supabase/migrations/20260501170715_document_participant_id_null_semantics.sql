-- Document why propositions.participant_id is nullable. The NULL
-- state is rare and load-bearing rather than incidental:
--
-- 1. ON DELETE SET NULL on the FK to participants(id). When a
--    participant row is hard-deleted (GDPR right-to-be-forgotten,
--    admin cleanup, schema repair), their propositions stay — content
--    + ratings + round outcomes preserved — but author attribution is
--    dropped. Anonymity is the design property already, so losing the
--    author has no user-visible effect. See migration 20260430120000
--    for the soft-delete model that made this path rare.
--
-- 2. Pre-April-30 leaveChat used hard-delete, leaving a small number
--    of orphaned NULL-author propositions in production. As of
--    2026-05-01 there are 3 such rows (0.52% of 582 total).
--
-- Normal leave flow does NOT produce NULLs — participants soft-delete
-- (status='left') and the row stays. The unique constraint
-- idx_propositions_unique_new_per_round is partial WHERE
-- participant_id IS NOT NULL, so NULL-author propositions are
-- explicitly carved out and don't conflict with the per-round-per-
-- participant uniqueness rule.

COMMENT ON COLUMN propositions.participant_id IS
'Author of the proposition. Nullable because: (a) FK ON DELETE SET '
'NULL preserves propositions when a participant row is hard-deleted '
'(GDPR, admin cleanup) without corrupting other participants'' '
'rating history; (b) pre-April-30 hard-delete leaveChat left a few '
'orphaned rows. Normal soft-delete leave (post 20260430120000) '
'preserves participant_id. Unique index idx_propositions_unique_new_'
'per_round excludes NULL via partial predicate. See migration '
'20260501170715.';
