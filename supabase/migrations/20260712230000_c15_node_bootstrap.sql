-- C15 node bootstrap — one RPC returning everything the node screen needs
-- (mirrors the get_chat_detail_bootstrap pattern: one call, JSONB snapshot,
-- no client fan-out).
--
-- Shape:
-- {
--   "parent":  { "id", "content" },
--   "chat_id": <bigint>,
--   "branching_enabled": <bool>,
--   "window_phase": "proposing" | "rating" | null,   -- ROOT round phase (the chat-wide window)
--   "node": null                                      -- not materialized yet
--         | { "cycle_id", "round": { "id", "phase", "phase_started_at",
--             "phase_ends_at", "completed_at", "winning_proposition_id" },
--             "propositions": [ { "id", "content", "participant_id",
--                                 "is_agent", "created_at" } ],
--             "winner": { "id", "content" } | null }
-- }
--
-- A null "node" means the subround hasn't been materialized — the client
-- shows the empty "be the first" state and calls get_or_create_node_cycle on
-- the first propose action (lazy per C15).

CREATE OR REPLACE FUNCTION public.get_node_bootstrap(p_proposition_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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

  -- The chat-wide window = the latest ROOT round's phase.
  SELECT r.phase INTO v_window_phase
  FROM rounds r JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = v_chat_id AND c.parent_proposition_id IS NULL
  ORDER BY r.id DESC LIMIT 1;

  SELECT id INTO v_cycle_id FROM cycles WHERE parent_proposition_id = p_proposition_id;

  IF v_cycle_id IS NOT NULL THEN
    SELECT id, phase, phase_started_at, phase_ends_at, completed_at, winning_proposition_id
    INTO v_round
    FROM rounds WHERE cycle_id = v_cycle_id
    ORDER BY id DESC LIMIT 1;

    IF v_round.winning_proposition_id IS NOT NULL THEN
      SELECT jsonb_build_object('id', id, 'content', content) INTO v_winner
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
    'parent', jsonb_build_object('id', v_parent.id, 'content', v_parent.content),
    'chat_id', v_chat_id,
    'branching_enabled', v_branching,
    'window_phase', v_window_phase,
    'node', v_node
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_node_bootstrap(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_node_bootstrap(BIGINT) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_node_bootstrap(BIGINT) IS
  'C15 node screen snapshot: parent proposition, chat window phase, and the (possibly unmaterialized) child subround with its propositions and winner. One call, no client fan-out.';
