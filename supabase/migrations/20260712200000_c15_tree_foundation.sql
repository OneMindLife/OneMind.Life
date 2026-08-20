-- C15 tree foundation (docs/ONEMIND_CONCEPT.md C15) — every proposition can
-- root its own follow-up subround. This migration is the DB layer of the
-- one-level vertical slice:
--
--   * cycles.parent_proposition_id — NULL = root cycle (today's behavior),
--     set = this cycle is the follow-up contest for that proposition.
--     One child cycle per proposition (unique partial index).
--   * chats.branching_enabled — per-chat pilot flag.
--   * Tree mode is CLOCK-ONLY (chat-wide 12h/12h windows): enforced
--     declaratively by a CHECK that branching chats have all early-advance
--     thresholds NULL — every threshold trigger short-circuits on NULLs, so
--     no trigger bodies need surgery.
--   * on_cycle_winner_set gated: a CHILD cycle sealing must not spawn a new
--     ROOT cycle nor end the chat — the node just settles.
--   * notify_push_round gated: pushes fire for ROOT rounds only (a window
--     flip across N nodes must not send N pushes).
--   * get_or_create_node_cycle(p_proposition_id) — lazy spawn. Creates the
--     child cycle + its first round synced to the chat's current proposing
--     window; idempotent (returns the existing child cycle id).

ALTER TABLE public.cycles
  ADD COLUMN IF NOT EXISTS parent_proposition_id BIGINT REFERENCES public.propositions(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_cycles_parent_proposition
  ON public.cycles(parent_proposition_id) WHERE parent_proposition_id IS NOT NULL;

COMMENT ON COLUMN public.cycles.parent_proposition_id IS
  'C15 tree: NULL = root cycle; set = this cycle is the follow-up subround contest for that proposition. One child cycle per proposition.';

ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS branching_enabled BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.chats.branching_enabled IS
  'C15 tree mode pilot flag. Branching chats are clock-only (see check constraint).';

-- Tree mode is clock-only: thresholds must be NULL so every early-advance
-- trigger (proposition/skip/matches-finalize) short-circuits by design.
ALTER TABLE public.chats DROP CONSTRAINT IF EXISTS chk_branching_clock_only;
ALTER TABLE public.chats ADD CONSTRAINT chk_branching_clock_only CHECK (
  NOT branching_enabled OR (
    proposing_threshold_percent IS NULL AND proposing_threshold_count IS NULL
    AND rating_threshold_percent IS NULL AND rating_threshold_count IS NULL
  )
);

-- ── Gate on_cycle_winner_set: child cycles seal quietly ─────────────────────
CREATE OR REPLACE FUNCTION public.on_cycle_winner_set()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_chat_id BIGINT;
    v_max_cycles INTEGER;
    v_completed_count INTEGER;
    new_cycle_id BIGINT;
    new_round_id BIGINT;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    -- C15: a CHILD cycle (follow-up subround) sealing is a node settling —
    -- it must not open a new root cycle and must not end the chat.
    IF NEW.parent_proposition_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Get chat_id + cap from this cycle's chat
    SELECT c.chat_id, ch.max_cycles
    INTO v_chat_id, v_max_cycles
    FROM cycles c
    JOIN chats ch ON ch.id = c.chat_id
    WHERE c.id = NEW.id;

    -- Stop-after-N: if this chat caps cycles, check whether we've hit the cap.
    -- Only ROOT cycles count toward the cap (child cycles are tree nodes).
    IF v_max_cycles IS NOT NULL THEN
        SELECT COUNT(*) INTO v_completed_count
        FROM cycles
        WHERE chat_id = v_chat_id AND completed_at IS NOT NULL
          AND parent_proposition_id IS NULL;

        IF v_completed_count >= v_max_cycles THEN
            -- Cap reached: seal the chat. No new cycle.
            UPDATE chats SET ended_at = NOW() WHERE id = v_chat_id AND ended_at IS NULL;
            RETURN NEW;
        END IF;
    END IF;

    -- Continuous (default): create new ROOT cycle for the chat
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO new_cycle_id;

    new_round_id := create_round_for_cycle(new_cycle_id, v_chat_id, 1);

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.on_cycle_winner_set() IS
    'On cycle consensus: child (tree-node) cycles seal quietly. Root cycles: if chats.max_cycles is reached, end the chat; otherwise start the next root cycle (continuous default).';

-- ── Gate notify_push_round: root rounds only ────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_push_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id     BIGINT;
  v_event       TEXT;
  v_secret      TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  IF NEW.winning_proposition_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.winning_proposition_id IS DISTINCT FROM NEW.winning_proposition_id) THEN
    v_event := 'winner';
  ELSIF NEW.phase = 'rating'
     AND (TG_OP = 'INSERT' OR OLD.phase IS DISTINCT FROM 'rating') THEN
    v_event := 'vote_open';
  ELSIF NEW.phase = 'proposing'
     AND (TG_OP = 'INSERT' OR OLD.phase IS DISTINCT FROM 'proposing') THEN
    v_event := 'round_open';
  ELSE
    RETURN NEW;
  END IF;

  -- Root cycles only: a window flip across N tree nodes must not fan out N
  -- pushes. (C15 child cycles have parent_proposition_id set.)
  SELECT ch.id INTO v_chat_id
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id
    AND c.parent_proposition_id IS NULL
    AND ch.is_preview = false
    AND ch.is_arena = false
    AND ch.telegram_chat_id IS NULL;

  IF v_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'push_internal_secret';

  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_push_round skipped: push_internal_secret not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('push-events');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object('pushevent', v_event, 'round_id', NEW.id, 'chat_id', v_chat_id)
  ) INTO v_request_id;

  RAISE LOG 'notify_push_round % for round % chat % (request_id %)',
    v_event, NEW.id, v_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_push_round error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

-- ── Lazy node spawn ─────────────────────────────────────────────────────────
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

  SELECT branching_enabled INTO v_branching FROM chats WHERE id = v_chat_id;
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

  -- Spawn is only meaningful during the chat's proposing window; the child
  -- round inherits the ROOT round's clock so the whole tree flips together.
  SELECT r.id, r.phase, r.phase_ends_at INTO v_root_round
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE c.chat_id = v_chat_id AND c.parent_proposition_id IS NULL
  ORDER BY r.id DESC
  LIMIT 1;

  IF v_root_round.phase IS DISTINCT FROM 'proposing' THEN
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

COMMENT ON FUNCTION public.get_or_create_node_cycle(BIGINT) IS
  'C15 lazy node spawn: returns the child cycle for a proposition, creating it (with a round synced to the chat''s current proposing window) on first touch. Requires branching_enabled + active participant. Idempotent.';
