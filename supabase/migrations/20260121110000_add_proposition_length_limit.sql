-- =============================================================================
-- MIGRATION: Add 200 character limit on proposition content
-- =============================================================================
-- Enforces a maximum length at the database level as the source of truth.
-- UI and AI also enforce this, but DB constraint is the ultimate safeguard.
-- =============================================================================

-- First, truncate any existing propositions that exceed the limit
UPDATE propositions
SET content = LEFT(content, 200)
WHERE char_length(content) > 200;

-- Now add the constraint
ALTER TABLE propositions
ADD CONSTRAINT propositions_content_length_check
CHECK (char_length(content) <= 200);

COMMENT ON CONSTRAINT propositions_content_length_check ON propositions IS
'Propositions must be 200 characters or less for readability and quick voting.';
