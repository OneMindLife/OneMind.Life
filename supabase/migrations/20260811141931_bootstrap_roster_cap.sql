-- get_chat_detail_bootstrap: stop shipping the whole participant roster.
--
-- Measured on prod 2026-08-11 for the GLOBAL room (chat 1269):
--   total response          1,198,363 B
--   └ participants          1,168,302 B  (97.5%, 2,987 rows @ ~391 B)
--   └ consensus_items          25,309 B  (2.1%  — the actual messages)
--
-- Every active participant of a public room is returned in full, and the room
-- polls this RPC every 3 s (ChatClient.tsx), so each open tab pulled ~24 MB/min.
-- Nobody ever "leaves" the global room, so the roster only grows: every new
-- visitor made the room slower for everyone, permanently.
--
-- And the wedge never reads it there. ChatClient routes the global room to
-- GlobalChat (max_cycles IS NULL, non-game), which owns the whole surface and
-- references `participants` zero times; `activeCount` in Voting/LeaderChallenge
-- is computed and never used. Only GameStatus (game standings) and Results
-- (winner-name lookup) genuinely read the array, and neither renders in a
-- continuous room.
--
-- Two changes:
--   1. Always return `participants_count`; only materialise the array for rooms
--      at or below k_max_roster. Small rooms (every decision/game chat) are
--      unaffected — they are orders of magnitude below the cap.
--   2. Strip `session_token` from the emitted rows. It is a credential and no
--      client needs another participant's. (`my_participant` is untouched — that
--      row is the viewer's own.)
--
-- Everything else is byte-identical to the previous definition.

CREATE OR REPLACE FUNCTION public.get_chat_detail_bootstrap(
    p_chat_id bigint,
    p_language_code text DEFAULT NULL::text,
    p_include_previous_results boolean DEFAULT false
)
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
    v_participants_count INT := 0;
    v_my_participant JSONB := NULL;
    v_pending_join_requests JSONB := '[]'::JSONB;
    v_chat_credits JSONB := NULL;
    v_previous_winners JSONB := '[]'::JSONB;
    v_previous_round_results JSONB := '[]'::JSONB;
    v_propositions JSONB := '[]'::JSONB;
    v_my_propositions JSONB := '[]'::JSONB;
    v_rating_progress JSONB := jsonb_build_object('rated', 0, 'total', 0, 'completed', FALSE, 'started', FALSE);
    v_skip_count INT := 0;
    v_has_skipped BOOLEAN := FALSE;
    v_rating_skip_count INT := 0;
    v_has_skipped_rating BOOLEAN := FALSE;
    v_affirmation_count INT := 0;
    v_has_affirmed BOOLEAN := FALSE;
    v_participants_who_rated JSONB := '[]'::JSONB;
    v_participants_who_proposed JSONB := '[]'::JSONB;
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
    -- Above this many active participants the roster is omitted (count only).
    -- Every real decision/game room is far below it; only the global arena isn't.
    k_max_roster CONSTANT INT := 500;
BEGIN
    v_user_id := auth.uid();
    SELECT * INTO v_chat_row FROM chats WHERE id = p_chat_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    SELECT p.id, p.is_host INTO v_my_participant_id, v_is_host
    FROM participants p WHERE p.chat_id = p_chat_id AND p.user_id = v_user_id LIMIT 1;
    v_can_view := (v_my_participant_id IS NOT NULL) OR (v_chat_row.access_method = 'public');
    v_is_host  := COALESCE(v_is_host, FALSE);
    IF NOT v_can_view THEN
        RETURN NULL;
    END IF;
    SELECT to_jsonb(c.*) ||
        jsonb_build_object(
            'name_translated', COALESCE(t_name.translated_text, t_name_en.translated_text, c.name),
            'description_translated', COALESCE(t_desc.translated_text, t_desc_en.translated_text, c.description),
            'initial_message_translated', COALESCE(t_msg.translated_text, t_msg_en.translated_text, c.initial_message),
            'translation_language',
            CASE WHEN p_language_code IS NULL THEN NULL
                 WHEN t_name.translated_text IS NOT NULL THEN p_language_code
                 WHEN t_name_en.translated_text IS NOT NULL THEN 'en'
                 ELSE 'original' END
        )
    INTO v_chat
    FROM chats c
    LEFT JOIN translations t_name ON t_name.chat_id = c.id AND t_name.field_name = 'name' AND p_language_code IS NOT NULL AND t_name.language_code = p_language_code
    LEFT JOIN translations t_name_en ON t_name_en.chat_id = c.id AND t_name_en.field_name = 'name' AND p_language_code IS NOT NULL AND p_language_code <> 'en' AND t_name_en.language_code = 'en'
    LEFT JOIN translations t_desc ON t_desc.chat_id = c.id AND t_desc.field_name = 'description' AND p_language_code IS NOT NULL AND t_desc.language_code = p_language_code
    LEFT JOIN translations t_desc_en ON t_desc_en.chat_id = c.id AND t_desc_en.field_name = 'description' AND p_language_code IS NOT NULL AND p_language_code <> 'en' AND t_desc_en.language_code = 'en'
    LEFT JOIN translations t_msg ON t_msg.chat_id = c.id AND t_msg.field_name = 'initial_message' AND p_language_code IS NOT NULL AND t_msg.language_code = p_language_code
    LEFT JOIN translations t_msg_en ON t_msg_en.chat_id = c.id AND t_msg_en.field_name = 'initial_message' AND p_language_code IS NOT NULL AND p_language_code <> 'en' AND t_msg_en.language_code = 'en'
    WHERE c.id = p_chat_id;
    IF v_my_participant_id IS NOT NULL THEN
        SELECT to_jsonb(p.*) INTO v_my_participant FROM participants p WHERE p.id = v_my_participant_id;
    END IF;

    -- ── Roster (see header): count always, array only for small rooms, and
    -- never the session_token.
    SELECT COUNT(*) INTO v_participants_count
    FROM participants p WHERE p.chat_id = p_chat_id AND p.status = 'active';

    IF v_participants_count <= k_max_roster THEN
        SELECT COALESCE(jsonb_agg((to_jsonb(p.*) - 'session_token') ORDER BY p.display_name), '[]'::JSONB)
        INTO v_participants
        FROM participants p WHERE p.chat_id = p_chat_id AND p.status = 'active';
    END IF;

    IF v_is_host THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(jr.*) ORDER BY jr.created_at), '[]'::JSONB) INTO v_pending_join_requests
        FROM join_requests jr WHERE jr.chat_id = p_chat_id AND jr.status = 'pending';
    END IF;
    SELECT to_jsonb(cc.*) INTO v_chat_credits FROM chat_credits cc WHERE cc.chat_id = p_chat_id LIMIT 1;
    SELECT COALESCE(jsonb_agg(item ORDER BY (item->>'completed_at')::TIMESTAMPTZ), '[]'::JSONB) INTO v_consensus_items
    FROM (
        SELECT jsonb_build_object(
            'id', cy.id, 'completed_at', cy.completed_at, 'winning_proposition_id', cy.winning_proposition_id,
            'task_result', cy.task_result, 'host_override', cy.host_override, 'video_url', cy.video_url, 'audio_url', cy.audio_url,
            'propositions', to_jsonb(p.*) || jsonb_build_object('content_translated', tr.translated_text,
                'language_code', CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code ELSE NULL END)
        ) AS item
        FROM cycles cy
        JOIN propositions p ON p.id = cy.winning_proposition_id
        LEFT JOIN translations tr ON tr.proposition_id = p.id AND tr.field_name = 'content' AND p_language_code IS NOT NULL AND tr.language_code = p_language_code
        WHERE cy.chat_id = p_chat_id AND cy.winning_proposition_id IS NOT NULL
    ) consensus_rows;
    SELECT to_jsonb(cy.*), cy.id INTO v_current_cycle, v_current_cycle_id
    FROM cycles cy WHERE cy.chat_id = p_chat_id AND cy.completed_at IS NULL ORDER BY cy.created_at DESC LIMIT 1;
    IF v_current_cycle_id IS NOT NULL THEN
        SELECT to_jsonb(r.*), r.id INTO v_current_round, v_current_round_id
        FROM rounds r WHERE r.cycle_id = v_current_cycle_id AND r.completed_at IS NULL ORDER BY r.custom_id DESC LIMIT 1;
        SELECT r.id, COALESCE(r.is_sole_winner, TRUE), r.winning_proposition_id INTO v_previous_round_id, v_is_sole_winner, v_primary_winner_id
        FROM rounds r WHERE r.cycle_id = v_current_cycle_id AND r.winning_proposition_id IS NOT NULL ORDER BY r.custom_id DESC LIMIT 1;
        IF v_previous_round_id IS NOT NULL THEN
            SELECT COALESCE(jsonb_agg(item ORDER BY (item->>'global_score')::NUMERIC DESC NULLS LAST), '[]'::JSONB) INTO v_previous_winners
            FROM (
                SELECT jsonb_build_object(
                    'id', rw.id, 'round_id', rw.round_id, 'proposition_id', rw.proposition_id, 'rank', rw.rank,
                    'global_score', rw.global_score, 'created_at', rw.created_at,
                    'propositions', jsonb_build_object('content', p.content),
                    'rounds', jsonb_build_object('audio_url', r.audio_url, 'video_url', r.video_url),
                    'content_translated', tr.translated_text,
                    'translation_language', CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code ELSE NULL END
                ) AS item
                FROM round_winners rw
                JOIN propositions p ON p.id = rw.proposition_id
                JOIN rounds r ON r.id = rw.round_id
                LEFT JOIN translations tr ON tr.proposition_id = rw.proposition_id AND tr.field_name = 'content' AND p_language_code IS NOT NULL AND tr.language_code = p_language_code
                WHERE rw.round_id = v_previous_round_id AND rw.rank = 1
            ) winners_rows;
            IF v_is_sole_winner AND v_primary_winner_id IS NOT NULL THEN
                SELECT public.count_consecutive_sole_wins(v_current_cycle_id, v_primary_winner_id) INTO v_consecutive_sole_wins;
            END IF;
            IF p_include_previous_results THEN
                SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ||
                    jsonb_build_object(
                        'proposition_global_scores', COALESCE((SELECT jsonb_agg(jsonb_build_object('global_score', g.global_score)) FROM proposition_global_scores g WHERE g.proposition_id = p.id), '[]'::JSONB),
                        'content_translated', tr.translated_text,
                        'language_code', CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code ELSE NULL END
                    )), '[]'::JSONB)
                INTO v_previous_round_results
                FROM propositions p
                LEFT JOIN translations tr ON tr.proposition_id = p.id AND tr.field_name = 'content' AND p_language_code IS NOT NULL AND tr.language_code = p_language_code
                WHERE p.round_id = v_previous_round_id;
            END IF;
        END IF;
        IF v_current_round_id IS NOT NULL AND v_my_participant_id IS NOT NULL THEN
            SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ||
                jsonb_build_object(
                    'proposition_movda_ratings', COALESCE((SELECT jsonb_agg(jsonb_build_object('rating', m.rating)) FROM proposition_movda_ratings m WHERE m.proposition_id = p.id), '[]'::JSONB),
                    'content_translated', tr.translated_text,
                    'language_code', CASE WHEN tr.translated_text IS NOT NULL THEN p_language_code ELSE NULL END
                ) ORDER BY p.created_at), '[]'::JSONB)
            INTO v_propositions
            FROM propositions p
            LEFT JOIN translations tr ON tr.proposition_id = p.id AND tr.field_name = 'content' AND p_language_code IS NOT NULL AND tr.language_code = p_language_code
            WHERE p.round_id = v_current_round_id;
            SELECT COALESCE(jsonb_agg(to_jsonb(p.*)), '[]'::JSONB) INTO v_my_propositions
            FROM propositions p WHERE p.round_id = v_current_round_id AND p.participant_id = v_my_participant_id;
            DECLARE
                v_total INT;
                v_rated INT;
            BEGIN
                SELECT COUNT(*) INTO v_total FROM propositions p WHERE p.round_id = v_current_round_id AND (p.participant_id IS NULL OR p.participant_id <> v_my_participant_id);
                SELECT COUNT(*) INTO v_rated FROM grid_rankings g WHERE g.round_id = v_current_round_id AND g.participant_id = v_my_participant_id;
                v_my_current_round_rating_count := v_rated;
                v_rating_progress := jsonb_build_object('rated', v_rated, 'total', v_total, 'completed', (v_rated >= v_total AND v_total > 0), 'started', (v_rated > 0));
            END;
            SELECT COUNT(*) INTO v_skip_count FROM round_skips s WHERE s.round_id = v_current_round_id;
            SELECT EXISTS (SELECT 1 FROM round_skips s WHERE s.round_id = v_current_round_id AND s.participant_id = v_my_participant_id) INTO v_has_skipped;
            SELECT COUNT(*) INTO v_rating_skip_count FROM rating_skips s WHERE s.round_id = v_current_round_id;
            SELECT EXISTS (SELECT 1 FROM rating_skips s WHERE s.round_id = v_current_round_id AND s.participant_id = v_my_participant_id) INTO v_has_skipped_rating;
            SELECT COUNT(*) INTO v_affirmation_count FROM affirmations a WHERE a.round_id = v_current_round_id;
            SELECT EXISTS (SELECT 1 FROM affirmations a WHERE a.round_id = v_current_round_id AND a.participant_id = v_my_participant_id) INTO v_has_affirmed;
            SELECT COALESCE(jsonb_agg(DISTINCT p.participant_id), '[]'::JSONB) INTO v_participants_who_proposed
            FROM propositions p WHERE p.round_id = v_current_round_id AND p.carried_from_id IS NULL AND p.participant_id IS NOT NULL;
            SELECT COALESCE(jsonb_agg(s.participant_id), '[]'::JSONB) INTO v_participants_who_skipped_proposing FROM round_skips s WHERE s.round_id = v_current_round_id;
            SELECT COALESCE(jsonb_agg(s.participant_id), '[]'::JSONB) INTO v_participants_who_skipped_rating FROM rating_skips s WHERE s.round_id = v_current_round_id;
            SELECT COALESCE(jsonb_agg(a.participant_id), '[]'::JSONB) INTO v_participants_who_affirmed FROM affirmations a WHERE a.round_id = v_current_round_id;
            DECLARE
                v_total_props INT;
            BEGIN
                SELECT COUNT(*) INTO v_total_props FROM propositions p WHERE p.round_id = v_current_round_id;
                IF v_total_props > 0 THEN
                    WITH authored AS (
                        SELECT participant_id, COUNT(*)::INT AS own_count FROM propositions
                        WHERE round_id = v_current_round_id AND participant_id IS NOT NULL GROUP BY participant_id
                    ),
                    rated AS (
                        SELECT participant_id, COUNT(*)::INT AS rated_count FROM grid_rankings
                        WHERE round_id = v_current_round_id AND participant_id IS NOT NULL GROUP BY participant_id
                    )
                    SELECT COALESCE(jsonb_agg(r.participant_id), '[]'::JSONB) INTO v_participants_who_rated
                    FROM rated r LEFT JOIN authored a ON a.participant_id = r.participant_id
                    WHERE LEAST(v_total_props - COALESCE(a.own_count, 0), k_max_ratings_per_user) > 0
                      AND r.rated_count >= LEAST(v_total_props - COALESCE(a.own_count, 0), k_max_ratings_per_user);
                END IF;
            END;
            SELECT COALESCE(
                (SELECT jsonb_agg(DISTINCT pid) FROM (
                    SELECT (jsonb_array_elements_text(v_participants_who_rated))::BIGINT AS pid
                    UNION
                    SELECT rc.participant_id FROM rating_completions rc
                    WHERE rc.round_id = v_current_round_id AND rc.participant_id IS NOT NULL
                ) u),
                '[]'::JSONB
            ) INTO v_participants_who_rated;
            DECLARE
                v_min INT;
            BEGIN
                WITH counts AS (
                    SELECT p.id, (SELECT COUNT(*)::INT FROM grid_rankings g WHERE g.round_id = v_current_round_id AND g.proposition_id = p.id) AS c
                    FROM propositions p WHERE p.round_id = v_current_round_id
                )
                SELECT MIN(c) INTO v_min FROM counts;
                v_min_ratings_per_prop := COALESCE(v_min, 0);
            END;
            SELECT EXISTS (SELECT 1 FROM round_funding rf WHERE rf.round_id = v_current_round_id AND rf.participant_id = v_my_participant_id) INTO v_my_funding_exists;
            IF v_my_funding_exists THEN
                v_is_my_participant_funded := TRUE;
            ELSE
                SELECT public.get_funded_participant_count(v_current_round_id) INTO v_funded_count;
                v_is_my_participant_funded := COALESCE(v_funded_count, 0) = 0;
            END IF;
        END IF;
        SELECT COALESCE((SELECT jsonb_agg(cat) FROM (SELECT unnest(public.get_chat_allowed_categories(p_chat_id)) AS cat) sub), '[]'::JSONB) INTO v_allowed_categories;
    END IF;
    RETURN jsonb_build_object(
        'chat', v_chat, 'current_cycle', v_current_cycle, 'current_round', v_current_round,
        'consensus_items', v_consensus_items, 'participants', v_participants, 'my_participant', v_my_participant,
        'participants_count', v_participants_count,
        'pending_join_requests', v_pending_join_requests, 'chat_credits', v_chat_credits,
        'previous_round_winners', v_previous_winners, 'is_sole_winner', v_is_sole_winner,
        'consecutive_sole_wins', v_consecutive_sole_wins, 'previous_round_id', v_previous_round_id,
        'primary_winner_id', v_primary_winner_id, 'previous_round_results', v_previous_round_results,
        'propositions', v_propositions, 'my_propositions', v_my_propositions, 'rating_progress', v_rating_progress,
        'skip_count', v_skip_count, 'has_skipped', v_has_skipped, 'rating_skip_count', v_rating_skip_count,
        'has_skipped_rating', v_has_skipped_rating, 'affirmation_count', v_affirmation_count, 'has_affirmed', v_has_affirmed,
        'participants_who_rated', v_participants_who_rated, 'participants_who_proposed', v_participants_who_proposed,
        'participants_who_skipped_proposing', v_participants_who_skipped_proposing,
        'participants_who_skipped_rating', v_participants_who_skipped_rating,
        'participants_who_affirmed', v_participants_who_affirmed, 'min_ratings_per_prop', v_min_ratings_per_prop,
        'my_current_round_rating_count', v_my_current_round_rating_count,
        'is_my_participant_funded', v_is_my_participant_funded, 'allowed_categories', v_allowed_categories
    );
END;
$function$;
