-- C15 fix: the chat-wide window is carried by the latest LIVE round, not the
-- latest ROOT round. Once the spine descends (root sealed, tip = some child
-- subround), the root's phase is frozen forever — reading the window from it
-- would block all spawning after the first winner. The tip is always live
-- (spine continuation), so the newest non-completed round IS the clock.

CREATE OR REPLACE FUNCTION public.get_or_create_node_cycle(p_proposition_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id      BIGINT;
  v_branching    BOOLEAN;
  v_existing     BIGINT;
  v_window       RECORD;
  v_cycle_id     BIGINT;
BEGIN
  SELECT cy.chat_id INTO v_chat_id
  FROM propositions p
  JOIN rounds r ON r.id = p.round_id
  JOIN cycles cy ON cy.id = r.cycle_id
  WHERE p.id = p_proposition_id;

  IF v_chat_id IS NULL THEN
    RAISE EXCEPTION 'proposition % not found', p_proposition_id;
  END IF;

  SELECT branching_enabled INTO v_branching FROM chats WHERE id = v_chat_id;
  IF NOT v_branching THEN
    RAISE EXCEPTION 'branching not enabled for chat %', v_chat_id;
  END IF;

  IF current_setting('role', true) <> 'service_role'
     AND NOT EXISTS (
       SELECT 1 FROM participants
       WHERE chat_id = v_chat_id AND user_id = auth.uid() AND status = 'active'
     ) THEN
    RAISE EXCEPTION 'not an active participant of chat %', v_chat_id;
  END IF;

  SELECT id INTO v_existing FROM cycles WHERE parent_proposition_id = p_proposition_id;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- The chat-wide window = the newest LIVE round anywhere in the tree.
  SELECT r.phase, r.phase_ends_at INTO v_window
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = v_chat_id AND r.completed_at IS NULL
  ORDER BY r.id DESC
  LIMIT 1;

  IF v_window.phase IS DISTINCT FROM 'proposing' THEN
    RAISE EXCEPTION 'window_closed';
  END IF;

  INSERT INTO cycles (chat_id, parent_proposition_id)
  VALUES (v_chat_id, p_proposition_id)
  RETURNING id INTO v_cycle_id;

  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle_id, 1, 'proposing', NOW(), v_window.phase_ends_at);

  RETURN v_cycle_id;
EXCEPTION WHEN unique_violation THEN
  SELECT id INTO v_existing FROM cycles WHERE parent_proposition_id = p_proposition_id;
  RETURN v_existing;
END;
$function$;

-- Same window redefinition in the bootstrap's window_phase.
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

  -- The chat-wide window = the newest LIVE round anywhere in the tree.
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
