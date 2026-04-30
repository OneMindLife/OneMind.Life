-- Migration: fix get_my_chats_dashboard.has_participated for rating phase.
--
-- The previous implementation checked `round_participant_submissions` to
-- decide whether a user had finished rating — but the Flutter client never
-- writes to that table. The rating UI writes grid positions to
-- `grid_rankings` directly (see PropositionService.submitGridRankings) and
-- writes skips to `rating_skips`; the `submit-ratings` edge function that
-- would have populated `round_participant_submissions` is orphaned.
--
-- Effect of the bug: users who finished rating stayed in the "Next up" pile
-- on Home because the dashboard still reported has_participated = FALSE.
--
-- Fix: mirror the Flutter source of truth.
--   * rating   → user placed every non-own proposition on the grid, OR
--                user explicitly skipped rating for this round.
--   * proposing → unchanged check (submitted own proposition), OR
--                 user explicitly skipped proposing via `round_skips`.

CREATE OR REPLACE FUNCTION public.get_my_chats_dashboard(
    p_user_id UUID,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE(
    id BIGINT, name TEXT, initial_message TEXT, description TEXT,
    invite_code TEXT, access_method TEXT, require_auth BOOLEAN, require_approval BOOLEAN,
    creator_id UUID, creator_session_token UUID, host_display_name TEXT,
    is_active BOOLEAN, is_official BOOLEAN, expires_at TIMESTAMPTZ, last_activity_at TIMESTAMPTZ,
    start_mode TEXT, rating_start_mode TEXT, auto_start_participant_count INTEGER,
    proposing_duration_seconds INTEGER, rating_duration_seconds INTEGER,
    proposing_minimum INTEGER, rating_minimum INTEGER,
    proposing_threshold_percent INTEGER, proposing_threshold_count INTEGER,
    rating_threshold_percent INTEGER, rating_threshold_count INTEGER,
    enable_ai_participant BOOLEAN, ai_propositions_count INTEGER,
    confirmation_rounds_required INTEGER, show_previous_results BOOLEAN,
    propositions_per_user INTEGER, created_at TIMESTAMPTZ,
    adaptive_duration_enabled BOOLEAN, adaptive_adjustment_percent INTEGER,
    min_phase_duration_seconds INTEGER, max_phase_duration_seconds INTEGER,
    schedule_type TEXT, schedule_timezone TEXT, scheduled_start_at TIMESTAMPTZ,
    schedule_windows JSONB, visible_outside_schedule BOOLEAN,
    schedule_paused BOOLEAN, host_paused BOOLEAN,
    allow_skip_proposing BOOLEAN, allow_skip_rating BOOLEAN,
    initial_message_audio_url TEXT, initial_message_video_url TEXT,
    background_audio_url TEXT,
    name_translated TEXT, description_translated TEXT, initial_message_translated TEXT,
    translation_language TEXT, translations_enabled BOOLEAN, translation_languages TEXT[],
    participant_count BIGINT, current_cycle_id BIGINT, current_round_phase TEXT,
    current_round_custom_id INTEGER, current_round_phase_ends_at TIMESTAMPTZ,
    current_round_phase_started_at TIMESTAMPTZ, viewing_language_code TEXT,
    has_participated BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
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
                )
                OR EXISTS (
                    SELECT 1 FROM round_skips rsk
                    WHERE rsk.round_id = ar.round_id
                      AND rsk.participant_id = p.id
                )
            )
            WHEN ar.phase::TEXT = 'rating' THEN (
                -- Placed every non-own proposition on the grid.
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
                -- ...or explicitly skipped rating for this round.
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
$$;

GRANT EXECUTE ON FUNCTION public.get_my_chats_dashboard(UUID, TEXT) TO authenticated;
