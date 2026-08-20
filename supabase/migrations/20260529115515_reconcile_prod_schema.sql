create sequence "public"."client_logs_id_seq";

drop policy "Users can skip in rounds they participate in" on "public"."round_skips";


  create table "public"."client_logs" (
    "id" bigint not null default nextval('public.client_logs_id_seq'::regclass),
    "user_id" uuid,
    "event" text not null,
    "message" text,
    "metadata" jsonb,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."client_logs" enable row level security;

alter sequence "public"."client_logs_id_seq" owned by "public"."client_logs"."id";

CREATE UNIQUE INDEX client_logs_pkey ON public.client_logs USING btree (id);

alter table "public"."client_logs" add constraint "client_logs_pkey" PRIMARY KEY using index "client_logs_pkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.check_moltbook_post_watchdog()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  last_post timestamptz;
  hours_since numeric;
BEGIN
  SELECT last_post_at INTO last_post FROM moltbook_agent_state WHERE id = 1;
  IF last_post IS NOT NULL THEN
    hours_since := EXTRACT(EPOCH FROM (now() - last_post)) / 3600;
    IF hours_since > 1 THEN
      RAISE LOG '[MOLTBOOK-WATCHDOG] Last post was % hours ago — restarting post-trigger chain', round(hours_since, 1);
      PERFORM schedule_moltbook_post_trigger(2);
    END IF;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.schedule_moltbook_post_trigger(minutes_from_now integer DEFAULT 32)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  target_time timestamptz := now() + (minutes_from_now || ' minutes')::interval;
  target_minute int := EXTRACT(MINUTE FROM target_time)::int;
  target_hour int := EXTRACT(HOUR FROM target_time)::int;
  target_day int := EXTRACT(DAY FROM target_time)::int;
  target_month int := EXTRACT(MONTH FROM target_time)::int;
  cron_expr text := target_minute || ' ' || target_hour || ' ' || target_day || ' ' || target_month || ' *';
  job_cmd text := E'SELECT net.http_post(\n'
    || E'  url := get_edge_function_url(''moltbook-agent''),\n'
    || E'  headers := get_cron_headers(),\n'
    || E'  body := ''{\"source\": \"post-trigger\"}''::jsonb\n'
    || E');';
BEGIN
  -- Remove old one-shot trigger if exists
  BEGIN
    PERFORM cron.unschedule('moltbook-post-trigger');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Schedule one-shot for exact date/time
  PERFORM cron.schedule('moltbook-post-trigger', cron_expr, job_cmd);
  
  RAISE LOG '[MOLTBOOK] Scheduled post trigger for % (cron: %)', target_time, cron_expr;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.auto_join_agents_on_chat_create()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_max_count INTEGER;
  v_persona RECORD;
  v_idx INTEGER := 0;
  v_display_name TEXT;
BEGIN
  IF NEW.enable_agents THEN
    v_max_count := GREATEST(NEW.proposing_agent_count, NEW.rating_agent_count);

    FOR v_persona IN
      SELECT ap.name, ap.display_name, ap.user_id
      FROM agent_personas ap
      WHERE ap.is_active = true
      ORDER BY ap.id ASC
    LOOP
      EXIT WHEN v_idx >= v_max_count;

      IF NEW.agent_configs IS NOT NULL
         AND v_idx < jsonb_array_length(NEW.agent_configs) THEN
        v_display_name := COALESCE(
          NEW.agent_configs -> v_idx ->> 'name',
          v_persona.display_name
        );
      ELSE
        v_display_name := v_persona.display_name;
      END IF;

      INSERT INTO participants (
        chat_id, user_id, display_name, is_host, is_authenticated, status, is_agent
      ) VALUES (
        NEW.id, v_persona.user_id, v_display_name, false, true, 'active', true
      ) ON CONFLICT DO NOTHING;

      v_idx := v_idx + 1;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_early_advance_on_rating()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round_id INTEGER;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 7;
    v_phase TEXT;
    v_chat_id INTEGER;
    v_corr UUID := gen_random_uuid();
    v_trigger_start TIMESTAMPTZ := clock_timestamp();
    v_pre_lock TIMESTAMPTZ;
    v_post_lock TIMESTAMPTZ;
    v_advanced BOOLEAN := FALSE;
BEGIN
    SELECT round_id INTO v_round_id FROM new_ratings LIMIT 1;
    IF v_round_id IS NULL THEN RETURN NULL; END IF;

    SELECT r.phase, c.chat_id INTO v_phase, v_chat_id
    FROM rounds r JOIN cycles c ON c.id = r.cycle_id WHERE r.id = v_round_id;

    IF v_phase IS DISTINCT FROM 'rating' THEN RETURN NULL; END IF;

    SELECT * INTO v_chat FROM chats WHERE id = v_chat_id;

    IF v_chat.rating_threshold_percent IS NULL
       AND v_chat.rating_threshold_count IS NULL THEN RETURN NULL; END IF;

    IF v_chat.start_mode = 'manual' THEN RETURN NULL; END IF;

    -- Time the lock acquisition. If 20 triggers serialize on this lock,
    -- the late ones see a multi-second wait; this number tells us so.
    v_pre_lock := clock_timestamp();
    PERFORM pg_advisory_xact_lock(v_round_id);
    v_post_lock := clock_timestamp();

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'rating_trigger.lock_wait',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (v_post_lock - v_pre_lock)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := v_round_id
    );

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase IS DISTINCT FROM 'rating' THEN RETURN NULL; END IF;

    v_total_participants := public.get_funded_participant_count(v_round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants WHERE chat_id = v_chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN RETURN NULL; END IF;

    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips rs JOIN participants p ON p.id = rs.participant_id
    WHERE rs.round_id = v_round_id AND p.status = 'active';

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
        v_advanced := TRUE;
    ELSE
        v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

        SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
        FROM (
            SELECT p.id,
                (SELECT COUNT(*) FROM grid_rankings gr
                 WHERE gr.proposition_id = p.id AND gr.round_id = v_round_id) AS cnt
            FROM propositions p WHERE p.round_id = v_round_id
        ) prop_ratings;

        IF v_min_ratings >= v_threshold THEN
            RAISE NOTICE '[EARLY ADVANCE] Per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
                v_min_ratings, v_threshold, v_active_raters, v_skip_count, v_round_id;
            PERFORM complete_round_with_winner(v_round_id);
            PERFORM apply_adaptive_duration(v_round_id);
            v_advanced := TRUE;
        END IF;
    END IF;

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := CASE WHEN v_advanced THEN 'rating_trigger.advanced'
                                  ELSE 'rating_trigger.bail' END,
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_trigger_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := v_round_id,
        p_payload        := jsonb_build_object(
            'min_ratings', v_min_ratings,
            'threshold', v_threshold,
            'active_raters', v_active_raters
        )
    );

    RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.complete_round_with_winner(p_round_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_round RECORD;
    v_winner_id BIGINT;
    v_max_score REAL;
    v_tied_count INTEGER;
    v_is_sole_winner BOOLEAN;
    v_corr UUID := gen_random_uuid();
    v_start TIMESTAMPTZ := clock_timestamp();
    v_stage_start TIMESTAMPTZ;
    v_chat_id BIGINT;
BEGIN
    SELECT * INTO v_round FROM rounds WHERE id = p_round_id;

    IF v_round IS NULL OR v_round.completed_at IS NOT NULL THEN
        SELECT cy.chat_id INTO v_chat_id
        FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
        WHERE r.id = p_round_id;
        PERFORM public.log_perf(
            p_correlation_id := v_corr,
            p_source         := 'db_func',
            p_action         := 'complete_round.bail_already_done',
            p_phase          := 'end',
            p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000)::INT,
            p_chat_id        := v_chat_id,
            p_round_id       := p_round_id
        );
        RETURN;
    END IF;

    SELECT cy.chat_id INTO v_chat_id
    FROM cycles cy
    WHERE cy.id = v_round.cycle_id;

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round',
        p_phase          := 'start',
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    PERFORM calculate_movda_scores_for_round(p_round_id);
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.movda',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    PERFORM store_round_ranks(p_round_id);
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.store_ranks',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    SELECT proposition_id, global_score INTO v_winner_id, v_max_score
    FROM proposition_global_scores
    WHERE round_id = p_round_id
    ORDER BY global_score DESC
    LIMIT 1;

    IF v_winner_id IS NULL THEN
        SELECT id INTO v_winner_id
        FROM propositions
        WHERE round_id = p_round_id
        ORDER BY created_at ASC
        LIMIT 1;
        v_is_sole_winner := TRUE;

        IF v_winner_id IS NOT NULL THEN
            INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
            VALUES (p_round_id, v_winner_id, 1, NULL);
        END IF;
    ELSE
        v_tied_count := count_tied_top_propositions(p_round_id);
        v_is_sole_winner := (v_tied_count = 1);

        INSERT INTO round_winners (round_id, proposition_id, rank, global_score)
        SELECT p_round_id, proposition_id,
               ROW_NUMBER() OVER (ORDER BY global_score DESC),
               global_score
        FROM proposition_global_scores
        WHERE round_id = p_round_id
        ORDER BY global_score DESC;
    END IF;
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.winner_insert',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    v_stage_start := clock_timestamp();
    UPDATE rounds
    SET winning_proposition_id = v_winner_id,
        is_sole_winner = v_is_sole_winner,
        completed_at = NOW()
    WHERE id = p_round_id;
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round.update_rounds_and_chain',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_stage_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'complete_round',
        p_phase          := 'end',
        p_duration_ms    := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000)::INT,
        p_chat_id        := v_chat_id,
        p_round_id       := p_round_id
    );

    RAISE NOTICE '[COMPLETE ROUND] Completed round % with winner %, sole_winner=% (tied within +/-% of top: %)',
        p_round_id, v_winner_id, v_is_sole_winner, convergence_tie_tolerance(), v_tied_count;
END;
$function$
;

-- count_round_skips return type changed integer -> bigint (prod is canonical).
-- CREATE OR REPLACE cannot change a function's return type (SQLSTATE 42P13),
-- so drop first. Safe: its only dependent (the round_skips policy) is dropped
-- at the top of this migration and recreated below.
DROP FUNCTION IF EXISTS public.count_round_skips(bigint);
CREATE OR REPLACE FUNCTION public.count_round_skips(p_round_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT count(*) FROM public.round_skips WHERE round_id = p_round_id;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_consensus(p_cycle_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_caller_id UUID;
  v_chat_id BIGINT;
  v_is_host BOOLEAN;
  v_latest_completed_cycle_id BIGINT;
  v_was_latest BOOLEAN := FALSE;
  v_new_round_id BIGINT;
  v_restarted BOOLEAN := FALSE;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT chat_id INTO v_chat_id
  FROM cycles
  WHERE id = p_cycle_id;

  IF v_chat_id IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  SELECT is_host INTO v_is_host
  FROM participants
  WHERE chat_id = v_chat_id
    AND user_id = v_caller_id
    AND status = 'active';

  IF v_is_host IS NOT TRUE THEN
    RAISE EXCEPTION 'Only the host can delete a consensus';
  END IF;

  SELECT id INTO v_latest_completed_cycle_id
  FROM cycles
  WHERE chat_id = v_chat_id
    AND completed_at IS NOT NULL
  ORDER BY completed_at DESC
  LIMIT 1;

  IF v_latest_completed_cycle_id IS NULL OR v_latest_completed_cycle_id != p_cycle_id THEN
    RAISE EXCEPTION 'Only the latest consensus can be deleted';
  END IF;

  v_was_latest := TRUE;

  UPDATE cycles
  SET winning_proposition_id = NULL,
      completed_at = NULL,
      task_result = NULL,
      category = NULL
  WHERE id = p_cycle_id;

  DELETE FROM rounds WHERE cycle_id = p_cycle_id;

  DELETE FROM rounds WHERE cycle_id IN (
    SELECT id FROM cycles
    WHERE chat_id = v_chat_id AND id > p_cycle_id AND completed_at IS NULL
  );
  DELETE FROM cycles
  WHERE chat_id = v_chat_id AND id > p_cycle_id AND completed_at IS NULL;

  v_new_round_id := create_round_for_cycle(p_cycle_id, v_chat_id, 1);
  v_restarted := TRUE;

  RETURN jsonb_build_object(
    'restarted', v_restarted,
    'new_round_id', v_new_round_id
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_chat_allowed_categories(p_chat_id bigint DEFAULT NULL::bigint)
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_prev_category TEXT;
BEGIN
  IF p_chat_id IS NOT NULL THEN
    SELECT category INTO v_prev_category
    FROM cycles
    WHERE chat_id = p_chat_id
      AND completed_at IS NOT NULL
    ORDER BY completed_at DESC
    LIMIT 1;
  ELSE
    SELECT category INTO v_prev_category
    FROM cycles
    WHERE completed_at IS NOT NULL
    ORDER BY completed_at DESC
    LIMIT 1;
  END IF;

  RETURN get_allowed_categories(v_prev_category);
END; $function$
;

CREATE OR REPLACE FUNCTION public.get_chat_by_code_translated(p_invite_code text, p_language_code text DEFAULT 'en'::text)
 RETURNS TABLE(id bigint, name text, initial_message text, description text, invite_code text, access_method text, require_auth boolean, require_approval boolean, creator_id uuid, creator_session_token uuid, host_display_name text, is_active boolean, is_official boolean, expires_at timestamp with time zone, last_activity_at timestamp with time zone, start_mode text, rating_start_mode text, auto_start_participant_count integer, proposing_duration_seconds integer, rating_duration_seconds integer, proposing_minimum integer, rating_minimum integer, proposing_threshold_percent integer, proposing_threshold_count integer, rating_threshold_percent integer, rating_threshold_count integer, enable_ai_participant boolean, ai_propositions_count integer, confirmation_rounds_required integer, show_previous_results boolean, propositions_per_user integer, created_at timestamp with time zone, adaptive_duration_enabled boolean, adaptive_adjustment_percent integer, min_phase_duration_seconds integer, max_phase_duration_seconds integer, schedule_type text, schedule_timezone text, scheduled_start_at timestamp with time zone, schedule_windows jsonb, visible_outside_schedule boolean, schedule_paused boolean, host_paused boolean, allow_skip_proposing boolean, allow_skip_rating boolean, initial_message_audio_url text, initial_message_video_url text, background_audio_url text, name_translated text, description_translated text, initial_message_translated text, translation_language text, translations_enabled boolean, translation_languages text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_resolved_invite_code TEXT;
BEGIN
    SELECT ch.invite_code INTO v_resolved_invite_code
    FROM personal_codes pc
    JOIN chats ch ON ch.id = pc.chat_id
    WHERE pc.code = UPPER(p_invite_code)
      AND pc.used_at IS NULL
      AND pc.revoked_at IS NULL
      AND ch.is_active = true
    LIMIT 1;
    IF v_resolved_invite_code IS NULL THEN
        v_resolved_invite_code := UPPER(p_invite_code);
    END IF;
    RETURN QUERY
    SELECT
        c.id, c.name, c.initial_message, c.description,
        c.invite_code::TEXT, c.access_method::TEXT, c.require_auth, c.require_approval,
        c.creator_id, c.creator_session_token, c.host_display_name,
        c.is_active, c.is_official, c.expires_at, c.last_activity_at,
        c.start_mode::TEXT, c.rating_start_mode::TEXT, c.auto_start_participant_count,
        c.proposing_duration_seconds, c.rating_duration_seconds,
        c.proposing_minimum, c.rating_minimum,
        c.proposing_threshold_percent, c.proposing_threshold_count,
        c.rating_threshold_percent, c.rating_threshold_count,
        c.enable_ai_participant, c.ai_propositions_count,
        c.confirmation_rounds_required, c.show_previous_results,
        c.propositions_per_user, c.created_at,
        c.adaptive_duration_enabled, c.adaptive_adjustment_percent,
        c.min_phase_duration_seconds, c.max_phase_duration_seconds,
        c.schedule_type::TEXT, c.schedule_timezone, c.scheduled_start_at,
        c.schedule_windows, c.visible_outside_schedule,
        c.schedule_paused, c.host_paused,
        c.allow_skip_proposing, c.allow_skip_rating,
        c.initial_message_audio_url, c.initial_message_video_url,
        c.background_audio_url,
        COALESCE(t_name.translated_text, t_name_en.translated_text, c.name) AS name_translated,
        COALESCE(t_desc.translated_text, t_desc_en.translated_text, c.description) AS description_translated,
        COALESCE(t_msg.translated_text, t_msg_en.translated_text, c.initial_message) AS initial_message_translated,
        CASE
            WHEN t_name.translated_text IS NOT NULL THEN p_language_code
            WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
            ELSE 'original'
        END AS translation_language,
        c.translations_enabled, c.translation_languages
    FROM chats c
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name' AND t_name.language_code = p_language_code
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name' AND t_name_en.language_code = 'en'
        AND p_language_code != 'en'
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description' AND t_desc.language_code = p_language_code
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description' AND t_desc_en.language_code = 'en'
        AND p_language_code != 'en'
    LEFT JOIN translations t_msg ON t_msg.chat_id = c.id
        AND t_msg.field_name = 'initial_message' AND t_msg.language_code = p_language_code
    LEFT JOIN translations t_msg_en ON t_msg_en.chat_id = c.id
        AND t_msg_en.field_name = 'initial_message' AND t_msg_en.language_code = 'en'
        AND p_language_code != 'en'
    WHERE (c.invite_code = v_resolved_invite_code OR c.id = (
        SELECT pc2.chat_id FROM personal_codes pc2
        WHERE pc2.code = UPPER(p_invite_code)
          AND pc2.used_at IS NULL
          AND pc2.revoked_at IS NULL
        LIMIT 1
    )) AND c.is_active = true;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_chat_detail_bootstrap(p_chat_id bigint, p_language_code text DEFAULT NULL::text, p_include_previous_results boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user_id UUID;
    v_chat_row chats%ROWTYPE;
    v_my_participant_id BIGINT;
    v_is_host BOOLEAN := FALSE;
    v_can_view BOOLEAN := FALSE;
    v_current_cycle_id BIGINT;
    v_current_round_id BIGINT;
    v_previous_round_id BIGINT;
    v_is_sole_winner BOOLEAN := FALSE;
    v_consecutive_sole_wins INT := 0;
    v_primary_winner_id BIGINT;

    v_chat JSONB;
    v_current_cycle JSONB := NULL;
    v_current_round JSONB := NULL;
    v_consensus_items JSONB := '[]'::JSONB;
    v_participants JSONB := '[]'::JSONB;
    v_my_participant JSONB := NULL;
    v_pending_join_requests JSONB := '[]'::JSONB;
    v_chat_credits JSONB := NULL;
    v_previous_winners JSONB := '[]'::JSONB;
    v_previous_round_results JSONB := '[]'::JSONB;
    v_propositions JSONB := '[]'::JSONB;
    v_my_propositions JSONB := '[]'::JSONB;
    v_rating_progress JSONB := jsonb_build_object(
        'rated', 0, 'total', 0, 'completed', FALSE, 'started', FALSE
    );
    v_skip_count INT := 0;
    v_has_skipped BOOLEAN := FALSE;
    v_rating_skip_count INT := 0;
    v_has_skipped_rating BOOLEAN := FALSE;
    v_affirmation_count INT := 0;
    v_has_affirmed BOOLEAN := FALSE;
    v_participants_who_rated JSONB := '[]'::JSONB;
    v_participants_who_skipped_proposing JSONB := '[]'::JSONB;
    v_participants_who_skipped_rating JSONB := '[]'::JSONB;
    v_participants_who_affirmed JSONB := '[]'::JSONB;
    v_min_ratings_per_prop INT := 0;
    v_my_current_round_rating_count INT := 0;
    v_is_my_participant_funded BOOLEAN := TRUE;
    v_funded_count INT;
    v_round_funding_count INT;
    v_my_funding_exists BOOLEAN;
    v_allowed_categories JSONB := '[]'::JSONB;

    k_max_ratings_per_user CONSTANT INT := 7;
BEGIN
    v_user_id := auth.uid();

    SELECT * INTO v_chat_row FROM chats WHERE id = p_chat_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT p.id, p.is_host
    INTO v_my_participant_id, v_is_host
    FROM participants p
    WHERE p.chat_id = p_chat_id
      AND p.user_id = v_user_id
    LIMIT 1;

    v_can_view := (v_my_participant_id IS NOT NULL)
                  OR (v_chat_row.access_method = 'public');
    v_is_host  := COALESCE(v_is_host, FALSE);

    IF NOT v_can_view THEN
        RETURN NULL;
    END IF;

    SELECT to_jsonb(c.*) ||
        jsonb_build_object(
            'name_translated',
            COALESCE(t_name.translated_text, t_name_en.translated_text, c.name),
            'description_translated',
            COALESCE(t_desc.translated_text, t_desc_en.translated_text, c.description),
            'initial_message_translated',
            COALESCE(t_msg.translated_text, t_msg_en.translated_text, c.initial_message),
            'translation_language',
            CASE
                WHEN p_language_code IS NULL THEN NULL
                WHEN t_name.translated_text IS NOT NULL THEN p_language_code
                WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
                ELSE 'original'
            END
        )
    INTO v_chat
    FROM chats c
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name'
        AND p_language_code IS NOT NULL
        AND t_name.language_code = p_language_code
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name'
        AND p_language_code IS NOT NULL
        AND p_language_code <> 'en'
        AND t_name_en.language_code = 'en'
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND p_language_code IS NOT NULL
        AND t_desc.language_code = p_language_code
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description'
        AND p_language_code IS NOT NULL
        AND p_language_code <> 'en'
        AND t_desc_en.language_code = 'en'
    LEFT JOIN translations t_msg ON t_msg.chat_id = c.id
        AND t_msg.field_name = 'initial_message'
        AND p_language_code IS NOT NULL
        AND t_msg.language_code = p_language_code
    LEFT JOIN translations t_msg_en ON t_msg_en.chat_id = c.id
        AND t_msg_en.field_name = 'initial_message'
        AND p_language_code IS NOT NULL
        AND p_language_code <> 'en'
        AND t_msg_en.language_code = 'en'
    WHERE c.id = p_chat_id;

    IF v_my_participant_id IS NOT NULL THEN
        SELECT to_jsonb(p.*)
        INTO v_my_participant
        FROM participants p
        WHERE p.id = v_my_participant_id;
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.display_name), '[]'::JSONB)
    INTO v_participants
    FROM participants p
    WHERE p.chat_id = p_chat_id AND p.status = 'active';

    IF v_is_host THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(jr.*) ORDER BY jr.created_at), '[]'::JSONB)
        INTO v_pending_join_requests
        FROM join_requests jr
        WHERE jr.chat_id = p_chat_id AND jr.status = 'pending';
    END IF;

    SELECT to_jsonb(cc.*)
    INTO v_chat_credits
    FROM chat_credits cc
    WHERE cc.chat_id = p_chat_id
    LIMIT 1;

    SELECT COALESCE(jsonb_agg(item ORDER BY (item->>'completed_at')::TIMESTAMPTZ), '[]'::JSONB)
    INTO v_consensus_items
    FROM (
        SELECT jsonb_build_object(
            'id', cy.id,
            'completed_at', cy.completed_at,
            'winning_proposition_id', cy.winning_proposition_id,
            'task_result', cy.task_result,
            'host_override', cy.host_override,
            'video_url', cy.video_url,
            'audio_url', cy.audio_url,
            'propositions', to_jsonb(p.*) || jsonb_build_object(
                'content_translated', tr.translated_text,
                'language_code',
                    CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code
                         ELSE NULL END
            )
        ) AS item
        FROM cycles cy
        JOIN propositions p ON p.id = cy.winning_proposition_id
        LEFT JOIN translations tr
            ON tr.proposition_id = p.id
            AND tr.field_name = 'content'
            AND p_language_code IS NOT NULL
            AND tr.language_code = p_language_code
        WHERE cy.chat_id = p_chat_id
          AND cy.winning_proposition_id IS NOT NULL
    ) consensus_rows;

    SELECT to_jsonb(cy.*), cy.id
    INTO v_current_cycle, v_current_cycle_id
    FROM cycles cy
    WHERE cy.chat_id = p_chat_id AND cy.completed_at IS NULL
    ORDER BY cy.created_at DESC
    LIMIT 1;

    IF v_current_cycle_id IS NOT NULL THEN
        SELECT to_jsonb(r.*), r.id
        INTO v_current_round, v_current_round_id
        FROM rounds r
        WHERE r.cycle_id = v_current_cycle_id AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC
        LIMIT 1;

        SELECT r.id, COALESCE(r.is_sole_winner, TRUE), r.winning_proposition_id
        INTO v_previous_round_id, v_is_sole_winner, v_primary_winner_id
        FROM rounds r
        WHERE r.cycle_id = v_current_cycle_id
          AND r.winning_proposition_id IS NOT NULL
        ORDER BY r.custom_id DESC
        LIMIT 1;

        IF v_previous_round_id IS NOT NULL THEN
            SELECT COALESCE(jsonb_agg(item ORDER BY (item->>'global_score')::NUMERIC DESC NULLS LAST), '[]'::JSONB)
            INTO v_previous_winners
            FROM (
                SELECT jsonb_build_object(
                    'id', rw.id,
                    'round_id', rw.round_id,
                    'proposition_id', rw.proposition_id,
                    'rank', rw.rank,
                    'global_score', rw.global_score,
                    'created_at', rw.created_at,
                    'propositions', jsonb_build_object('content', p.content),
                    'rounds', jsonb_build_object(
                        'audio_url', r.audio_url,
                        'video_url', r.video_url
                    ),
                    'content_translated', tr.translated_text,
                    'translation_language',
                        CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code
                             ELSE NULL END
                ) AS item
                FROM round_winners rw
                JOIN propositions p ON p.id = rw.proposition_id
                JOIN rounds r ON r.id = rw.round_id
                LEFT JOIN translations tr ON tr.proposition_id = rw.proposition_id
                    AND tr.field_name = 'content'
                    AND p_language_code IS NOT NULL
                    AND tr.language_code = p_language_code
                WHERE rw.round_id = v_previous_round_id
                  AND rw.rank = 1
            ) winners_rows;

            IF v_is_sole_winner AND v_primary_winner_id IS NOT NULL THEN
                SELECT public.count_consecutive_sole_wins(
                    v_current_cycle_id, v_primary_winner_id
                ) INTO v_consecutive_sole_wins;
            END IF;

            IF p_include_previous_results THEN
                SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ||
                    jsonb_build_object(
                        'proposition_global_scores',
                        COALESCE(
                            (SELECT jsonb_agg(jsonb_build_object('global_score', g.global_score))
                             FROM proposition_global_scores g
                             WHERE g.proposition_id = p.id),
                            '[]'::JSONB
                        ),
                        'content_translated', tr.translated_text,
                        'language_code',
                            CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code
                                 ELSE NULL END
                    )
                ), '[]'::JSONB)
                INTO v_previous_round_results
                FROM propositions p
                LEFT JOIN translations tr
                    ON tr.proposition_id = p.id
                    AND tr.field_name = 'content'
                    AND p_language_code IS NOT NULL
                    AND tr.language_code = p_language_code
                WHERE p.round_id = v_previous_round_id;
            END IF;
        END IF;

        IF v_current_round_id IS NOT NULL AND v_my_participant_id IS NOT NULL THEN
            SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ||
                jsonb_build_object(
                    'proposition_movda_ratings',
                    COALESCE(
                        (SELECT jsonb_agg(jsonb_build_object('rating', m.rating))
                         FROM proposition_movda_ratings m
                         WHERE m.proposition_id = p.id),
                        '[]'::JSONB
                    ),
                    'content_translated', tr.translated_text,
                    'language_code',
                        CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code
                             ELSE NULL END
                ) ORDER BY p.created_at), '[]'::JSONB)
            INTO v_propositions
            FROM propositions p
            LEFT JOIN translations tr
                ON tr.proposition_id = p.id
                AND tr.field_name = 'content'
                AND p_language_code IS NOT NULL
                AND tr.language_code = p_language_code
            WHERE p.round_id = v_current_round_id;

            SELECT COALESCE(jsonb_agg(to_jsonb(p.*)), '[]'::JSONB)
            INTO v_my_propositions
            FROM propositions p
            WHERE p.round_id = v_current_round_id
              AND p.participant_id = v_my_participant_id;

            DECLARE
                v_total INT;
                v_rated INT;
            BEGIN
                SELECT COUNT(*) INTO v_total
                FROM propositions p
                WHERE p.round_id = v_current_round_id
                  AND (p.participant_id IS NULL OR p.participant_id <> v_my_participant_id);

                SELECT COUNT(*) INTO v_rated
                FROM grid_rankings g
                WHERE g.round_id = v_current_round_id
                  AND g.participant_id = v_my_participant_id;

                v_my_current_round_rating_count := v_rated;
                v_rating_progress := jsonb_build_object(
                    'rated', v_rated,
                    'total', v_total,
                    'completed', (v_rated >= v_total AND v_total > 0),
                    'started', (v_rated > 0)
                );
            END;

            SELECT COUNT(*) INTO v_skip_count
            FROM round_skips s WHERE s.round_id = v_current_round_id;

            SELECT EXISTS (
                SELECT 1 FROM round_skips s
                WHERE s.round_id = v_current_round_id
                  AND s.participant_id = v_my_participant_id
            ) INTO v_has_skipped;

            SELECT COUNT(*) INTO v_rating_skip_count
            FROM rating_skips s WHERE s.round_id = v_current_round_id;

            SELECT EXISTS (
                SELECT 1 FROM rating_skips s
                WHERE s.round_id = v_current_round_id
                  AND s.participant_id = v_my_participant_id
            ) INTO v_has_skipped_rating;

            SELECT COUNT(*) INTO v_affirmation_count
            FROM affirmations a WHERE a.round_id = v_current_round_id;

            SELECT EXISTS (
                SELECT 1 FROM affirmations a
                WHERE a.round_id = v_current_round_id
                  AND a.participant_id = v_my_participant_id
            ) INTO v_has_affirmed;

            SELECT COALESCE(jsonb_agg(s.participant_id), '[]'::JSONB)
            INTO v_participants_who_skipped_proposing
            FROM round_skips s WHERE s.round_id = v_current_round_id;

            SELECT COALESCE(jsonb_agg(s.participant_id), '[]'::JSONB)
            INTO v_participants_who_skipped_rating
            FROM rating_skips s WHERE s.round_id = v_current_round_id;

            SELECT COALESCE(jsonb_agg(a.participant_id), '[]'::JSONB)
            INTO v_participants_who_affirmed
            FROM affirmations a WHERE a.round_id = v_current_round_id;

            DECLARE
                v_total_props INT;
            BEGIN
                SELECT COUNT(*) INTO v_total_props
                FROM propositions p WHERE p.round_id = v_current_round_id;

                IF v_total_props > 0 THEN
                    WITH authored AS (
                        SELECT participant_id, COUNT(*)::INT AS own_count
                        FROM propositions
                        WHERE round_id = v_current_round_id
                          AND participant_id IS NOT NULL
                        GROUP BY participant_id
                    ),
                    rated AS (
                        SELECT participant_id, COUNT(*)::INT AS rated_count
                        FROM grid_rankings
                        WHERE round_id = v_current_round_id
                          AND participant_id IS NOT NULL
                        GROUP BY participant_id
                    )
                    SELECT COALESCE(jsonb_agg(r.participant_id), '[]'::JSONB)
                    INTO v_participants_who_rated
                    FROM rated r
                    LEFT JOIN authored a ON a.participant_id = r.participant_id
                    WHERE LEAST(
                            v_total_props - COALESCE(a.own_count, 0),
                            k_max_ratings_per_user
                          ) > 0
                      AND r.rated_count >= LEAST(
                            v_total_props - COALESCE(a.own_count, 0),
                            k_max_ratings_per_user
                          );
                END IF;
            END;

            DECLARE
                v_min INT;
            BEGIN
                WITH counts AS (
                    SELECT p.id,
                           (SELECT COUNT(*)::INT FROM grid_rankings g
                             WHERE g.round_id = v_current_round_id
                               AND g.proposition_id = p.id) AS c
                    FROM propositions p
                    WHERE p.round_id = v_current_round_id
                )
                SELECT MIN(c) INTO v_min FROM counts;
                v_min_ratings_per_prop := COALESCE(v_min, 0);
            END;

            SELECT EXISTS (
                SELECT 1 FROM round_funding rf
                WHERE rf.round_id = v_current_round_id
                  AND rf.participant_id = v_my_participant_id
            ) INTO v_my_funding_exists;

            IF v_my_funding_exists THEN
                v_is_my_participant_funded := TRUE;
            ELSE
                SELECT public.get_funded_participant_count(v_current_round_id)
                INTO v_funded_count;
                v_is_my_participant_funded := COALESCE(v_funded_count, 0) = 0;
            END IF;
        END IF;

        SELECT COALESCE(
            (SELECT jsonb_agg(cat) FROM
                (SELECT unnest(public.get_chat_allowed_categories(p_chat_id)) AS cat) sub),
            '[]'::JSONB
        )
        INTO v_allowed_categories;
    END IF;

    RETURN jsonb_build_object(
        'chat', v_chat,
        'current_cycle', v_current_cycle,
        'current_round', v_current_round,
        'consensus_items', v_consensus_items,
        'participants', v_participants,
        'my_participant', v_my_participant,
        'pending_join_requests', v_pending_join_requests,
        'chat_credits', v_chat_credits,
        'previous_round_winners', v_previous_winners,
        'is_sole_winner', v_is_sole_winner,
        'consecutive_sole_wins', v_consecutive_sole_wins,
        'previous_round_id', v_previous_round_id,
        'primary_winner_id', v_primary_winner_id,
        'previous_round_results', v_previous_round_results,
        'propositions', v_propositions,
        'my_propositions', v_my_propositions,
        'rating_progress', v_rating_progress,
        'skip_count', v_skip_count,
        'has_skipped', v_has_skipped,
        'rating_skip_count', v_rating_skip_count,
        'has_skipped_rating', v_has_skipped_rating,
        'affirmation_count', v_affirmation_count,
        'has_affirmed', v_has_affirmed,
        'participants_who_rated', v_participants_who_rated,
        'participants_who_skipped_proposing', v_participants_who_skipped_proposing,
        'participants_who_skipped_rating', v_participants_who_skipped_rating,
        'participants_who_affirmed', v_participants_who_affirmed,
        'min_ratings_per_prop', v_min_ratings_per_prop,
        'my_current_round_rating_count', v_my_current_round_rating_count,
        'is_my_participant_funded', v_is_my_participant_funded,
        'allowed_categories', v_allowed_categories
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_least_rated_propositions(p_round_id bigint, p_participant_id bigint, p_count integer DEFAULT 2, p_exclude_ids bigint[] DEFAULT '{}'::bigint[])
 RETURNS TABLE(id bigint, round_id bigint, participant_id bigint, content text, carried_from_id bigint, created_at timestamp with time zone, rating_count bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t0 TIMESTAMPTZ := clock_timestamp();
  v_t1 TIMESTAMPTZ;
  v_pid INT := pg_backend_pid();
BEGIN
  RAISE LOG 'LRP_PROBE pid=% round=% stage=enter ms=0', v_pid, p_round_id;

  RETURN QUERY
    SELECT p.id, p.round_id, p.participant_id, p.content, p.carried_from_id,
           p.created_at, p.rating_count::BIGINT
    FROM public.propositions p
    WHERE p.round_id = p_round_id
      AND (p.participant_id IS NULL OR p.participant_id != p_participant_id)
      AND NOT (p.id = ANY(p_exclude_ids))
    ORDER BY p.rating_count ASC,
             hashtext(p_participant_id::TEXT || ':' || p.id::TEXT)
    LIMIT p_count;

  v_t1 := clock_timestamp();
  RAISE LOG 'LRP_PROBE pid=% round=% stage=done ms=%',
    v_pid, p_round_id,
    (EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000)::INT;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_chats_dashboard(p_user_id uuid, p_language_code text DEFAULT 'en'::text)
 RETURNS TABLE(id bigint, name text, initial_message text, description text, invite_code text, access_method text, require_auth boolean, require_approval boolean, creator_id uuid, creator_session_token uuid, host_display_name text, is_active boolean, is_official boolean, expires_at timestamp with time zone, last_activity_at timestamp with time zone, start_mode text, rating_start_mode text, auto_start_participant_count integer, proposing_duration_seconds integer, rating_duration_seconds integer, proposing_minimum integer, rating_minimum integer, proposing_threshold_percent integer, proposing_threshold_count integer, rating_threshold_percent integer, rating_threshold_count integer, enable_ai_participant boolean, ai_propositions_count integer, confirmation_rounds_required integer, show_previous_results boolean, propositions_per_user integer, created_at timestamp with time zone, adaptive_duration_enabled boolean, adaptive_adjustment_percent integer, min_phase_duration_seconds integer, max_phase_duration_seconds integer, schedule_type text, schedule_timezone text, scheduled_start_at timestamp with time zone, schedule_windows jsonb, visible_outside_schedule boolean, schedule_paused boolean, host_paused boolean, allow_skip_proposing boolean, allow_skip_rating boolean, initial_message_audio_url text, initial_message_video_url text, background_audio_url text, name_translated text, description_translated text, initial_message_translated text, translation_language text, translations_enabled boolean, translation_languages text[], participant_count bigint, current_cycle_id bigint, current_round_phase text, current_round_custom_id integer, current_round_phase_ends_at timestamp with time zone, current_round_phase_started_at timestamp with time zone, viewing_language_code text, has_participated boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        c.id, c.name, c.initial_message, c.description,
        c.invite_code::TEXT, c.access_method::TEXT, c.require_auth, c.require_approval,
        c.creator_id, c.creator_session_token, c.host_display_name,
        c.is_active, c.is_official, c.expires_at, c.last_activity_at,
        c.start_mode::TEXT, c.rating_start_mode::TEXT, c.auto_start_participant_count,
        c.proposing_duration_seconds, c.rating_duration_seconds,
        c.proposing_minimum, c.rating_minimum,
        c.proposing_threshold_percent, c.proposing_threshold_count,
        c.rating_threshold_percent, c.rating_threshold_count,
        c.enable_ai_participant, c.ai_propositions_count,
        c.confirmation_rounds_required, c.show_previous_results,
        c.propositions_per_user, c.created_at,
        c.adaptive_duration_enabled, c.adaptive_adjustment_percent,
        c.min_phase_duration_seconds, c.max_phase_duration_seconds,
        c.schedule_type::TEXT, c.schedule_timezone, c.scheduled_start_at,
        c.schedule_windows, c.visible_outside_schedule,
        c.schedule_paused, c.host_paused,
        c.allow_skip_proposing, c.allow_skip_rating,
        c.initial_message_audio_url, c.initial_message_video_url,
        c.background_audio_url,
        COALESCE(t_name.translated_text, t_name_en.translated_text, c.name) AS name_translated,
        COALESCE(t_desc.translated_text, t_desc_en.translated_text, c.description) AS description_translated,
        COALESCE(t_msg.translated_text, t_msg_en.translated_text, c.initial_message) AS initial_message_translated,
        CASE
            WHEN t_name.translated_text IS NOT NULL THEN COALESCE(p.viewing_language_code, p_language_code)
            WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
            ELSE 'original'
        END AS translation_language,
        c.translations_enabled, c.translation_languages,
        pc.cnt AS participant_count,
        ar.cycle_id AS current_cycle_id,
        ar.phase::TEXT AS current_round_phase,
        ar.custom_id AS current_round_custom_id,
        ar.phase_ends_at AS current_round_phase_ends_at,
        ar.phase_started_at AS current_round_phase_started_at,
        p.viewing_language_code,
        CASE
            WHEN ar.round_id IS NULL THEN TRUE
            WHEN ar.phase::TEXT = 'waiting' THEN TRUE
            WHEN ar.phase::TEXT = 'proposing' THEN (
                EXISTS (
                    SELECT 1 FROM propositions prop
                    WHERE prop.round_id = ar.round_id
                      AND prop.participant_id = p.id
                      AND prop.carried_from_id IS NULL
                )
                OR EXISTS (
                    SELECT 1 FROM round_skips rsk
                    WHERE rsk.round_id = ar.round_id
                      AND rsk.participant_id = p.id
                )
                OR EXISTS (
                    SELECT 1 FROM affirmations a
                    WHERE a.round_id = ar.round_id
                      AND a.participant_id = p.id
                )
            )
            WHEN ar.phase::TEXT = 'rating' THEN (
                (
                    SELECT COUNT(*) FROM grid_rankings gr
                    WHERE gr.round_id = ar.round_id
                      AND gr.participant_id = p.id
                ) >= (
                    SELECT COUNT(*) FROM propositions prop
                    WHERE prop.round_id = ar.round_id
                      AND (prop.participant_id IS NULL
                           OR prop.participant_id != p.id)
                )
                OR EXISTS (
                    SELECT 1 FROM rating_skips rsk
                    WHERE rsk.round_id = ar.round_id
                      AND rsk.participant_id = p.id
                )
            )
            ELSE TRUE
        END AS has_participated
    FROM chats c
    INNER JOIN participants p ON p.chat_id = c.id
        AND p.user_id = p_user_id AND p.status = 'active'
    LEFT JOIN translations t_name ON t_name.chat_id = c.id
        AND t_name.field_name = 'name'
        AND t_name.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id
        AND t_name_en.field_name = 'name' AND t_name_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id
        AND t_desc.field_name = 'description'
        AND t_desc.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id
        AND t_desc_en.field_name = 'description' AND t_desc_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN translations t_msg ON t_msg.chat_id = c.id
        AND t_msg.field_name = 'initial_message'
        AND t_msg.language_code = COALESCE(p.viewing_language_code, p_language_code)
    LEFT JOIN translations t_msg_en ON t_msg_en.chat_id = c.id
        AND t_msg_en.field_name = 'initial_message' AND t_msg_en.language_code = 'en'
        AND COALESCE(p.viewing_language_code, p_language_code) != 'en'
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt FROM participants p2
        WHERE p2.chat_id = c.id AND p2.status = 'active'
    ) pc ON true
    LEFT JOIN LATERAL (
        SELECT r.id AS round_id, r.cycle_id, r.phase, r.custom_id,
               r.phase_ends_at, r.phase_started_at
        FROM cycles cy
        JOIN rounds r ON r.cycle_id = cy.id
        WHERE cy.chat_id = c.id
          AND cy.completed_at IS NULL
          AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC LIMIT 1
    ) ar ON true
    WHERE c.is_active = true
    ORDER BY c.last_activity_at DESC NULLS LAST;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_propositions_for_rating(p_round_id bigint, p_participant_id bigint)
 RETURNS TABLE(id bigint, content text, participant_id bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Verify the caller is a participant in the chat that owns this round
  IF NOT EXISTS (
    SELECT 1 
    FROM participants p
    JOIN cycles c ON c.chat_id = p.chat_id
    JOIN rounds r ON r.cycle_id = c.id
    WHERE r.id = p_round_id
      AND p.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a participant in this chat';
  END IF;

  -- Return all propositions for the round except the caller's own
  RETURN QUERY
    SELECT pr.id, pr.content, pr.participant_id
    FROM propositions pr
    WHERE pr.round_id = p_round_id
      AND pr.participant_id != p_participant_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_round_state_for_participant(p_chat_id bigint, p_participant_id bigint)
 RETURNS TABLE(cycle_id bigint, round_id bigint, phase text, phase_ends_at timestamp with time zone, custom_id integer, has_submitted_proposition boolean, has_submitted_ratings boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cycle_id bigint;
  v_round_id bigint;
  v_phase text;
  v_phase_ends_at timestamptz;
  v_custom_id int;
  v_has_proposition boolean;
  v_has_ratings boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM participants p
    WHERE p.id = p_participant_id
      AND p.chat_id = p_chat_id
      AND p.user_id = auth.uid()
      AND p.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Not an active participant in this chat';
  END IF;

  SELECT c.id INTO v_cycle_id
  FROM cycles c
  WHERE c.chat_id = p_chat_id
  ORDER BY c.created_at DESC
  LIMIT 1;

  IF v_cycle_id IS NULL THEN
    RETURN;
  END IF;

  SELECT r.id, r.phase, r.phase_ends_at, r.custom_id
  INTO v_round_id, v_phase, v_phase_ends_at, v_custom_id
  FROM rounds r
  WHERE r.cycle_id = v_cycle_id
  ORDER BY r.custom_id DESC
  LIMIT 1;

  IF v_round_id IS NULL THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM propositions pr
    WHERE pr.round_id = v_round_id
      AND pr.participant_id = p_participant_id
      AND pr.carried_from_id IS NULL
  ) INTO v_has_proposition;

  SELECT EXISTS (
    SELECT 1 FROM grid_rankings gr
    WHERE gr.round_id = v_round_id
      AND gr.participant_id = p_participant_id
  ) INTO v_has_ratings;

  cycle_id := v_cycle_id;
  round_id := v_round_id;
  phase := v_phase;
  phase_ends_at := v_phase_ends_at;
  custom_id := v_custom_id;
  has_submitted_proposition := v_has_proposition;
  has_submitted_ratings := v_has_ratings;
  RETURN NEXT;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.host_force_consensus(p_chat_id bigint, p_content text, p_category text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_caller_id UUID;
  v_is_host BOOLEAN;
  v_participant_id BIGINT;
  v_current_cycle_id BIGINT;
  v_current_round_id BIGINT;
  v_proposition_id BIGINT;
  v_allowed TEXT[];
  v_is_service_role BOOLEAN;
  v_effective_category TEXT;
BEGIN
  v_is_service_role := current_setting('role', true) = 'service_role'
                    OR current_setting('request.jwt.claim.role', true) = 'service_role';

  IF v_is_service_role THEN
    SELECT id INTO v_participant_id
    FROM participants
    WHERE chat_id = p_chat_id AND status = 'active'
    ORDER BY is_host DESC
    LIMIT 1;

    IF v_participant_id IS NULL THEN
      RAISE EXCEPTION 'No active participants in chat';
    END IF;
  ELSE
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT id, is_host INTO v_participant_id, v_is_host
    FROM participants
    WHERE chat_id = p_chat_id
      AND user_id = v_caller_id
      AND status = 'active';

    IF v_is_host IS NOT TRUE THEN
      RAISE EXCEPTION 'Only the host can force a consensus';
    END IF;
  END IF;

  IF p_content IS NULL OR TRIM(p_content) = '' THEN
    RAISE EXCEPTION 'Content cannot be empty';
  END IF;

  v_allowed := get_chat_allowed_categories(p_chat_id);

  IF p_category IS NOT NULL THEN
    IF NOT (p_category = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'Category "%" not allowed. Allowed: %', p_category, v_allowed;
    END IF;
    v_effective_category := p_category;
  ELSE
    IF array_length(v_allowed, 1) = 1 THEN
      v_effective_category := v_allowed[1];
    ELSE
      v_effective_category := NULL;
    END IF;
  END IF;

  SELECT id INTO v_current_cycle_id
  FROM cycles
  WHERE chat_id = p_chat_id
    AND completed_at IS NULL
  ORDER BY id DESC
  LIMIT 1;

  IF v_current_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No active cycle found for this chat';
  END IF;

  SELECT id INTO v_current_round_id
  FROM rounds
  WHERE cycle_id = v_current_cycle_id
  ORDER BY id DESC
  LIMIT 1;

  IF v_current_round_id IS NULL THEN
    RAISE EXCEPTION 'No active round found for this cycle';
  END IF;

  INSERT INTO propositions (round_id, participant_id, content, category)
  VALUES (v_current_round_id, v_participant_id, TRIM(p_content), v_effective_category)
  RETURNING id INTO v_proposition_id;

  -- Mark ALL rounds in this cycle as completed so timer queries don't pick them up
  UPDATE rounds
  SET completed_at = NOW()
  WHERE cycle_id = v_current_cycle_id AND completed_at IS NULL;

  UPDATE cycles
  SET winning_proposition_id = v_proposition_id,
      completed_at = NOW(),
      host_override = TRUE,
      category = v_effective_category
  WHERE id = v_current_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_current_cycle_id,
    'proposition_id', v_proposition_id,
    'category', v_effective_category
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.host_resume_chat(p_chat_id bigint, p_correlation_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_current_round       record;
  v_is_host             boolean;
  v_schedule_paused     boolean;
  v_found               boolean;
  v_chat                record;
  v_existing_cycle_id   INTEGER;
  v_participant_count   INTEGER;
  v_new_cycle_id        BIGINT;
  v_new_round_id        BIGINT;
  v_started_at          timestamptz := clock_timestamp();
  v_corr                uuid := COALESCE(p_correlation_id, gen_random_uuid());
BEGIN
  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'host_resume_chat',
    p_phase          := 'start',
    p_chat_id        := p_chat_id
  );

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

  IF NOT (SELECT host_paused FROM public.chats WHERE id = p_chat_id) THEN
    RAISE NOTICE 'Chat % is not paused by host', p_chat_id;
    PERFORM public.log_perf(
      p_correlation_id := v_corr,
      p_source         := 'db_func',
      p_action         := 'host_resume_chat',
      p_phase          := 'end',
      p_duration_ms    := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started_at)::int,
      p_chat_id        := p_chat_id,
      p_payload        := '{"noop": true, "reason": "not_paused"}'::JSONB
    );
    RETURN;
  END IF;

  UPDATE public.chats SET host_paused = false WHERE id = p_chat_id;

  SELECT schedule_paused INTO v_schedule_paused
  FROM public.chats WHERE id = p_chat_id;

  IF NOT v_schedule_paused THEN
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

    IF v_found AND v_current_round.phase_time_remaining_seconds > 0 THEN
      UPDATE public.rounds
      SET phase_ends_at = calculate_round_minute_end(phase_time_remaining_seconds),
          phase_time_remaining_seconds = NULL
      WHERE id = v_current_round.id;

      RAISE NOTICE '[HOST RESUME] Round % resumed with % seconds (aligned to minute)',
        v_current_round.id, v_current_round.phase_time_remaining_seconds;
    END IF;

    SELECT id INTO v_existing_cycle_id
    FROM cycles
    WHERE chat_id = p_chat_id
    LIMIT 1;

    IF v_existing_cycle_id IS NULL THEN
      SELECT
        c.start_mode,
        c.auto_start_participant_count
      INTO v_chat
      FROM chats c
      WHERE c.id = p_chat_id;

      IF v_chat.start_mode = 'auto' THEN
        SELECT COUNT(*) INTO v_participant_count
        FROM participants
        WHERE chat_id = p_chat_id
          AND status = 'active';

        IF v_participant_count >= v_chat.auto_start_participant_count THEN
          INSERT INTO cycles (chat_id)
          VALUES (p_chat_id)
          RETURNING id INTO v_new_cycle_id;

          v_new_round_id := create_round_for_cycle(v_new_cycle_id, p_chat_id, 1);

          UPDATE chats
          SET last_activity_at = NOW()
          WHERE id = p_chat_id;

          RAISE NOTICE '[HOST RESUME] Auto-start retry on resume: cycle % round % for chat %',
            v_new_cycle_id, v_new_round_id, p_chat_id;
        END IF;
      END IF;
    END IF;
  ELSE
    RAISE NOTICE '[HOST RESUME] Chat % resumed by host but still paused by schedule', p_chat_id;
  END IF;

  RAISE NOTICE '[HOST RESUME] Chat % resumed by host', p_chat_id;

  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'host_resume_chat',
    p_phase          := 'end',
    p_duration_ms    := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started_at)::int,
    p_chat_id        := p_chat_id
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.log_perf(p_correlation_id uuid, p_source text, p_action text, p_phase text DEFAULT NULL::text, p_duration_ms integer DEFAULT NULL::integer, p_chat_id bigint DEFAULT NULL::bigint, p_round_id bigint DEFAULT NULL::bigint, p_user_id uuid DEFAULT NULL::uuid, p_device_id text DEFAULT NULL::text, p_payload jsonb DEFAULT NULL::jsonb, p_error text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO public.perf_logs (
        correlation_id, source, action, phase, duration_ms,
        chat_id, round_id, user_id, device_id, payload, error
    ) VALUES (
        p_correlation_id, p_source, p_action, p_phase, p_duration_ms,
        p_chat_id, p_round_id, COALESCE(p_user_id, auth.uid()), p_device_id, p_payload, p_error
    );
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.on_round_winner_set()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    consecutive_sole_wins INTEGER := 0;
    required_wins INTEGER;
    v_cycle_id BIGINT;
    v_chat_id BIGINT;
    current_custom_id INTEGER;
    check_custom_id INTEGER;
    prev_winner_id BIGINT;
    prev_is_sole BOOLEAN;
    new_round_id BIGINT;
    current_root_id BIGINT;
    prev_root_id BIGINT;
    winner_record RECORD;
    root_prop_id BIGINT;
    new_prop_id BIGINT;
    v_winner_category TEXT;
    v_agents_enabled BOOLEAN;
    v_human_propositions INTEGER;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    v_cycle_id := NEW.cycle_id;

    -- Get chat_id, confirmation_rounds_required, and enable_agents from chat settings
    SELECT c.chat_id, ch.confirmation_rounds_required, ch.enable_agents
    INTO v_chat_id, required_wins, v_agents_enabled
    FROM cycles c
    JOIN chats ch ON ch.id = c.chat_id
    WHERE c.id = v_cycle_id;

    -- Default to 2 if not set
    IF required_wins IS NULL THEN
        required_wins := 2;
    END IF;

    -- Mark current round as completed
    NEW.completed_at := NOW();

    -- Get the ROOT proposition ID for the current winner
    current_root_id := get_root_proposition_id(NEW.winning_proposition_id);

    -- CRITICAL: Only count this win toward consensus if it's a SOLE win (no ties)
    IF NEW.is_sole_winner = TRUE THEN
        consecutive_sole_wins := 1;

        -- Walk backwards through previous rounds to count consecutive SOLE wins
        current_custom_id := NEW.custom_id;
        check_custom_id := current_custom_id - 1;

        WHILE check_custom_id >= 1 LOOP
            SELECT winning_proposition_id, is_sole_winner
            INTO prev_winner_id, prev_is_sole
            FROM rounds
            WHERE cycle_id = v_cycle_id
            AND custom_id = check_custom_id;

            -- Get the ROOT proposition ID for the previous winner
            IF prev_winner_id IS NOT NULL THEN
                prev_root_id := get_root_proposition_id(prev_winner_id);
            ELSE
                prev_root_id := NULL;
            END IF;

            -- Count only if: same ROOT winner AND was a sole win (not tied)
            IF prev_root_id IS NOT NULL
               AND prev_root_id = current_root_id
               AND prev_is_sole = TRUE THEN
                consecutive_sole_wins := consecutive_sole_wins + 1;
                check_custom_id := check_custom_id - 1;
            ELSE
                -- Chain broken (different winner OR was a tie)
                EXIT;
            END IF;
        END LOOP;

        RAISE NOTICE '[ROUND WINNER] Proposition % (root: %) has % consecutive sole win(s), need %',
            NEW.winning_proposition_id, current_root_id, consecutive_sole_wins, required_wins;
    ELSE
        -- Tied win - does not count toward consensus
        RAISE NOTICE '[ROUND WINNER] Round % ended in tie (is_sole_winner=FALSE), does not count toward consensus',
            NEW.id;
    END IF;

    -- Check if we've reached the required consecutive SOLE wins
    IF consecutive_sole_wins >= required_wins THEN
        -- Consensus reached! Complete the cycle
        RAISE NOTICE '[ROUND WINNER] CONSENSUS REACHED! Completing cycle % with winner % (root: %)',
            v_cycle_id, NEW.winning_proposition_id, current_root_id;

        -- Get the winning proposition's category for denormalization onto cycle
        SELECT category INTO v_winner_category
        FROM propositions
        WHERE id = NEW.winning_proposition_id;

        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW(),
            category = v_winner_category
        WHERE id = v_cycle_id;
    ELSE
        -- Need more rounds, create next one using the helper function
        -- This properly handles auto-start conditions (creates in proposing phase
        -- if auto mode + enough participants, instead of always waiting)
        new_round_id := create_round_for_cycle(v_cycle_id, v_chat_id, get_next_custom_id(v_cycle_id));

        RAISE NOTICE '[ROUND WINNER] Created next round % for cycle %', new_round_id, v_cycle_id;

        -- CARRY FORWARD: Copy all winning propositions to the new round
        -- This enables consensus tracking across rounds (same root ID)
        FOR winner_record IN
            SELECT rw.proposition_id, p.content, p.participant_id, p.carried_from_id, p.category
            FROM round_winners rw
            JOIN propositions p ON rw.proposition_id = p.id
            WHERE rw.round_id = NEW.id AND rw.rank = 1
        LOOP
            -- Determine the root proposition ID
            -- If already carried, use its carried_from_id; otherwise use the proposition itself
            root_prop_id := COALESCE(winner_record.carried_from_id, winner_record.proposition_id);

            -- Insert the carried-forward proposition (including category)
            INSERT INTO propositions (round_id, participant_id, content, carried_from_id, category)
            VALUES (new_round_id, winner_record.participant_id, winner_record.content, root_prop_id, winner_record.category)
            RETURNING id INTO new_prop_id;

            RAISE NOTICE '[CARRY FORWARD] Copied proposition "%" to round % (root: %, new_id: %, category: %)',
                LEFT(winner_record.content, 30), new_round_id, root_prop_id, new_prop_id, winner_record.category;

            -- COPY TRANSLATIONS from the root proposition to the new carried proposition
            -- This ensures duplicate detection works correctly
            INSERT INTO translations (proposition_id, entity_type, field_name, language_code, translated_text)
            SELECT
                new_prop_id,
                t.entity_type,
                t.field_name,
                t.language_code,
                t.translated_text
            FROM translations t
            WHERE t.proposition_id = root_prop_id
              AND t.field_name = 'content';

            RAISE NOTICE '[CARRY FORWARD] Copied translations for proposition % from root %',
                new_prop_id, root_prop_id;
        END LOOP;
    END IF;

    -- =========================================================================
    -- AUTO-PAUSE SAFETY: Prevent runaway agent-only rounds
    -- =========================================================================
    IF v_agents_enabled THEN
        SELECT COUNT(*) INTO v_human_propositions
        FROM (
            -- Humans who submitted a new proposition
            SELECT p.id
            FROM propositions p
            JOIN participants pt ON pt.id = p.participant_id
            WHERE p.round_id = NEW.id
              AND p.carried_from_id IS NULL
              AND pt.is_agent = false
            UNION ALL
            -- Humans who explicitly skipped (still counts as active participation)
            SELECT rs.id
            FROM round_skips rs
            JOIN participants pt ON pt.id = rs.participant_id
            WHERE rs.round_id = NEW.id
              AND pt.is_agent = false
        ) human_activity;

        IF v_human_propositions = 0 THEN
            UPDATE chats SET host_paused = true WHERE id = v_chat_id;
            RAISE NOTICE '[AUTO PAUSE] Chat % auto-paused: round % completed with no human propositions',
                v_chat_id, NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.recompute_round_participation_percent(p_round_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_phase           TEXT;
  v_chat_id         BIGINT;
  v_total           INT;
  v_done            INT;
  v_skip_count      INT;
  v_active_raters   INT;
  v_threshold       INT;
  v_min_ratings     INT;
  v_percent         INT;
BEGIN
  SELECT r.phase, cy.chat_id INTO v_phase, v_chat_id
  FROM public.rounds r
  JOIN public.cycles cy ON cy.id = r.cycle_id
  WHERE r.id = p_round_id;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.participants
  WHERE chat_id = v_chat_id AND status = 'active';

  IF v_phase = 'proposing' THEN
    SELECT COUNT(DISTINCT pid) INTO v_done FROM (
      SELECT participant_id AS pid FROM public.propositions
        WHERE round_id = p_round_id
          AND carried_from_id IS NULL
          AND participant_id IS NOT NULL
      UNION
      SELECT participant_id FROM public.round_skips WHERE round_id = p_round_id
      UNION
      SELECT participant_id FROM public.affirmations WHERE round_id = p_round_id
    ) acted;

    v_percent := CASE WHEN v_total = 0 THEN 0
                      ELSE LEAST(100, (v_done * 100 / v_total)) END;

  ELSIF v_phase = 'rating' THEN
    SELECT COUNT(*) INTO v_skip_count
    FROM public.rating_skips rs
    JOIN public.participants p ON p.id = rs.participant_id
    WHERE rs.round_id = p_round_id AND p.status = 'active';

    v_active_raters := v_total - v_skip_count;
    IF v_active_raters <= 0 THEN
      v_percent := 100;
    ELSE
      v_threshold := LEAST(10, GREATEST(v_active_raters - 1, 1));
      SELECT COALESCE(MIN(p.rating_count), 0) INTO v_min_ratings
      FROM public.propositions p
      WHERE p.round_id = p_round_id;
      v_percent := LEAST(100, (v_min_ratings * 100 / v_threshold));
    END IF;

  ELSE
    v_percent := NULL;
  END IF;

  UPDATE public.rounds
  SET participation_percent = v_percent
  WHERE id = p_round_id
    AND participation_percent IS DISTINCT FROM v_percent;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.skip_rating_with_cleanup(p_round_id bigint, p_participant_id bigint, p_correlation_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_user_id              uuid;
  v_round_phase          text;
  v_skip_count           integer;
  v_total_participants   integer;
  v_rating_minimum       integer;
  v_chat_id              bigint;
  v_allow_skip           boolean;
  v_started_at           timestamptz := clock_timestamp();
  v_corr                 uuid := COALESCE(p_correlation_id, gen_random_uuid());
BEGIN
  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'skip_rating_with_cleanup',
    p_phase          := 'start',
    p_round_id       := p_round_id
  );

  SELECT user_id INTO v_user_id
  FROM participants WHERE id = p_participant_id;

  IF v_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Participant does not belong to current user';
  END IF;

  SELECT r.phase, c.chat_id INTO v_round_phase, v_chat_id
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE r.id = p_round_id;

  IF v_round_phase IS DISTINCT FROM 'rating' THEN
    RAISE EXCEPTION 'Round is not in rating phase';
  END IF;

  SELECT allow_skip_rating INTO v_allow_skip
  FROM chats WHERE id = v_chat_id;

  IF v_allow_skip IS NOT TRUE THEN
    RAISE EXCEPTION 'Skipping rating is not allowed in this chat';
  END IF;

  IF EXISTS (
    SELECT 1 FROM rating_skips
    WHERE round_id = p_round_id AND participant_id = p_participant_id
  ) THEN
    RAISE EXCEPTION 'Already skipped this round';
  END IF;

  SELECT COUNT(*) INTO v_skip_count
  FROM rating_skips rs
  JOIN participants p ON p.id = rs.participant_id
  WHERE rs.round_id = p_round_id
    AND p.status = 'active';

  SELECT COUNT(*) INTO v_total_participants FROM participants WHERE chat_id = v_chat_id AND status = 'active';
  SELECT rating_minimum INTO v_rating_minimum FROM chats WHERE id = v_chat_id;
  v_rating_minimum := COALESCE(v_rating_minimum, 2);

  IF v_skip_count >= (v_total_participants - v_rating_minimum) THEN
    RAISE EXCEPTION 'Rating skip quota exceeded';
  END IF;

  DELETE FROM grid_rankings
  WHERE participant_id = p_participant_id
    AND proposition_id IN (
      SELECT id FROM propositions WHERE round_id = p_round_id
    );

  INSERT INTO rating_skips (round_id, participant_id)
  VALUES (p_round_id, p_participant_id);

  PERFORM public.log_perf(
    p_correlation_id := v_corr,
    p_source         := 'db_func',
    p_action         := 'skip_rating_with_cleanup',
    p_phase          := 'end',
    p_duration_ms    := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started_at)::int,
    p_chat_id        := v_chat_id,
    p_round_id       := p_round_id
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trigger_translate_proposition_on_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_service_key TEXT;
  v_url TEXT;
  v_body JSONB;
  v_request_id BIGINT;
  v_translations_enabled BOOLEAN;
  v_translation_languages TEXT[];
BEGIN
  IF OLD.content IS NOT DISTINCT FROM NEW.content THEN
    RETURN NEW;
  END IF;

  DELETE FROM public.translations
  WHERE proposition_id = NEW.id
    AND field_name = 'content';

  IF NEW.carried_from_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.content IS NULL OR NEW.content = '' THEN
    RETURN NEW;
  END IF;

  SELECT c.translations_enabled, c.translation_languages
  INTO v_translations_enabled, v_translation_languages
  FROM public.rounds r
  INNER JOIN public.cycles cy ON cy.id = r.cycle_id
  INNER JOIN public.chats c ON c.id = cy.chat_id
  WHERE r.id = NEW.round_id;

  IF NOT COALESCE(v_translations_enabled, FALSE) THEN
    RAISE LOG 'Translation skipped for proposition % update: chat translations_enabled = false', NEW.id;
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_function_service_key';

  IF v_service_key IS NULL OR v_service_key = 'placeholder-set-via-dashboard' THEN
    RAISE WARNING 'Translation skipped: edge_function_service_key not configured in vault';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('translate');

  v_body := jsonb_build_object(
    'proposition_id', NEW.id,
    'text', NEW.content,
    'entity_type', 'proposition',
    'field_name', 'content',
    'languages', to_jsonb(v_translation_languages)
  );

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := v_body,
    timeout_milliseconds := 60000
  ) INTO v_request_id;

  RAISE LOG 'Translation requested for proposition % update (request_id: %, languages: %)',
    NEW.id, v_request_id, v_translation_languages;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Translation trigger error for proposition % on update: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$
;

grant delete on table "public"."client_logs" to "anon";

grant insert on table "public"."client_logs" to "anon";

grant references on table "public"."client_logs" to "anon";

grant select on table "public"."client_logs" to "anon";

grant trigger on table "public"."client_logs" to "anon";

grant truncate on table "public"."client_logs" to "anon";

grant update on table "public"."client_logs" to "anon";

grant delete on table "public"."client_logs" to "authenticated";

grant insert on table "public"."client_logs" to "authenticated";

grant references on table "public"."client_logs" to "authenticated";

grant select on table "public"."client_logs" to "authenticated";

grant trigger on table "public"."client_logs" to "authenticated";

grant truncate on table "public"."client_logs" to "authenticated";

grant update on table "public"."client_logs" to "authenticated";

grant delete on table "public"."client_logs" to "service_role";

grant insert on table "public"."client_logs" to "service_role";

grant references on table "public"."client_logs" to "service_role";

grant select on table "public"."client_logs" to "service_role";

grant trigger on table "public"."client_logs" to "service_role";

grant truncate on table "public"."client_logs" to "service_role";

grant update on table "public"."client_logs" to "service_role";


  create policy "Anyone can insert client_logs"
  on "public"."client_logs"
  as permissive
  for insert
  to public
with check (true);



  create policy "Service role can read client_logs"
  on "public"."client_logs"
  as permissive
  for select
  to public
using (true);



  create policy "Participants can update own grid_rankings"
  on "public"."grid_rankings"
  as permissive
  for update
  to public
using (((current_setting('role'::text, true) = 'service_role'::text) OR (public.owns_participant(participant_id) AND public.participant_can_access_round(participant_id, round_id))))
with check (((current_setting('role'::text, true) = 'service_role'::text) OR (public.owns_participant(participant_id) AND public.participant_can_access_round(participant_id, round_id))));



  create policy "Users can skip in rounds they participate in"
  on "public"."round_skips"
  as permissive
  for insert
  to public
with check (((EXISTS ( SELECT 1
   FROM ((public.chats ch
     JOIN public.cycles c ON ((c.chat_id = ch.id)))
     JOIN public.rounds r ON ((r.cycle_id = c.id)))
  WHERE ((r.id = round_skips.round_id) AND (ch.allow_skip_proposing = true)))) AND (participant_id IN ( SELECT participants.id
   FROM public.participants
  WHERE (participants.user_id = auth.uid()))) AND (EXISTS ( SELECT 1
   FROM public.rounds
  WHERE ((rounds.id = round_skips.round_id) AND (rounds.phase = 'proposing'::text)))) AND (NOT (EXISTS ( SELECT 1
   FROM public.propositions
  WHERE ((propositions.round_id = round_skips.round_id) AND (propositions.participant_id = round_skips.participant_id) AND (propositions.carried_from_id IS NULL))))) AND (public.count_round_skips(round_id) < (( SELECT count(*) AS count
   FROM ((public.participants p
     JOIN public.cycles c ON ((p.chat_id = c.chat_id)))
     JOIN public.rounds r ON ((r.cycle_id = c.id)))
  WHERE ((r.id = round_skips.round_id) AND (p.status = 'active'::text))) - ( SELECT ch.proposing_minimum
   FROM ((public.chats ch
     JOIN public.cycles c ON ((c.chat_id = ch.id)))
     JOIN public.rounds r ON ((r.cycle_id = c.id)))
  WHERE (r.id = round_skips.round_id))))));



