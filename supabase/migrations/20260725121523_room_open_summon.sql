-- One "the room is open" summon per session, instead of one ping per phase.
--
-- Context (2026-07-25): GLOBAL became a scheduled 30-minute daily event with 60s
-- phases (20260725115129_scheduled_room_window). notify_telegram_round
-- broadcasts to the OneMind channel on EVERY phase transition -- fine at 12h
-- phases (2 posts/day), a spam cannon at 60s (~30 posts per session). And the
-- push half never fired for this room at all: notify_push_round filters
-- is_arena = false, and 1269 is an arena chat, so the wedge's "Notify me when it
-- opens" button collected FCM tokens nothing would ever send to.
--
-- Both are the same mistake -- the interesting event for a scheduled room is not
-- a phase change, it is the room OPENING. That happens exactly once per session,
-- when process_scheduled_chats flips schedule_paused true -> false. So:
--
--   1. notify_telegram_round stops broadcasting phase changes for scheduled
--      chats (bound-GROUP posts are untouched -- only the channel broadcast).
--   2. process_scheduled_chats emits a 'room_open' event on resume, to the
--      telegram-bot (channel broadcast) and push-events (FCM) edge functions.
--   3. room_open_subscribers holds who asked to be summoned. It cannot be
--      root_watches: that table is keyed on participant_id, and the whole point
--      of the closed screen is that a visitor outside the window does NOT
--      become a participant.

-- =============================================================================
-- 1. Who gets summoned
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.room_open_subscribers (
  chat_id    BIGINT NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  user_id    UUID   NOT NULL REFERENCES auth.users(id)   ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (chat_id, user_id)
);

COMMENT ON TABLE public.room_open_subscribers IS
  'Users who asked to be pinged when a scheduled room opens. Deliberately keyed '
  'on user_id, not participant_id: opt-in happens on the closed screen, before '
  '(and without) joining.';

ALTER TABLE public.room_open_subscribers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS room_open_subscribers_owner ON public.room_open_subscribers;
CREATE POLICY room_open_subscribers_owner ON public.room_open_subscribers
  FOR ALL
  USING (
    (current_setting('role', true) = 'service_role') OR user_id = auth.uid()
  )
  WITH CHECK (
    (current_setting('role', true) = 'service_role') OR user_id = auth.uid()
  );

GRANT SELECT, INSERT, DELETE ON public.room_open_subscribers TO anon, authenticated;

-- =============================================================================
-- 2. Scheduled chats: no per-phase channel broadcast
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_telegram_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_event         TEXT;
  v_secret        TEXT;
  v_url           TEXT;
  v_tg_chat_id    BIGINT;
  v_is_official   BOOLEAN;
  v_schedule_type TEXT;
  v_request_id    BIGINT;
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

  SELECT ch.telegram_chat_id, ch.is_official, ch.schedule_type
  INTO v_tg_chat_id, v_is_official, v_schedule_type
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'telegram_internal_secret';

  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_telegram_round skipped: telegram_internal_secret not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('telegram-bot');

  -- Broadcast to the OneMind channel for the official web room (retention loop).
  -- SCHEDULED rooms are excluded: their phases are 60s, so a per-phase broadcast
  -- would post ~30 times per session. They announce once, on open, from
  -- process_scheduled_chats.
  IF v_is_official AND v_schedule_type IS NULL THEN
    SELECT net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_secret
      ),
      body := jsonb_build_object('tgevent', v_event, 'round_id', NEW.id, 'broadcast', true)
    ) INTO v_request_id;
    RAISE LOG 'notify_telegram_round broadcast % for round % (request_id %)',
      v_event, NEW.id, v_request_id;
  END IF;

  -- Bound Telegram group (per-group Lens/House posts). Unchanged.
  IF v_tg_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object('tgevent', v_event, 'round_id', NEW.id, 'telegram_chat_id', v_tg_chat_id)
  ) INTO v_request_id;

  RAISE LOG 'notify_telegram_round % for round % chat % (request_id %)',
    v_event, NEW.id, v_tg_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_telegram_round error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

-- =============================================================================
-- 3. The summon itself: one event when the room unpauses
-- =============================================================================

CREATE OR REPLACE FUNCTION public.emit_room_open(p_chat_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_official BOOLEAN;
  v_tg_secret   TEXT;
  v_push_secret TEXT;
  v_request_id  BIGINT;
BEGIN
  SELECT is_official INTO v_is_official FROM chats WHERE id = p_chat_id;

  -- Telegram channel broadcast: the official room only (the channel is a single
  -- public surface; a private scheduled chat has no business posting there).
  IF COALESCE(v_is_official, false) THEN
    SELECT decrypted_secret INTO v_tg_secret
    FROM vault.decrypted_secrets WHERE name = 'telegram_internal_secret';

    IF v_tg_secret IS NULL THEN
      RAISE WARNING 'emit_room_open: telegram_internal_secret not configured';
    ELSE
      SELECT net.http_post(
        url := get_edge_function_url('telegram-bot'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_tg_secret
        ),
        body := jsonb_build_object('tgevent', 'room_open', 'chat_id', p_chat_id, 'broadcast', true)
      ) INTO v_request_id;
      RAISE LOG 'emit_room_open telegram broadcast chat % (request_id %)',
        p_chat_id, v_request_id;
    END IF;
  END IF;

  -- Web push to everyone who asked on the closed screen.
  SELECT decrypted_secret INTO v_push_secret
  FROM vault.decrypted_secrets WHERE name = 'push_internal_secret';

  IF v_push_secret IS NULL THEN
    RAISE WARNING 'emit_room_open: push_internal_secret not configured';
  ELSE
    SELECT net.http_post(
      url := get_edge_function_url('push-events'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_push_secret
      ),
      body := jsonb_build_object('pushevent', 'room_open', 'chat_id', p_chat_id)
    ) INTO v_request_id;
    RAISE LOG 'emit_room_open push chat % (request_id %)', p_chat_id, v_request_id;
  END IF;

EXCEPTION WHEN OTHERS THEN
  -- A summon failure must never roll back the resume itself.
  RAISE WARNING 'emit_room_open error for chat %: %', p_chat_id, SQLERRM;
END;
$function$;

COMMENT ON FUNCTION public.emit_room_open(BIGINT) IS
  'Fires the once-per-session "the room is open" summon (Telegram channel + FCM). '
  'Called from process_scheduled_chats on resume, never from a phase transition.';

-- process_scheduled_chats: same body as before, plus the emit_room_open call on
-- the resume branch. (Reproduced in full because plpgsql has no partial patch.)
CREATE OR REPLACE FUNCTION public.process_scheduled_chats()
RETURNS TABLE(chat_id integer, action text, details text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_chat RECORD;
    v_in_window BOOLEAN;
    v_current_round RECORD;
    v_remaining_seconds INTEGER;
    v_phase_duration INTEGER;
BEGIN
    FOR v_chat IN
        SELECT c.id, c.is_active, c.schedule_paused, c.schedule_type,
               c.scheduled_start_at, c.proposing_duration_seconds, c.rating_duration_seconds,
               c.start_mode
        FROM public.chats c
        WHERE c.schedule_type IS NOT NULL
          AND c.is_active = TRUE
    LOOP
        v_in_window := is_chat_in_schedule_window(v_chat.id::INT);

        -- Case 1: Chat should be active but is paused -> RESUME
        IF v_in_window AND v_chat.schedule_paused THEN
            UPDATE public.chats
            SET schedule_paused = FALSE
            WHERE id = v_chat.id;

            SELECT r.* INTO v_current_round
            FROM public.rounds r
            JOIN public.cycles cy ON r.cycle_id = cy.id
            WHERE cy.chat_id = v_chat.id
              AND r.completed_at IS NULL
            ORDER BY r.created_at DESC
            LIMIT 1;

            IF v_current_round.id IS NOT NULL THEN
                IF v_current_round.phase = 'proposing' OR v_current_round.phase = 'waiting' THEN
                    v_phase_duration := COALESCE(v_chat.proposing_duration_seconds, 86400);
                ELSE
                    v_phase_duration := COALESCE(v_chat.rating_duration_seconds, 86400);
                END IF;

                IF v_current_round.phase_time_remaining_seconds IS NOT NULL
                   AND v_current_round.phase_time_remaining_seconds > 0 THEN
                    v_remaining_seconds := v_current_round.phase_time_remaining_seconds;
                ELSE
                    v_remaining_seconds := v_phase_duration;
                END IF;

                IF v_current_round.phase = 'waiting' THEN
                    RAISE NOTICE '[SCHEDULE RESUME] Round % stays in waiting phase (start_mode=%), facilitation rules apply',
                        v_current_round.id, v_chat.start_mode;
                ELSE
                    UPDATE public.rounds
                    SET phase_started_at = NOW(),
                        phase_ends_at = calculate_round_minute_end(v_remaining_seconds),
                        phase_time_remaining_seconds = NULL
                    WHERE id = v_current_round.id;

                    RAISE NOTICE '[SCHEDULE RESUME] Round % resumed % phase with % seconds remaining (aligned to minute)',
                        v_current_round.id, v_current_round.phase, v_remaining_seconds;
                END IF;
            END IF;

            -- The one summon per session. After the unpause + round restore, so
            -- anyone the ping wakes lands on a room that is genuinely running.
            PERFORM public.emit_room_open(v_chat.id);

            chat_id := v_chat.id;
            action := 'resumed';
            IF v_current_round.phase = 'waiting' THEN
                details := format('Chat resumed, round in waiting phase (start_mode=%s)', v_chat.start_mode);
            ELSE
                details := format('Chat resumed with %s seconds remaining (aligned to minute)', v_remaining_seconds);
            END IF;
            RETURN NEXT;

        -- Case 2: Chat should be paused but is active -> PAUSE
        ELSIF NOT v_in_window AND NOT v_chat.schedule_paused THEN
            IF v_chat.schedule_type = 'once' AND v_chat.scheduled_start_at > NOW() THEN
                CONTINUE;
            END IF;

            SELECT r.* INTO v_current_round
            FROM public.rounds r
            JOIN public.cycles cy ON r.cycle_id = cy.id
            WHERE cy.chat_id = v_chat.id
              AND r.completed_at IS NULL
            ORDER BY r.created_at DESC
            LIMIT 1;

            IF v_current_round.id IS NOT NULL
               AND v_current_round.phase IN ('proposing', 'rating')
               AND v_current_round.phase_ends_at IS NOT NULL THEN
                v_remaining_seconds := GREATEST(0,
                    EXTRACT(EPOCH FROM (v_current_round.phase_ends_at - NOW()))::INTEGER
                );

                UPDATE public.rounds
                SET phase_time_remaining_seconds = v_remaining_seconds
                WHERE id = v_current_round.id;

                RAISE NOTICE '[SCHEDULE PAUSE] Round % paused in % phase with % seconds remaining',
                    v_current_round.id, v_current_round.phase, v_remaining_seconds;
            ELSE
                v_remaining_seconds := NULL;
            END IF;

            UPDATE public.chats
            SET schedule_paused = TRUE
            WHERE id = v_chat.id;

            chat_id := v_chat.id;
            action := 'paused';
            details := format('Chat paused with %s seconds remaining', COALESCE(v_remaining_seconds::TEXT, 'N/A'));
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$function$;
