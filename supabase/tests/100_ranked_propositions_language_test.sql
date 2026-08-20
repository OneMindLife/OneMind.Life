-- Test: get_propositions_with_scores resolves translations without disturbing
-- the ranking.
--
-- Why this is guarded: the wedge ranks ONE global, multilingual opinion pool.
-- A voter who can't read a card can't judge it, so an unresolved translation
-- injects noise straight into the ranking that IS the product. Two things must
-- hold forever:
--   1. p_language_code NULL (the default) behaves exactly as it did before the
--      language param existed — this is what every Flutter caller relies on.
--   2. Translation is ADDITIVE: `content` is always the author's original, and
--      the resolution order is requested-language -> en -> original.
--
-- We don't exercise the pg_net HTTP call (out-of-process, same reasoning as
-- 96_proposition_translation_on_update_test). We insert translation rows
-- directly and assert the read path resolves them.

BEGIN;
SET search_path TO public, extensions;
SELECT plan(19);

-- =============================================================================
-- Signature
-- =============================================================================
SELECT has_function(
  'public', 'get_propositions_with_scores', ARRAY['bigint', 'text'],
  'ranked read path takes an optional language code'
);

SELECT hasnt_function(
  'public', 'get_propositions_with_scores', ARRAY['bigint'],
  'the 1-arg overload is GONE — coexisting with the defaulted 2-arg version '
  'would make get_propositions_with_scores(bigint) an ambiguous call'
);

SELECT has_function(
  'public', 'request_proposition_translation', ARRAY['bigint', 'text', 'text[]'],
  'shared translation-request helper exists'
);

SELECT has_function(
  'public', 'backfill_proposition_translations', ARRAY['bigint', 'text', 'integer'],
  'backfill entry point exists'
);

-- =============================================================================
-- Fixture: a round with two opinions, one non-English, plus a carried copy.
-- =============================================================================
INSERT INTO chats (name, initial_message, creator_session_token)
VALUES ('Ranked Lang Test', 'Q', gen_random_uuid());

DO $$
DECLARE
  v_chat_id INT;
  v_cycle_id INT;
  v_round_id INT;
  v_participant INT;
  v_prop_foreign INT;
  v_prop_english INT;
BEGIN
  SELECT id INTO v_chat_id FROM chats WHERE name = 'Ranked Lang Test';

  INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
  -- 'rating' so early-advance triggers don't complete the round mid-seed.
  INSERT INTO rounds (cycle_id, custom_id, phase)
  VALUES (v_cycle_id, 1, 'rating') RETURNING id INTO v_round_id;

  INSERT INTO participants (chat_id, session_token, display_name, is_host)
  VALUES (v_chat_id, gen_random_uuid(), 'Voter', true)
  RETURNING id INTO v_participant;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant, 'أمر مهم')
  RETURNING id INTO v_prop_foreign;

  INSERT INTO propositions (round_id, participant_id, content)
  VALUES (v_round_id, v_participant, 'An English opinion')
  RETURNING id INTO v_prop_english;

  -- Only the foreign one has translations. The English one deliberately has
  -- none, so we can assert the 'original' fallback.
  INSERT INTO translations (proposition_id, entity_type, field_name, language_code, translated_text)
  VALUES
    (v_prop_foreign, 'proposition', 'content', 'en', 'An important matter'),
    (v_prop_foreign, 'proposition', 'content', 'es', 'Un asunto importante');

  -- Rank the foreign opinion first, so a translation bug that reorders rows
  -- shows up as a rank assertion failure rather than passing silently.
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score)
  VALUES (v_prop_foreign, v_round_id, 0.9), (v_prop_english, v_round_id, 0.1);

  PERFORM set_config('test.round_id', v_round_id::text, false);
  PERFORM set_config('test.prop_foreign', v_prop_foreign::text, false);
  PERFORM set_config('test.prop_english', v_prop_english::text, false);
END $$;

-- =============================================================================
-- 1. NULL language = pre-existing behaviour, byte for byte
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint)
   WHERE proposition_id = current_setting('test.prop_foreign')::bigint),
  'أمر مهم',
  'NULL language: content_translated falls back to the original'
);

SELECT is(
  (SELECT language_code FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint)
   WHERE proposition_id = current_setting('test.prop_foreign')::bigint),
  'original',
  'NULL language: reports "original" — no translation was applied'
);

-- =============================================================================
-- 2. The original is NEVER overwritten
-- =============================================================================
SELECT is(
  (SELECT content FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'en')
   WHERE proposition_id = current_setting('test.prop_foreign')::bigint),
  'أمر مهم',
  'content always returns what the author actually wrote'
);

-- =============================================================================
-- 3. Requested language resolves
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'en')
   WHERE proposition_id = current_setting('test.prop_foreign')::bigint),
  'An important matter',
  'en requested: the English translation is what a reader sees'
);

SELECT is(
  (SELECT content_translated FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'es')
   WHERE proposition_id = current_setting('test.prop_foreign')::bigint),
  'Un asunto importante',
  'es requested: the Spanish translation wins over the English one'
);

-- =============================================================================
-- 4. Fallback rungs
-- =============================================================================
SELECT is(
  (SELECT content_translated FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'fr')
   WHERE proposition_id = current_setting('test.prop_foreign')::bigint),
  'An important matter',
  'fr requested but absent: falls back to English, not to unreadable source'
);

SELECT is(
  (SELECT language_code FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'fr')
   WHERE proposition_id = current_setting('test.prop_foreign')::bigint),
  'en',
  'fr requested but absent: honestly reports that English is what was served'
);

SELECT is(
  (SELECT content_translated FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'en')
   WHERE proposition_id = current_setting('test.prop_english')::bigint),
  'An English opinion',
  'no translation rows at all: falls back to the original'
);

-- =============================================================================
-- 5. Ranking is untouched by the translation joins
-- =============================================================================
-- The translations LEFT JOINs must not fan out rows or perturb ORDER BY. If a
-- future edit joins on a non-unique key, this is what catches it.
SELECT is(
  (SELECT count(*) FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'en')),
  2::bigint,
  'translation joins do not duplicate rows'
);

SELECT is(
  (SELECT proposition_id FROM public.get_propositions_with_scores(
     current_setting('test.round_id')::bigint, 'en')
   WHERE rank = 1),
  current_setting('test.prop_foreign')::bigint,
  'ranking still follows global_score, unaffected by language'
);

-- =============================================================================
-- 6. Scalar resolver — the shared fallback ladder used by the node bootstrap
-- =============================================================================
-- get_node_bootstrap resolves each of its three content fields (parent, reply,
-- winner) through this, so the node/duel path shows the same English the ranked
-- list does. Test it directly — the bootstrap's own participant gate makes it
-- awkward to drive in pgtap, and this is where the actual logic lives.
SELECT has_function(
  'public', 'proposition_content_translated', ARRAY['bigint', 'text', 'text'],
  'scalar resolver exists'
);

SELECT is(
  public.proposition_content_translated(
    current_setting('test.prop_foreign')::bigint, 'أمر مهم', NULL),
  'أمر مهم',
  'resolver: NULL language returns the original untouched'
);

SELECT is(
  public.proposition_content_translated(
    current_setting('test.prop_foreign')::bigint, 'أمر مهم', 'en'),
  'An important matter',
  'resolver: en returns the English translation'
);

SELECT is(
  public.proposition_content_translated(
    current_setting('test.prop_foreign')::bigint, 'أمر مهم', 'fr'),
  'An important matter',
  'resolver: absent language falls back to English'
);

SELECT is(
  public.proposition_content_translated(
    current_setting('test.prop_english')::bigint, 'An English opinion', 'en'),
  'An English opinion',
  'resolver: no translation rows falls back to the original'
);

SELECT * FROM finish();
ROLLBACK;
