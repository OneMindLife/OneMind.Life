-- =============================================================================
-- SECURITY: gate the round-content DEFINER RPCs on chat membership.
-- =============================================================================
-- Vulnerability (found 2026-07-07): four SECURITY DEFINER RPCs are GRANTed to
-- anon and read a round's PROPOSITION TEXT (and winner text) with NO membership
-- check. They take a round_id, so an unauthenticated caller who guesses/enumerates
-- a round_id can read the propositions of a PRIVATE (access_method <> 'public')
-- chat. Confirmed by calling each as the anon role with no JWT against private
-- chat 1185 (round 3612 = 6 props, round 3605 = winner) — all returned content.
--
--   get_propositions_with_scores(round_id)            -- all proposition text + scores
--   get_propositions_with_translations(round_id,lang) -- all props + translations
--   get_unranked_propositions(round_id,pid,token)     -- proposition text
--   get_round_winners(round_id)                       -- winner content
--
-- Fix: apply the SAME gate the results/history RPCs got in
-- 20260708033853_gate_results_rpcs_membership.sql — reuse can_read_chat_results
-- (service_role OR public chat OR caller is a participant of the chat, ANY
-- status). Because these RPCs key on round_id, add a thin
-- can_read_round_results(round_id) that resolves the chat via rounds -> cycles
-- and delegates. Non-members of private chats now get zero rows; participants,
-- public-chat viewers, and the backend (service_role, used by agents/edge fns)
-- are unchanged. The query bodies are preserved byte-for-byte; only an early
-- gate + SET search_path are added.
-- =============================================================================

-- Round-level gate: resolve the round's chat and delegate to the chat gate.
-- A NULL chat_id (unknown round) yields FALSE for non-service callers -> empty.
CREATE OR REPLACE FUNCTION public.can_read_round_results(p_round_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.can_read_chat_results(
    (SELECT cy.chat_id FROM public.rounds r
       JOIN public.cycles cy ON cy.id = r.cycle_id
       WHERE r.id = p_round_id));
$$;

GRANT EXECUTE ON FUNCTION public.can_read_round_results(BIGINT) TO anon, authenticated;

-- 1. Propositions + MOVDA/global scores.
CREATE OR REPLACE FUNCTION public.get_propositions_with_scores(p_round_id bigint)
 RETURNS TABLE(proposition_id bigint, content text, participant_id bigint, global_score real, movda_rating real, rank integer, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
    IF NOT public.can_read_round_results(p_round_id) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT
        p.id as proposition_id,
        p.content,
        p.participant_id,
        COALESCE(pgs.global_score, 0.0) as global_score,
        COALESCE(pmr.rating, 1500.0) as movda_rating,
        ROW_NUMBER() OVER (ORDER BY COALESCE(pgs.global_score, 0.0) DESC)::INTEGER as rank,
        p.created_at
    FROM propositions p
    LEFT JOIN proposition_global_scores pgs
        ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
    LEFT JOIN proposition_movda_ratings pmr
        ON pmr.proposition_id = p.id AND pmr.round_id = p_round_id
    WHERE p.round_id = p_round_id
    ORDER BY COALESCE(pgs.global_score, 0.0) DESC;
END;
$function$;

-- 2. Propositions with translations.
CREATE OR REPLACE FUNCTION public.get_propositions_with_translations(p_round_id bigint, p_language_code text DEFAULT 'en'::text)
 RETURNS TABLE(id bigint, round_id bigint, participant_id bigint, content text, content_translated text, language_code text, created_at timestamp with time zone, carried_from_id bigint, proposition_global_scores jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
    IF NOT public.can_read_round_results(p_round_id) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT
        p.id,
        p.round_id,
        p.participant_id,
        p.content,
        -- Fallback chain: requested language -> English -> original content
        -- For carried propositions, look up translations from the ORIGINAL proposition
        COALESCE(
            -- First try: requested language (from original if carried)
            t.translated_text,
            -- Second try: English (if requested language is not English)
            CASE WHEN p_language_code != 'en' THEN (
                SELECT t2.translated_text
                FROM public.translations t2
                WHERE t2.proposition_id = COALESCE(p.carried_from_id, p.id)
                  AND t2.field_name = 'content'
                  AND t2.language_code = 'en'
                LIMIT 1
            ) ELSE NULL END,
            -- Fallback: original content
            p.content
        ) as content_translated,
        COALESCE(t.language_code, 'original') as language_code,
        p.created_at,
        p.carried_from_id,
        -- Include global_score as JSONB to match the expected format from Proposition.fromJson
        (
            SELECT jsonb_build_object('global_score', pgs.global_score)
            FROM public.proposition_global_scores pgs
            WHERE pgs.proposition_id = p.id
              AND pgs.round_id = p_round_id
            LIMIT 1
        ) as proposition_global_scores
    FROM public.propositions p
    -- Join translations using the ORIGINAL proposition ID for carried propositions
    LEFT JOIN public.translations t
        ON t.proposition_id = COALESCE(p.carried_from_id, p.id)
        AND t.field_name = 'content'
        AND t.language_code = p_language_code
    WHERE p.round_id = p_round_id
    ORDER BY p.created_at ASC;
END;
$function$;

-- 3. Unranked propositions for a rater.
CREATE OR REPLACE FUNCTION public.get_unranked_propositions(p_round_id bigint, p_participant_id bigint DEFAULT NULL::bigint, p_session_token uuid DEFAULT NULL::uuid)
 RETURNS TABLE(proposition_id bigint, content text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_current_user_id UUID;
BEGIN
    IF NOT public.can_read_round_results(p_round_id) THEN
        RETURN;
    END IF;
    -- Get the user_id for the participant (if provided)
    IF p_participant_id IS NOT NULL THEN
        SELECT user_id INTO v_current_user_id
        FROM participants
        WHERE id = p_participant_id;
    END IF;

    -- Get propositions that this user hasn't ranked yet
    -- Excludes:
    -- 1. User's own propositions (by participant_id)
    -- 2. Propositions where user is the ORIGINAL author (for carried props)
    -- 3. Already ranked propositions
    RETURN QUERY
    SELECT
        p.id as proposition_id,
        p.content,
        p.created_at
    FROM propositions p
    WHERE p.round_id = p_round_id
    -- Exclude own propositions (by participant_id if available)
    AND (p_participant_id IS NULL OR p.participant_id IS DISTINCT FROM p_participant_id)
    -- Exclude propositions where user is the ORIGINAL author (handles carried props)
    AND (v_current_user_id IS NULL OR get_original_author_user_id(p.id) IS DISTINCT FROM v_current_user_id)
    -- Exclude already ranked
    AND NOT EXISTS (
        SELECT 1 FROM grid_rankings gr
        WHERE gr.round_id = p_round_id
        AND gr.proposition_id = p.id
        AND (
            (p_participant_id IS NOT NULL AND gr.participant_id = p_participant_id)
            OR
            (p_session_token IS NOT NULL AND gr.session_token = p_session_token)
        )
    )
    ORDER BY p.created_at;
END;
$function$;

-- 4. Round winners (winner content).
CREATE OR REPLACE FUNCTION public.get_round_winners(p_round_id bigint)
 RETURNS TABLE(winner_id bigint, round_id bigint, proposition_id bigint, rank integer, global_score real, content text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
    IF NOT public.can_read_round_results(p_round_id) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT
        rw.id as winner_id,
        rw.round_id,
        rw.proposition_id,
        rw.rank,
        rw.global_score,
        p.content,
        rw.created_at
    FROM round_winners rw
    JOIN propositions p ON p.id = rw.proposition_id
    WHERE rw.round_id = p_round_id
    ORDER BY rw.rank ASC, rw.global_score DESC NULLS LAST;
END;
$function$;
