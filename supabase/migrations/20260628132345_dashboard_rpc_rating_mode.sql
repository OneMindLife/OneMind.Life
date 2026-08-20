-- get_my_chats_dashboard did not return rating_mode / match_objective, so the
-- Home dashboard's Chat snapshot (widget.chat) always fell back to 'grid' for
-- matches chats — which made the round-results screen render the grid view for
-- pairwise chats wherever the dashboard snapshot (rather than the bootstrap)
-- was the source. Add the two columns so widget.chat.ratingMode is correct
-- everywhere. Adding columns to a RETURNS TABLE requires DROP + CREATE; grants
-- (PUBLIC/anon/authenticated/service_role) are restored at the end.
DROP FUNCTION IF EXISTS public.get_my_chats_dashboard(uuid, text);

CREATE OR REPLACE FUNCTION public.get_my_chats_dashboard(p_user_id uuid, p_language_code text DEFAULT 'en'::text)
 RETURNS TABLE(id bigint, name text, initial_message text, description text, invite_code text, access_method text, require_auth boolean, require_approval boolean, creator_id uuid, creator_session_token uuid, host_display_name text, is_active boolean, is_official boolean, expires_at timestamp with time zone, last_activity_at timestamp with time zone, start_mode text, rating_start_mode text, auto_start_participant_count integer, proposing_duration_seconds integer, rating_duration_seconds integer, proposing_minimum integer, rating_minimum integer, proposing_threshold_percent integer, proposing_threshold_count integer, rating_threshold_percent integer, rating_threshold_count integer, enable_ai_participant boolean, ai_propositions_count integer, confirmation_rounds_required integer, show_previous_results boolean, propositions_per_user integer, created_at timestamp with time zone, adaptive_duration_enabled boolean, adaptive_adjustment_percent integer, min_phase_duration_seconds integer, max_phase_duration_seconds integer, schedule_type text, schedule_timezone text, scheduled_start_at timestamp with time zone, schedule_windows jsonb, visible_outside_schedule boolean, schedule_paused boolean, host_paused boolean, allow_skip_proposing boolean, allow_skip_rating boolean, initial_message_audio_url text, initial_message_video_url text, background_audio_url text, name_translated text, description_translated text, initial_message_translated text, translation_language text, translations_enabled boolean, translation_languages text[], participant_count bigint, current_cycle_id bigint, current_round_phase text, current_round_custom_id integer, current_round_phase_ends_at timestamp with time zone, current_round_phase_started_at timestamp with time zone, viewing_language_code text, has_participated boolean, rating_mode text, match_objective text)
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
        END AS has_participated,
        c.rating_mode::TEXT,
        c.match_objective::TEXT
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
$function$;

GRANT EXECUTE ON FUNCTION public.get_my_chats_dashboard(uuid, text) TO PUBLIC, anon, authenticated, service_role;
