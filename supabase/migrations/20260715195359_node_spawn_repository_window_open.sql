-- Repository chats (never_seals) keep the reply composer open at all times — the
-- client shows it regardless of the oscillating proposing/rating window
-- (treeWalk: windowProposing = repository || phase==='proposing'). But
-- get_or_create_node_cycle still hard-required a 'proposing' window to spawn a
-- new sub-thread, so replying to a LEAF failed with 'window_closed' whenever the
-- window was in 'rating' — the intermittent "could not submit" on GLOBAL.
-- Exempt never_seals chats from the window gate; phase-gated chats keep the
-- original rule. (Replying into an EXISTING thread was never affected — it skips
-- the spawn and submits straight to the child round.)
CREATE OR REPLACE FUNCTION public.get_or_create_node_cycle(p_proposition_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id      BIGINT;
  v_branching    BOOLEAN;
  v_never_seals  BOOLEAN;
  v_existing     BIGINT;
  v_root_round   RECORD;
  v_cycle_id     BIGINT;
BEGIN
  -- The proposition's chat (prop → round → cycle → chat)
  SELECT cy.chat_id INTO v_chat_id
  FROM propositions p
  JOIN rounds r ON r.id = p.round_id
  JOIN cycles cy ON cy.id = r.cycle_id
  WHERE p.id = p_proposition_id;

  IF v_chat_id IS NULL THEN
    RAISE EXCEPTION 'proposition % not found', p_proposition_id;
  END IF;

  SELECT branching_enabled, never_seals INTO v_branching, v_never_seals
  FROM chats WHERE id = v_chat_id;
  IF NOT v_branching THEN
    RAISE EXCEPTION 'branching not enabled for chat %', v_chat_id;
  END IF;

  -- Caller must be an active participant of the chat (service role bypasses).
  IF current_setting('role', true) <> 'service_role'
     AND NOT EXISTS (
       SELECT 1 FROM participants
       WHERE chat_id = v_chat_id AND user_id = auth.uid() AND status = 'active'
     ) THEN
    RAISE EXCEPTION 'not an active participant of chat %', v_chat_id;
  END IF;

  -- Idempotent: one child cycle per proposition.
  SELECT id INTO v_existing FROM cycles WHERE parent_proposition_id = p_proposition_id;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- The child round inherits the ROOT round's clock so the whole tree flips
  -- together.
  SELECT r.id, r.phase, r.phase_ends_at INTO v_root_round
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = v_chat_id AND c.parent_proposition_id IS NULL
  ORDER BY r.id DESC
  LIMIT 1;

  -- Phase-gated chats: spawning is only meaningful during a proposing window.
  -- Repository chats (never_seals) are always alive, so skip the window gate —
  -- the reply composer is open regardless of the oscillating phase.
  IF NOT COALESCE(v_never_seals, false)
     AND v_root_round.phase IS DISTINCT FROM 'proposing' THEN
    RAISE EXCEPTION 'window_closed';
  END IF;

  INSERT INTO cycles (chat_id, parent_proposition_id)
  VALUES (v_chat_id, p_proposition_id)
  RETURNING id INTO v_cycle_id;

  INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
  VALUES (v_cycle_id, 1, 'proposing', NOW(), v_root_round.phase_ends_at);

  RETURN v_cycle_id;
EXCEPTION WHEN unique_violation THEN
  -- Lost a race to another spawner — return theirs.
  SELECT id INTO v_existing FROM cycles WHERE parent_proposition_id = p_proposition_id;
  RETURN v_existing;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_or_create_node_cycle(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_node_cycle(BIGINT) TO authenticated, service_role;
