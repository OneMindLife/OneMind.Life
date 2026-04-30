-- Test: chats.background_audio_url column + validator trigger + chat-audio bucket.
--
-- Backs per-chat background music. The column is nullable (most chats don't
-- have music), and a BEFORE trigger pins non-null values to the chat-audio
-- storage bucket so the host can't inject off-platform media URLs.
--
-- Covers:
--   * column exists, type text, nullable
--   * bucket 'chat-audio' exists and is public
--   * public-read policy on storage.objects for this bucket
--   * validator trigger accepts NULL (default case)
--   * validator trigger accepts any URL containing the canonical bucket path
--     (works for prod domain + local dev + custom CDN aliases)
--   * validator trigger rejects off-bucket URLs with a CHECK-class SQLSTATE
--   * validator trigger also fires on INSERT (not just UPDATE)
--   * chat RPCs include the column so Chat.fromJson hydrates it

BEGIN;
SET search_path TO public, extensions;
SELECT plan(12);

-- =============================================================================
-- Schema
-- =============================================================================
SELECT col_type_is(
  'public', 'chats', 'background_audio_url', 'text',
  'chats.background_audio_url is text'
);

SELECT col_is_null(
  'public', 'chats', 'background_audio_url',
  'chats.background_audio_url is nullable'
);

-- =============================================================================
-- Bucket + policy
-- =============================================================================
SELECT is(
  (SELECT public FROM storage.buckets WHERE id = 'chat-audio'),
  true,
  'chat-audio bucket exists and is public'
);

SELECT isnt_empty(
  $$SELECT 1 FROM pg_policies
    WHERE tablename = 'objects'
      AND policyname = 'Public read access for chat audio'$$,
  'Public read policy exists on storage.objects for chat-audio'
);

-- =============================================================================
-- Validator trigger — setup a chat we can mutate.
-- =============================================================================
INSERT INTO auth.users (id, email, role, aud, created_at, updated_at) VALUES
  ('00000000-0000-0000-0000-000000000b01', 'bg-audio@test.com', 'authenticated', 'authenticated', now(), now());

INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode,
                   proposing_threshold_count, proposing_threshold_percent,
                   rating_threshold_count, rating_threshold_percent)
VALUES ('BG Audio Test', 'Q', 'public', '00000000-0000-0000-0000-000000000b01', 'manual', NULL, NULL, NULL, NULL);

-- NULL stays NULL (default case, no trigger rejection).
SELECT is(
  (SELECT background_audio_url FROM chats WHERE name = 'BG Audio Test'),
  NULL::text,
  'New chat has null background_audio_url by default'
);

-- A valid bucket URL is accepted.
UPDATE chats
  SET background_audio_url = 'https://ccyuxrtrklgpkzcryzpj.supabase.co/storage/v1/object/public/chat-audio/999/song.mp3'
  WHERE name = 'BG Audio Test';
SELECT is(
  (SELECT background_audio_url FROM chats WHERE name = 'BG Audio Test'),
  'https://ccyuxrtrklgpkzcryzpj.supabase.co/storage/v1/object/public/chat-audio/999/song.mp3',
  'Valid chat-audio URL is accepted'
);

-- Local dev URL (different host) is also accepted — validator matches on path.
UPDATE chats
  SET background_audio_url = 'http://127.0.0.1:54321/storage/v1/object/public/chat-audio/999/song.mp3'
  WHERE name = 'BG Audio Test';
SELECT is(
  (SELECT background_audio_url FROM chats WHERE name = 'BG Audio Test'),
  'http://127.0.0.1:54321/storage/v1/object/public/chat-audio/999/song.mp3',
  'Local dev URL pointing at chat-audio bucket is accepted'
);

-- Setting back to NULL is allowed.
UPDATE chats SET background_audio_url = NULL WHERE name = 'BG Audio Test';
SELECT is(
  (SELECT background_audio_url FROM chats WHERE name = 'BG Audio Test'),
  NULL::text,
  'background_audio_url can be cleared back to NULL'
);

-- Off-platform URL rejected.
SELECT throws_ok(
  $$UPDATE chats SET background_audio_url = 'https://evil.example.com/trackme.mp3' WHERE name = 'BG Audio Test'$$,
  '23514',
  NULL,
  'Off-bucket URL is rejected by validator trigger (UPDATE)'
);

-- Different bucket (same Supabase Storage host) rejected.
SELECT throws_ok(
  $$UPDATE chats SET background_audio_url = 'https://ccyuxrtrklgpkzcryzpj.supabase.co/storage/v1/object/public/cycle-audio/999/song.mp3' WHERE name = 'BG Audio Test'$$,
  '23514',
  NULL,
  'Wrong-bucket URL is rejected by validator trigger'
);

-- Validator also fires on INSERT.
SELECT throws_ok(
  $$INSERT INTO chats (name, initial_message, access_method, creator_id, start_mode, background_audio_url)
    VALUES ('Bad URL Insert', 'Q', 'public', '00000000-0000-0000-0000-000000000b01', 'manual', 'https://evil.example.com/trackme.mp3')$$,
  '23514',
  NULL,
  'Off-bucket URL is rejected by validator trigger (INSERT)'
);

-- =============================================================================
-- RPCs return the new column — otherwise Chat.fromJson gets null even when
-- the DB row has a value, breaking playback after any dashboard refresh.
-- We check the function's declared return signature (pg_get_function_result)
-- rather than has_column, which only works for tables/views.
-- =============================================================================
SELECT matches(
  pg_get_function_result('public.get_chat_translated(bigint, text)'::regprocedure),
  'background_audio_url text',
  'get_chat_translated RETURNS TABLE includes background_audio_url text'
);

SELECT * FROM finish();
ROLLBACK;
