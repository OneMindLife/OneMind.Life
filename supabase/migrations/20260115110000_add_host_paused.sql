-- =============================================================================
-- MIGRATION: Host Manual Pause
-- =============================================================================
-- Allows hosts to manually pause/unpause a chat independently of schedule.
-- When paused: timer stops, remaining time saved
-- When resumed: timer resumes from saved time
-- =============================================================================

-- =============================================================================
-- STEP 1: Add host_paused column
-- =============================================================================

ALTER TABLE public.chats
ADD COLUMN IF NOT EXISTS host_paused boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.chats.host_paused IS
'Whether the chat is manually paused by the host. Independent of schedule_paused.';

-- =============================================================================
-- STEP 2: Create helper function to check if chat is paused (either way)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_chat_paused(p_chat_id bigint)
RETURNS boolean AS $$
  SELECT schedule_paused OR host_paused
  FROM public.chats
  WHERE id = p_chat_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION public.is_chat_paused IS
'Returns true if chat is paused by either schedule or host.';

-- =============================================================================
-- STEP 3: Create host_pause_chat function
-- =============================================================================

CREATE OR REPLACE FUNCTION public.host_pause_chat(p_chat_id bigint)
RETURNS void AS $$
DECLARE
  v_current_round record;
  v_is_host boolean;
  v_found boolean;
BEGIN
  -- Verify caller is host
  SELECT EXISTS(
    SELECT 1 FROM public.participants
    WHERE chat_id = p_chat_id
      AND user_id = auth.uid()
      AND is_host = true
      AND status = 'active'
  ) INTO v_is_host;

  IF NOT v_is_host THEN
    RAISE EXCEPTION 'Only hosts can pause the chat';
  END IF;

  -- Check if already paused
  IF (SELECT host_paused FROM public.chats WHERE id = p_chat_id) THEN
    RAISE NOTICE 'Chat % is already paused by host', p_chat_id;
    RETURN;
  END IF;

  -- Get current active round (explicit columns to avoid record type issues)
  SELECT r.id, r.phase_ends_at INTO v_current_round
  FROM public.rounds r
  JOIN public.cycles c ON r.cycle_id = c.id
  WHERE c.chat_id = p_chat_id
    AND r.phase IN ('proposing', 'rating')
    AND r.completed_at IS NULL
  ORDER BY r.created_at DESC
  LIMIT 1;

  v_found := FOUND;

  -- If there's an active round with a timer, save remaining time and clear phase_ends_at
  -- CRITICAL: Clearing phase_ends_at stops the timer - Edge Function won't process it
  IF v_found AND v_current_round.phase_ends_at IS NOT NULL THEN
    UPDATE public.rounds
    SET phase_time_remaining_seconds = GREATEST(0,
        EXTRACT(EPOCH FROM (phase_ends_at - now()))::integer
      ),
      phase_ends_at = NULL
    WHERE id = v_current_round.id;

    RAISE NOTICE '[HOST PAUSE] Round % paused with % seconds remaining',
      v_current_round.id,
      GREATEST(0, EXTRACT(EPOCH FROM (v_current_round.phase_ends_at - now()))::integer);
  END IF;

  -- Set host_paused flag
  UPDATE public.chats SET host_paused = true WHERE id = p_chat_id;

  RAISE NOTICE '[HOST PAUSE] Chat % paused by host', p_chat_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.host_pause_chat IS
'Pauses a chat manually by the host. Saves remaining timer state.';

-- =============================================================================
-- STEP 4: Create host_resume_chat function
-- =============================================================================

CREATE OR REPLACE FUNCTION public.host_resume_chat(p_chat_id bigint)
RETURNS void AS $$
DECLARE
  v_current_round record;
  v_is_host boolean;
  v_schedule_paused boolean;
  v_found boolean;
BEGIN
  -- Verify caller is host
  SELECT EXISTS(
    SELECT 1 FROM public.participants
    WHERE chat_id = p_chat_id
      AND user_id = auth.uid()
      AND is_host = true
      AND status = 'active'
  ) INTO v_is_host;

  IF NOT v_is_host THEN
    RAISE EXCEPTION 'Only hosts can resume the chat';
  END IF;

  -- Check if not paused
  IF NOT (SELECT host_paused FROM public.chats WHERE id = p_chat_id) THEN
    RAISE NOTICE 'Chat % is not paused by host', p_chat_id;
    RETURN;
  END IF;

  -- Clear host_paused flag first
  UPDATE public.chats SET host_paused = false WHERE id = p_chat_id;

  -- Check if schedule is also paused
  SELECT schedule_paused INTO v_schedule_paused
  FROM public.chats WHERE id = p_chat_id;

  -- Only restore timer if schedule is also not paused
  IF NOT v_schedule_paused THEN
    -- Get current round that might have saved time (explicit columns)
    SELECT r.id, r.phase_time_remaining_seconds INTO v_current_round
    FROM public.rounds r
    JOIN public.cycles c ON r.cycle_id = c.id
    WHERE c.chat_id = p_chat_id
      AND r.phase IN ('proposing', 'rating')
      AND r.completed_at IS NULL
      AND r.phase_time_remaining_seconds IS NOT NULL
    ORDER BY r.created_at DESC
    LIMIT 1;

    v_found := FOUND;

    -- Restore timer if there was saved time
    IF v_found AND v_current_round.phase_time_remaining_seconds > 0 THEN
      UPDATE public.rounds
      SET phase_ends_at = now() + (phase_time_remaining_seconds || ' seconds')::interval,
          phase_time_remaining_seconds = NULL
      WHERE id = v_current_round.id;

      RAISE NOTICE '[HOST RESUME] Round % resumed with % seconds',
        v_current_round.id, v_current_round.phase_time_remaining_seconds;
    END IF;
  ELSE
    RAISE NOTICE '[HOST RESUME] Chat % resumed by host but still paused by schedule', p_chat_id;
  END IF;

  RAISE NOTICE '[HOST RESUME] Chat % resumed by host', p_chat_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.host_resume_chat IS
'Resumes a chat that was manually paused by the host. Restores timer if schedule is not also paused.';

-- =============================================================================
-- STEP 5: Index for efficient querying
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_chats_host_paused
ON public.chats(host_paused)
WHERE host_paused = true;
