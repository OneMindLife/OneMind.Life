-- =============================================================================
-- Add `participants_who_proposed` to the chat-detail bootstrap RPC.
-- =============================================================================
-- The participants-leaderboard "Done" tag works in the RATING phase (driven by
-- participants_who_rated / participants_who_skipped_rating) but NOT in the
-- PROPOSING phase, because the client had no "who proposed" signal — proposition
-- authorship is anonymous/hidden during proposing and the per-round propositions
-- the client receives don't reliably expose who has acted.
--
-- This migration CREATE OR REPLACEs get_chat_detail_bootstrap to also return
-- `participants_who_proposed`: the DISTINCT participant_ids that have a NEW
-- proposition (carried_from_id IS NULL) in the current round. The function is
-- SECURITY DEFINER, so this count bypasses RLS — it leaks only PARTICIPATION
-- (who submitted), never idea content.
--
-- This is a pure addition: the rest of the function body is reproduced verbatim
-- from 20260501233023_chat_detail_bootstrap.sql.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_chat_detail_bootstrap(
    p_chat_id BIGINT,
    p_language_code TEXT DEFAULT NULL,
    p_include_previous_results BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

    -- Mirrors PropositionService.kMaxRatingsPerUser. If the constant moves
    -- in Flutter, update here too.
    k_max_ratings_per_user CONSTANT INT := 7;
BEGIN
    v_user_id := auth.uid();

    SELECT * INTO v_chat_row FROM chats WHERE id = p_chat_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Access check: caller must be a participant (any status) OR chat must be
    -- publicly viewable. We do NOT silently auto-join here — the bootstrap is
    -- read-only.
    SELECT p.id, p.is_host
    INTO v_my_participant_id, v_is_host
    FROM participants p
    WHERE p.chat_id = p_chat_id
      AND p.user_id = v_user_id
    LIMIT 1;

    -- v_my_participant_id is NULL when the caller has no participant row.
    -- Note: SELECT INTO sets all targets to NULL when no row matches, so we
    -- must check explicitly; "IF NOT v_can_view" with NULL evaluates FALSE.
    v_can_view := (v_my_participant_id IS NOT NULL)
                  OR (v_chat_row.access_method = 'public');
    v_is_host  := COALESCE(v_is_host, FALSE);

    IF NOT v_can_view THEN
        RETURN NULL;
    END IF;

    -- ---------------------------------------------------------------------
    -- Chat row + translations applied inline.
    -- ---------------------------------------------------------------------
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

    -- ---------------------------------------------------------------------
    -- My participant row (full JSON).
    -- ---------------------------------------------------------------------
    IF v_my_participant_id IS NOT NULL THEN
        SELECT to_jsonb(p.*)
        INTO v_my_participant
        FROM participants p
        WHERE p.id = v_my_participant_id;
    END IF;

    -- ---------------------------------------------------------------------
    -- Active participants (status='active', ordered by display_name).
    -- ---------------------------------------------------------------------
    SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.display_name), '[]'::JSONB)
    INTO v_participants
    FROM participants p
    WHERE p.chat_id = p_chat_id AND p.status = 'active';

    -- ---------------------------------------------------------------------
    -- Pending join requests — host only, ordered by created_at.
    -- ---------------------------------------------------------------------
    IF v_is_host THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(jr.*) ORDER BY jr.created_at), '[]'::JSONB)
        INTO v_pending_join_requests
        FROM join_requests jr
        WHERE jr.chat_id = p_chat_id AND jr.status = 'pending';
    END IF;

    -- ---------------------------------------------------------------------
    -- Chat credits (1:1 with chat).
    -- ---------------------------------------------------------------------
    SELECT to_jsonb(cc.*)
    INTO v_chat_credits
    FROM chat_credits cc
    WHERE cc.chat_id = p_chat_id
    LIMIT 1;

    -- ---------------------------------------------------------------------
    -- Consensus items: completed cycles with a winning proposition. Joined
    -- with translations on the proposition content.
    -- ---------------------------------------------------------------------
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

    -- ---------------------------------------------------------------------
    -- Current cycle (most recent uncompleted).
    -- ---------------------------------------------------------------------
    SELECT to_jsonb(cy.*), cy.id
    INTO v_current_cycle, v_current_cycle_id
    FROM cycles cy
    WHERE cy.chat_id = p_chat_id AND cy.completed_at IS NULL
    ORDER BY cy.created_at DESC
    LIMIT 1;

    -- ---------------------------------------------------------------------
    -- Round-scoped data only when a cycle exists.
    -- ---------------------------------------------------------------------
    IF v_current_cycle_id IS NOT NULL THEN
        -- Current round: most recent uncompleted round.
        SELECT to_jsonb(r.*), r.id
        INTO v_current_round, v_current_round_id
        FROM rounds r
        WHERE r.cycle_id = v_current_cycle_id AND r.completed_at IS NULL
        ORDER BY r.custom_id DESC
        LIMIT 1;

        -- Previous round (most recent completed-with-winner in cycle).
        SELECT r.id, COALESCE(r.is_sole_winner, TRUE), r.winning_proposition_id
        INTO v_previous_round_id, v_is_sole_winner, v_primary_winner_id
        FROM rounds r
        WHERE r.cycle_id = v_current_cycle_id
          AND r.winning_proposition_id IS NOT NULL
        ORDER BY r.custom_id DESC
        LIMIT 1;

        IF v_previous_round_id IS NOT NULL THEN
            -- All rank-1 winners for that round, with translations + nested
            -- propositions/rounds joins so the existing fromJson handles it.
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
                -- Reuse existing helper RPC.
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

        -- Round-scoped data needs both round and participant.
        IF v_current_round_id IS NOT NULL AND v_my_participant_id IS NOT NULL THEN
            -- Propositions for this round, with movda ratings (matches
            -- getPropositions shape).
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

            -- My propositions for this round (no joins).
            SELECT COALESCE(jsonb_agg(to_jsonb(p.*)), '[]'::JSONB)
            INTO v_my_propositions
            FROM propositions p
            WHERE p.round_id = v_current_round_id
              AND p.participant_id = v_my_participant_id;

            -- Rating progress: count of non-self propositions vs my grid
            -- rankings for this round.
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

            -- Skip counts and per-user flags.
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

            -- Affirmations.
            SELECT COUNT(*) INTO v_affirmation_count
            FROM affirmations a WHERE a.round_id = v_current_round_id;

            SELECT EXISTS (
                SELECT 1 FROM affirmations a
                WHERE a.round_id = v_current_round_id
                  AND a.participant_id = v_my_participant_id
            ) INTO v_has_affirmed;

            -- Participants who proposed: DISTINCT authors of a NEW proposition
            -- (carried_from_id IS NULL) in the current round. Drives the
            -- proposing-phase "Done" tag on the participants leaderboard.
            -- SECURITY DEFINER bypasses RLS, so this exposes only WHO submitted
            -- (participation) — never the idea content.
            SELECT COALESCE(jsonb_agg(DISTINCT p.participant_id), '[]'::JSONB)
            INTO v_participants_who_proposed
            FROM propositions p
            WHERE p.round_id = v_current_round_id
              AND p.carried_from_id IS NULL
              AND p.participant_id IS NOT NULL;

            -- Participants who skipped proposing/rating/affirmed (id sets).
            SELECT COALESCE(jsonb_agg(s.participant_id), '[]'::JSONB)
            INTO v_participants_who_skipped_proposing
            FROM round_skips s WHERE s.round_id = v_current_round_id;

            SELECT COALESCE(jsonb_agg(s.participant_id), '[]'::JSONB)
            INTO v_participants_who_skipped_rating
            FROM rating_skips s WHERE s.round_id = v_current_round_id;

            SELECT COALESCE(jsonb_agg(a.participant_id), '[]'::JSONB)
            INTO v_participants_who_affirmed
            FROM affirmations a WHERE a.round_id = v_current_round_id;

            -- Participants who completed rating (mirrors
            -- PropositionService.getParticipantsWhoRated logic).
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

            -- Min ratings per proposition (lowest-rated count across props).
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

            -- Funding: my round_funding row OR the round has no funding rows.
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

        -- Allowed proposition categories for the cycle.
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
        'participants_who_proposed', v_participants_who_proposed,
        'participants_who_skipped_proposing', v_participants_who_skipped_proposing,
        'participants_who_skipped_rating', v_participants_who_skipped_rating,
        'participants_who_affirmed', v_participants_who_affirmed,
        'min_ratings_per_prop', v_min_ratings_per_prop,
        'my_current_round_rating_count', v_my_current_round_rating_count,
        'is_my_participant_funded', v_is_my_participant_funded,
        'allowed_categories', v_allowed_categories
    );
END;
$$;

COMMENT ON FUNCTION public.get_chat_detail_bootstrap(BIGINT, TEXT, BOOLEAN) IS
'Returns one JSONB payload containing every field ChatDetailNotifier._loadData '
'needs. Replaces 18 parallel client queries with one round-trip. SECURITY '
'DEFINER + caller must be a participant of the chat or chat must be public; '
'otherwise returns NULL (mirrors RLS-filtered getChatById behaviour). '
'Includes participants_who_proposed (DISTINCT authors of a NEW proposition in '
'the current round) so the proposing-phase Done tag has a who-proposed signal.';

GRANT EXECUTE ON FUNCTION public.get_chat_detail_bootstrap(BIGINT, TEXT, BOOLEAN)
    TO authenticated, anon;
