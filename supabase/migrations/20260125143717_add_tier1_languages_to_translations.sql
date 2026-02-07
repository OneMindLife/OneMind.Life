-- =============================================================================
-- MIGRATION: Add Tier 1 languages to translations table
-- =============================================================================
-- Adds Portuguese (pt), French (fr), and German (de) to the allowed language codes.
-- These are Tier 1 languages for internationalization support.
-- =============================================================================

-- Drop the old constraint
ALTER TABLE translations DROP CONSTRAINT IF EXISTS translations_language_code_check;

-- Add new constraint with all 5 supported languages
ALTER TABLE translations ADD CONSTRAINT translations_language_code_check
  CHECK (language_code = ANY (ARRAY['en', 'es', 'pt', 'fr', 'de']));

-- Add comment documenting the supported languages
COMMENT ON CONSTRAINT translations_language_code_check ON translations IS
  'Allowed language codes: en (English), es (Spanish), pt (Portuguese), fr (French), de (German)';
