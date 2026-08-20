-- Translate the DESCENDED-THREAD read path too.
--
-- The ranked root list already resolves translations (20260717140700), but a
-- thread you descend into loads through a different RPC, get_node_bootstrap,
-- which emits three raw content fields: the parent node, each reply, and the
-- sealed winner. 7 of GLOBAL's 10 non-English opinions live inside node
-- threads — and the duel that motivated all this (Arabic vs English) was under
-- a node. So without this, exactly the surface that exposed the problem stayed
-- in the original script.
--
-- Same contract as the ranked path: content stays the author's original,
-- content_translated resolves requested-language -> en -> original. The client
-- resolves at the fetch boundary, so treeWalk keeps reading `.content`.

-- ---------------------------------------------------------------------------
-- Reusable scalar resolver
-- ---------------------------------------------------------------------------
-- One place that knows the fallback ladder for a single proposition. Used here
-- for the node bootstrap's row-at-a-time JSONB assembly (small N). The ranked
-- path deliberately does NOT call this — it resolves set-based in a LEFT JOIN,
-- which matters because it's the hottest RPC under vote-time concurrency and a
-- per-row function call would plan worse.
--
-- Resolves carried-forward copies through their root (same rule the trigger and
-- the ranked path use), so a carried winner shows its root's translation.
CREATE OR REPLACE FUNCTION public.proposition_content_translated(
  p_proposition_id bigint,
  p_content text,
  p_language_code text
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN p_language_code IS NULL THEN p_content
    ELSE COALESCE(
      (SELECT t.translated_text FROM public.translations t
       WHERE t.proposition_id = COALESCE(
               (SELECT carried_from_id FROM public.propositions WHERE id = p_proposition_id),
               p_proposition_id)
         AND t.field_name = 'content'
         AND t.language_code = p_language_code
       LIMIT 1),
      (SELECT t.translated_text FROM public.translations t
       WHERE p_language_code <> 'en'
         AND t.proposition_id = COALESCE(
               (SELECT carried_from_id FROM public.propositions WHERE id = p_proposition_id),
               p_proposition_id)
         AND t.field_name = 'content'
         AND t.language_code = 'en'
       LIMIT 1),
      p_content)
  END
$function$;

REVOKE ALL ON FUNCTION public.proposition_content_translated(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.proposition_content_translated(bigint, text, text)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.proposition_content_translated(bigint, text, text) IS
  'One proposition''s content in p_language_code, resolving requested -> en -> original (via the root of carried copies). NULL language returns the original unchanged.';

-- ---------------------------------------------------------------------------
-- Language-aware node bootstrap
-- ---------------------------------------------------------------------------
-- p_language_code defaults NULL (originals only) so any 1-arg caller is
-- unchanged. DROP + recreate rather than add an overload: a defaulted 2-arg
-- beside a 1-arg makes get_node_bootstrap(bigint) ambiguous.
DROP FUNCTION IF EXISTS public.get_node_bootstrap(bigint);

CREATE FUNCTION public.get_node_bootstrap(
  p_proposition_id bigint,
  p_language_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_parent       RECORD;
  v_chat_id      BIGINT;
  v_branching    BOOLEAN;
  v_window_phase TEXT;
  v_cycle_id     BIGINT;
  v_round        RECORD;
  v_node         JSONB := NULL;
  v_winner       JSONB := NULL;
BEGIN
  SELECT p.id, p.content, cy.chat_id INTO v_parent
  FROM propositions p
  JOIN rounds r ON r.id = p.round_id
  JOIN cycles cy ON cy.id = r.cycle_id
  WHERE p.id = p_proposition_id;

  IF v_parent.id IS NULL THEN
    RAISE EXCEPTION 'proposition % not found', p_proposition_id;
  END IF;
  v_chat_id := v_parent.chat_id;

  SELECT branching_enabled INTO v_branching FROM chats WHERE id = v_chat_id;

  IF current_setting('role', true) <> 'service_role'
     AND NOT EXISTS (
       SELECT 1 FROM participants
       WHERE chat_id = v_chat_id AND user_id = auth.uid() AND status = 'active'
     ) THEN
    RAISE EXCEPTION 'not an active participant of chat %', v_chat_id;
  END IF;

  SELECT r.phase INTO v_window_phase
  FROM rounds r JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = v_chat_id AND r.completed_at IS NULL
  ORDER BY r.id DESC LIMIT 1;

  SELECT id INTO v_cycle_id FROM cycles WHERE parent_proposition_id = p_proposition_id;

  IF v_cycle_id IS NOT NULL THEN
    SELECT id, phase, phase_started_at, phase_ends_at, completed_at, winning_proposition_id
    INTO v_round
    FROM rounds WHERE cycle_id = v_cycle_id
    ORDER BY id DESC LIMIT 1;

    IF v_round.winning_proposition_id IS NOT NULL THEN
      SELECT jsonb_build_object(
        'id', id,
        'content', content,
        'content_translated',
          public.proposition_content_translated(id, content, p_language_code)
      ) INTO v_winner
      FROM propositions WHERE id = v_round.winning_proposition_id;
    END IF;

    v_node := jsonb_build_object(
      'cycle_id', v_cycle_id,
      'round', jsonb_build_object(
        'id', v_round.id,
        'phase', v_round.phase,
        'phase_started_at', v_round.phase_started_at,
        'phase_ends_at', v_round.phase_ends_at,
        'completed_at', v_round.completed_at,
        'winning_proposition_id', v_round.winning_proposition_id
      ),
      'propositions', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', pr.id,
          'content', pr.content,
          'content_translated',
            public.proposition_content_translated(pr.id, pr.content, p_language_code),
          'participant_id', pr.participant_id,
          'is_agent', COALESCE(pa.is_agent, false),
          'created_at', pr.created_at
        ) ORDER BY pr.created_at)
        FROM propositions pr
        LEFT JOIN participants pa ON pa.id = pr.participant_id
        WHERE pr.round_id = v_round.id
      ), '[]'::jsonb),
      'winner', v_winner
    );
  END IF;

  RETURN jsonb_build_object(
    'parent', jsonb_build_object(
      'id', v_parent.id,
      'content', v_parent.content,
      'content_translated',
        public.proposition_content_translated(v_parent.id, v_parent.content, p_language_code)
    ),
    'chat_id', v_chat_id,
    'branching_enabled', v_branching,
    'window_phase', v_window_phase,
    'node', v_node
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_node_bootstrap(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_node_bootstrap(bigint, text)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_node_bootstrap(bigint, text) IS
  'One node''s snapshot (parent, live/sealed subround, propositions, winner). p_language_code NULL (default) = originals; set it to add content_translated (requested -> en -> original) to parent, each proposition, and the winner.';
