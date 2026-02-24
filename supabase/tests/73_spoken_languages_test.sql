-- Test: spoken_languages column, updated language constraint, and RPCs
-- Migration: 20260227100000_spoken_languages.sql

BEGIN;
SET search_path TO public, extensions;
SELECT plan(14);

-- =============================================================================
-- Setup: Create test user
-- =============================================================================
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000f01', 'spoken-lang-test@test.com', 'authenticated', 'authenticated', now(), now());

-- Ensure user row exists (auth trigger should create it)
INSERT INTO public.users (id, language_code)
VALUES ('00000000-0000-0000-0000-000000000f01', 'en')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- Test 1: spoken_languages column exists
-- =============================================================================
SELECT has_column('public', 'users', 'spoken_languages',
  'users table has spoken_languages column');

-- =============================================================================
-- Test 2: spoken_languages column has correct type (TEXT[])
-- =============================================================================
SELECT col_type_is('public', 'users', 'spoken_languages', 'text[]',
  'spoken_languages is TEXT[]');

-- =============================================================================
-- Test 3: spoken_languages defaults to {en}
-- =============================================================================
SELECT is(
  (SELECT spoken_languages FROM public.users WHERE id = '00000000-0000-0000-0000-000000000f01'),
  ARRAY['en']::TEXT[],
  'spoken_languages defaults to {en}'
);

-- =============================================================================
-- Test 4: language_code constraint accepts "en"
-- =============================================================================
SELECT lives_ok(
  $$UPDATE public.users SET language_code = 'en' WHERE id = '00000000-0000-0000-0000-000000000f01'$$,
  'language_code constraint accepts en'
);

-- =============================================================================
-- Test 5: language_code constraint accepts "es"
-- =============================================================================
SELECT lives_ok(
  $$UPDATE public.users SET language_code = 'es' WHERE id = '00000000-0000-0000-0000-000000000f01'$$,
  'language_code constraint accepts es'
);

-- =============================================================================
-- Test 6: language_code constraint accepts "pt"
-- =============================================================================
SELECT lives_ok(
  $$UPDATE public.users SET language_code = 'pt' WHERE id = '00000000-0000-0000-0000-000000000f01'$$,
  'language_code constraint accepts pt'
);

-- =============================================================================
-- Test 7: language_code constraint accepts "fr"
-- =============================================================================
SELECT lives_ok(
  $$UPDATE public.users SET language_code = 'fr' WHERE id = '00000000-0000-0000-0000-000000000f01'$$,
  'language_code constraint accepts fr'
);

-- =============================================================================
-- Test 8: language_code constraint accepts "de"
-- =============================================================================
SELECT lives_ok(
  $$UPDATE public.users SET language_code = 'de' WHERE id = '00000000-0000-0000-0000-000000000f01'$$,
  'language_code constraint accepts de'
);

-- =============================================================================
-- Test 9: language_code constraint rejects unsupported code
-- =============================================================================
SELECT throws_ok(
  $$UPDATE public.users SET language_code = 'zh' WHERE id = '00000000-0000-0000-0000-000000000f01'$$,
  '23514',  -- check_violation
  NULL,
  'language_code constraint rejects unsupported code zh'
);

-- =============================================================================
-- Test 10: update_user_language_code RPC exists
-- =============================================================================
SELECT has_function('public', 'update_user_language_code', ARRAY['text'],
  'update_user_language_code(text) function exists');

-- =============================================================================
-- Test 11: update_user_language_code RPC validates input
-- =============================================================================
-- Set auth context to our test user
SET LOCAL role TO 'authenticated';
SET LOCAL request.jwt.claim.sub TO '00000000-0000-0000-0000-000000000f01';

SELECT throws_ok(
  $$SELECT update_user_language_code('zh')$$,
  'P0001',  -- raise_exception
  'Unsupported language code: zh',
  'update_user_language_code rejects unsupported language'
);

-- =============================================================================
-- Test 12: update_user_language_code RPC updates language
-- =============================================================================
SELECT lives_ok(
  $$SELECT update_user_language_code('pt')$$,
  'update_user_language_code accepts pt'
);

-- =============================================================================
-- Test 13: update_user_spoken_languages RPC exists
-- =============================================================================
SELECT has_function('public', 'update_user_spoken_languages', ARRAY['text[]'],
  'update_user_spoken_languages(text[]) function exists');

-- =============================================================================
-- Test 14: update_user_spoken_languages RPC stores array
-- =============================================================================
SELECT lives_ok(
  $$SELECT update_user_spoken_languages(ARRAY['en', 'es', 'fr']::TEXT[])$$,
  'update_user_spoken_languages stores array of 3 languages'
);

-- Reset
RESET role;

SELECT * FROM finish();
ROLLBACK;
