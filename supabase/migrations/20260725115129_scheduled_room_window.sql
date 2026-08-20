-- Scheduled room windows: a chat that is genuinely CLOSED outside its schedule.
--
-- Context (2026-07-25, docs/RETENTION_EXPERIMENT.md): the GLOBAL front door
-- becomes a daily 30-minute live event (8:00-8:30 AM ET) with 60s phases, so
-- the fast loop can be experienced at all. The pre-existing schedule feature
-- (schedule_windows + process_scheduled_chats, cron every minute) only FREEZES
-- the phase timer -- it does not close the room. Nothing gated writes on
-- schedule_paused (is_chat_paused had exactly one caller,
-- trigger_agent_orchestrator), so a visitor arriving at 3pm could still post
-- into a frozen phase. Two pieces make "closed" real:
--
--   1. get_chat_schedule_state(chat) -- authoritative open/closed plus the next
--      open/close boundary as absolute timestamps. Timezone- and DST-correct
--      because the boundaries are built in the chat's local timezone and cast
--      with AT TIME ZONE. The wedge renders its closed screen from this; the
--      daily summon cron can read the same source.
--
--   2. enforce_chat_schedule_window -- BEFORE INSERT guard on propositions and
--      pairwise_comparisons, so the gate is enforced server-side and not just
--      hidden in the UI. Deliberately NOT exempt for service_role: takes come
--      in through the submit-proposition edge function on the service key, and
--      that path must be gated too.
--
-- Both are inert when chats.schedule_type IS NULL, which is every other chat.

-- =============================================================================
-- 1. Schedule state (open now + next boundary)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_chat_schedule_state(p_chat_id integer)
RETURNS TABLE(
  is_open   BOOLEAN,
  opens_at  TIMESTAMPTZ,
  closes_at TIMESTAMPTZ,
  timezone  TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_chat        RECORD;
  v_tz          TEXT;
  v_now         TIMESTAMPTZ := NOW();
  v_today       DATE;
  v_day_offset  INT;
  v_window_idx  INT;
  v_window      JSONB;
  v_start_dow   INT;
  v_end_dow     INT;
  v_date        DATE;
  v_start_ts    TIMESTAMPTZ;
  v_end_ts      TIMESTAMPTZ;
  v_best_start  TIMESTAMPTZ;
  v_best_end    TIMESTAMPTZ;
BEGIN
  SELECT c.schedule_type, c.schedule_timezone, c.scheduled_start_at,
         c.scheduled_end_at, c.schedule_windows
    INTO v_chat
    FROM public.chats c
   WHERE c.id = p_chat_id;

  -- No schedule configured -> always open (the state every other chat is in).
  IF NOT FOUND OR v_chat.schedule_type IS NULL THEN
    RETURN QUERY SELECT TRUE, NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ,
                        COALESCE(v_chat.schedule_timezone, 'UTC');
    RETURN;
  END IF;

  v_tz := COALESCE(v_chat.schedule_timezone, 'UTC');

  -- One-shot schedules already carry absolute boundaries.
  IF v_chat.schedule_type = 'once' THEN
    RETURN QUERY SELECT public.is_chat_in_schedule_window(p_chat_id),
                        v_chat.scheduled_start_at, v_chat.scheduled_end_at, v_tz;
    RETURN;
  END IF;

  IF v_chat.schedule_windows IS NULL
     OR jsonb_array_length(v_chat.schedule_windows) = 0 THEN
    RETURN QUERY SELECT FALSE, NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ, v_tz;
    RETURN;
  END IF;

  v_today := (v_now AT TIME ZONE v_tz)::DATE;

  -- Walk local days for the first window that has not finished yet. Starting at
  -- -1 catches an overnight window that opened yesterday and is still running.
  -- Days ascend, so the first day that yields a candidate holds the answer; we
  -- keep the earliest start within that day.
  FOR v_day_offset IN -1..7 LOOP
    v_date := v_today + v_day_offset;

    FOR v_window_idx IN 0..(jsonb_array_length(v_chat.schedule_windows) - 1) LOOP
      v_window := v_chat.schedule_windows -> v_window_idx;
      v_start_dow := public.day_name_to_number(v_window->>'start_day');
      v_end_dow   := public.day_name_to_number(v_window->>'end_day');

      CONTINUE WHEN v_start_dow IS DISTINCT FROM EXTRACT(DOW FROM v_date)::INT;

      v_start_ts := (v_date + (v_window->>'start_time')::TIME) AT TIME ZONE v_tz;
      -- end_day may be a later weekday; (end - start + 7) % 7 is the day span.
      v_end_ts := (
        (v_date + ((v_end_dow - v_start_dow + 7) % 7))
        + (v_window->>'end_time')::TIME
      ) AT TIME ZONE v_tz;

      IF v_end_ts > v_now
         AND (v_best_start IS NULL OR v_start_ts < v_best_start) THEN
        v_best_start := v_start_ts;
        v_best_end   := v_end_ts;
      END IF;
    END LOOP;

    EXIT WHEN v_best_start IS NOT NULL;
  END LOOP;

  -- is_chat_in_schedule_window stays the single source of truth for "open now"
  -- so this function can never disagree with process_scheduled_chats.
  RETURN QUERY SELECT public.is_chat_in_schedule_window(p_chat_id),
                      v_best_start, v_best_end, v_tz;
END;
$$;

COMMENT ON FUNCTION public.get_chat_schedule_state(integer) IS
  'Open/closed state of a scheduled chat plus the next open and close boundary '
  'as absolute timestamps (DST-correct). Chats without a schedule report open '
  'with NULL boundaries.';

GRANT EXECUTE ON FUNCTION public.get_chat_schedule_state(integer)
  TO anon, authenticated, service_role;

-- =============================================================================
-- 2. Write guard -- "closed" means closed
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_chat_schedule_window()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_chat_id        BIGINT;
  v_schedule_type  TEXT;
BEGIN
  -- Machine-authored rows are never gated. Carried-forward winners are written
  -- by the round-advance trigger and must land even when the boundary falls
  -- mid-transition; agent rows (participant_id IS NULL) have no human clock.
  IF TG_TABLE_NAME = 'propositions' THEN
    IF NEW.carried_from_id IS NOT NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.participant_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT cy.chat_id
    INTO v_chat_id
    FROM public.rounds r
    JOIN public.cycles cy ON cy.id = r.cycle_id
   WHERE r.id = NEW.round_id;

  IF v_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.schedule_type INTO v_schedule_type
    FROM public.chats c WHERE c.id = v_chat_id;

  -- Unscheduled chat -> no gate. This is the fast path for every other chat.
  IF v_schedule_type IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT public.is_chat_in_schedule_window(v_chat_id::INT) THEN
    RAISE EXCEPTION 'CHAT_CLOSED: this room is only open during its scheduled window'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_chat_schedule_window() IS
  'BEFORE INSERT guard: rejects human takes/votes submitted while a scheduled '
  'chat is outside its window. Inert for chats with schedule_type IS NULL.';

DROP TRIGGER IF EXISTS enforce_schedule_window_on_propositions ON public.propositions;
CREATE TRIGGER enforce_schedule_window_on_propositions
  BEFORE INSERT ON public.propositions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_chat_schedule_window();

DROP TRIGGER IF EXISTS enforce_schedule_window_on_pairwise ON public.pairwise_comparisons;
CREATE TRIGGER enforce_schedule_window_on_pairwise
  BEFORE INSERT ON public.pairwise_comparisons
  FOR EACH ROW EXECUTE FUNCTION public.enforce_chat_schedule_window();
