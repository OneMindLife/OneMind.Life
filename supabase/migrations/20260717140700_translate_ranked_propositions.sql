-- Make the global opinion pool readable: translate opinions, and surface the
-- translation on the ranked read path.
--
-- WHY THIS IS CORRECTNESS, NOT POLISH
-- The wedge ranks every opinion in ONE global pool, and that pool is
-- multilingual — a live duel paired an Arabic opinion against an English one.
-- A voter who cannot read a card cannot judge it, so their vote is noise
-- injected into the very ranking that IS the product. Readable text is a
-- precondition for a meaningful vote.
--
-- THREE GAPS CLOSED HERE
--   1. request_proposition_translation() — the vault + pg_net call, extracted
--      from the INSERT trigger so the trigger and the backfill share ONE path.
--   2. get_propositions_with_scores() — the ranked read path gains an optional
--      language, so translations can actually reach a reader.
--   3. backfill_proposition_translations() — the trigger only ever fired on
--      INSERT, so every opinion posted before today has no translation.
--
-- Originals are never overwritten. propositions.content stays exactly what the
-- author typed; translations live in the `translations` table alongside it.

-- ---------------------------------------------------------------------------
-- 1. Shared translation request
-- ---------------------------------------------------------------------------
-- Extracted verbatim from trigger_translate_proposition() so there is exactly
-- one place that knows how to reach the translate edge function. The trigger
-- (new opinions) and the backfill (old opinions) are now two callers of one
-- helper rather than two copies of the same vault/pg_net dance.
--
-- Returns the pg_net request id, or NULL when the call was deliberately
-- skipped (no vault key). Never raises: a translation is an enhancement, and
-- failing to get one must never fail the INSERT that triggered it.
CREATE OR REPLACE FUNCTION public.request_proposition_translation(
  p_proposition_id bigint,
  p_text text,
  p_languages text[]
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_service_key text;
  v_request_id bigint;
BEGIN
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'Translation skipped: edge_function_service_key not configured in vault';
    RETURN NULL;
  END IF;

  -- Vault-based URL (not hardcoded) so local dev hits the local stack. See the
  -- cron setup note in CLAUDE.md — same helper the cron jobs use.
  SELECT net.http_post(
    url := public.get_edge_function_url('translate'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      'proposition_id', p_proposition_id,
      'text', p_text,
      'entity_type', 'proposition',
      'field_name', 'content',
      'languages', to_jsonb(p_languages)
    ),
    timeout_milliseconds := 60000
  ) INTO v_request_id;

  RETURN v_request_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_proposition_translation(bigint, text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_proposition_translation(bigint, text, text[]) TO service_role;

COMMENT ON FUNCTION public.request_proposition_translation(bigint, text, text[]) IS
  'Fire-and-forget request to the translate edge function for one proposition. Shared by the INSERT trigger and the backfill. Returns the pg_net request id, or NULL if skipped.';

-- The trigger is now a thin policy layer: decide WHETHER to translate (chat
-- settings, carried-forward skip) and delegate HOW to the helper above.
CREATE OR REPLACE FUNCTION public.trigger_translate_proposition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_request_id bigint;
  v_translations_enabled boolean;
  v_translation_languages text[];
BEGIN
  -- Carried-forward copies are the same text as their root, which already has
  -- translations; the read path resolves them via COALESCE(carried_from_id, id).
  IF NEW.carried_from_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.translations_enabled, c.translation_languages
  INTO v_translations_enabled, v_translation_languages
  FROM rounds r
  INNER JOIN cycles cy ON cy.id = r.cycle_id
  INNER JOIN chats c ON c.id = cy.chat_id
  WHERE r.id = NEW.round_id;

  IF NOT COALESCE(v_translations_enabled, false) THEN
    RETURN NEW;
  END IF;

  v_request_id := public.request_proposition_translation(
    NEW.id, NEW.content, v_translation_languages
  );

  RAISE LOG 'Translation requested for proposition % (request_id: %, languages: %)',
    NEW.id, v_request_id, v_translation_languages;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- A missing translation must never cost us the opinion itself.
  RAISE WARNING 'Translation trigger error for proposition %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Language-aware ranked read path
-- ---------------------------------------------------------------------------
-- SHAPE: `content` still returns the ORIGINAL, always — we never lie about what
-- someone wrote. Translation is additive: `content_translated` resolves
-- requested-language -> English -> original, and `language_code` reports which
-- of those actually landed ('original' = no translation row exists). That is the
-- exact contract get_propositions_with_translations() already exposes, so both
-- read paths speak one language and the wedge's propContent() helper works
-- unchanged.
--
-- COMPAT: p_language_code defaults to NULL, meaning "don't translate", which
-- reproduces the previous behaviour exactly (content_translated = content).
--
-- WHY DROP INSTEAD OF ADDING AN OVERLOAD: a defaulted 2-arg function sitting
-- next to the 1-arg one makes get_propositions_with_scores(bigint) an AMBIGUOUS
-- call that errors at runtime. Existing 1-arg callers bind to the default here.
--
-- WHY NOT A SECOND RPC: ranking is the product. Forking a translated copy of it
-- guarantees the two drift, and the ranked list is exactly where that drift
-- would be invisible and expensive.
DROP FUNCTION IF EXISTS public.get_propositions_with_scores(bigint);

CREATE FUNCTION public.get_propositions_with_scores(
  p_round_id bigint,
  p_language_code text DEFAULT NULL
)
RETURNS TABLE(
  proposition_id bigint,
  content text,
  content_translated text,
  language_code text,
  participant_id bigint,
  global_score real,
  movda_rating real,
  rank integer,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.can_read_round_results(p_round_id) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    p.id AS proposition_id,
    p.content,
    COALESCE(t.translated_text, ten.translated_text, p.content) AS content_translated,
    COALESCE(
      t.language_code,
      CASE WHEN ten.translated_text IS NOT NULL THEN 'en' END,
      'original'
    ) AS language_code,
    p.participant_id,
    COALESCE(pgs.global_score, 0.0) AS global_score,
    COALESCE(pmr.rating, 1500.0) AS movda_rating,
    ROW_NUMBER() OVER (ORDER BY COALESCE(pgs.global_score, 0.0) DESC)::integer AS rank,
    p.created_at
  FROM propositions p
  LEFT JOIN proposition_global_scores pgs
    ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
  LEFT JOIN proposition_movda_ratings pmr
    ON pmr.proposition_id = p.id AND pmr.round_id = p_round_id
  -- Carried-forward copies inherit their root's translation; the trigger skips
  -- them for exactly that reason.
  LEFT JOIN translations t
    ON p_language_code IS NOT NULL
   AND t.proposition_id = COALESCE(p.carried_from_id, p.id)
   AND t.field_name = 'content'
   AND t.language_code = p_language_code
  -- English is the fallback rung: better a language most readers share than a
  -- script they cannot read at all.
  LEFT JOIN translations ten
    ON p_language_code IS NOT NULL AND p_language_code <> 'en'
   AND ten.proposition_id = COALESCE(p.carried_from_id, p.id)
   AND ten.field_name = 'content'
   AND ten.language_code = 'en'
  WHERE p.round_id = p_round_id
  ORDER BY COALESCE(pgs.global_score, 0.0) DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_propositions_with_scores(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_propositions_with_scores(bigint, text)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_propositions_with_scores(bigint, text) IS
  'Vote-ranked propositions for a round. p_language_code NULL (default) = originals only; set it to resolve content_translated via requested-language -> en -> original.';

-- ---------------------------------------------------------------------------
-- 3. Backfill
-- ---------------------------------------------------------------------------
-- The trigger only ever fired on INSERT, so opinions posted before translation
-- was switched on for a chat have no translation row. This walks those, oldest
-- first, and enqueues each through the same helper the trigger uses.
--
-- Idempotent (skips anything already translated into p_language_code) and
-- batched (p_limit) because pg_net queues in-process and the edge function
-- fans out to Google per language. Safe to re-run until it returns 0.
CREATE OR REPLACE FUNCTION public.backfill_proposition_translations(
  p_chat_id bigint,
  p_language_code text DEFAULT 'en',
  p_limit integer DEFAULT 50
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_prop record;
  v_count integer := 0;
BEGIN
  FOR v_prop IN
    SELECT p.id, p.content
    FROM propositions p
    WHERE p.chat_id = p_chat_id
      -- Carried-forward copies resolve through their root, so translating them
      -- would pay Google twice for one string.
      AND p.carried_from_id IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM translations t
        WHERE t.proposition_id = p.id
          AND t.field_name = 'content'
          AND t.language_code = p_language_code
      )
    ORDER BY p.created_at ASC
    LIMIT p_limit
  LOOP
    PERFORM public.request_proposition_translation(
      v_prop.id, v_prop.content, ARRAY[p_language_code]
    );
    v_count := v_count + 1;
  END LOOP;

  RAISE LOG 'Backfill enqueued % translations for chat % (%)', v_count, p_chat_id, p_language_code;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.backfill_proposition_translations(bigint, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.backfill_proposition_translations(bigint, text, integer) TO service_role;

COMMENT ON FUNCTION public.backfill_proposition_translations(bigint, text, integer) IS
  'Enqueue translation for a chat''s propositions that lack p_language_code. Idempotent and batched; re-run until it returns 0. Operator tool, service_role only.';
