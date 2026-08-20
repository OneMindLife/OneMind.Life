-- AI game participant — agent creation + scoring/leaderboard exclusion.
--
-- The AI is a real participant (is_agent=true) so it shows in the roster and its
-- proposition is authored ("by AI") and can win. But it is NOT scored: excluded
-- from the leaderboard AND from the human proposing-rank computation (its idea
-- still competes in the vote — it just doesn't occupy a rank slot that would
-- shift human scores).
--
-- Creation is gated on chats.has_ai_player (set true by the app for games) rather
-- than mode='game' directly, so test fixtures and non-app inserts don't silently
-- gain an agent.

ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS has_ai_player boolean NOT NULL DEFAULT false;

-- ── add the AI participant when a game opts in ──
CREATE OR REPLACE FUNCTION public.add_game_ai_participant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status, is_agent)
  VALUES (NEW.id, gen_random_uuid(), 'AI', false, 'active', true);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS add_game_ai_participant_trg ON public.chats;
CREATE TRIGGER add_game_ai_participant_trg
AFTER INSERT ON public.chats
FOR EACH ROW
WHEN (NEW.has_ai_player IS TRUE)
EXECUTE FUNCTION public.add_game_ai_participant();

-- ── get_cycle_leaderboard: exclude agents (AI never scored) ──
CREATE OR REPLACE FUNCTION public.get_cycle_leaderboard(p_cycle_id bigint)
RETURNS TABLE(participant_id bigint, display_name text, avg_rank real, rounds_participated integer, total_rounds integer)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id bigint;
  v_total_rounds integer;
BEGIN
  SELECT chat_id INTO v_chat_id FROM cycles WHERE id = p_cycle_id;
  IF v_chat_id IS NULL THEN
    RETURN;
  END IF;

  SELECT count(DISTINCT r.id) INTO v_total_rounds
  FROM rounds r
  WHERE r.cycle_id = p_cycle_id
    AND EXISTS (SELECT 1 FROM user_round_ranks u WHERE u.round_id = r.id);

  RETURN QUERY
  SELECT p.id,
         p.display_name,
         AVG(urr.rank)::real        AS avg_rank,
         COUNT(urr.id)::integer     AS rounds_participated,
         v_total_rounds             AS total_rounds
  FROM participants p
  JOIN user_round_ranks urr ON urr.participant_id = p.id
  JOIN rounds r            ON r.id = urr.round_id AND r.cycle_id = p_cycle_id
  WHERE p.chat_id = v_chat_id
    AND p.status = 'active'
    AND p.is_agent = false
  GROUP BY p.id, p.display_name
  ORDER BY AVG(urr.rank) DESC NULLS LAST;
END;
$function$;

-- ── calculate_proposing_ranks: exclude the AI's proposition from human scoring ──
CREATE OR REPLACE FUNCTION public.calculate_proposing_ranks(p_round_id bigint)
 RETURNS TABLE(participant_id bigint, rank real, avg_score real, proposition_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_min_avg REAL;
    v_max_avg REAL;
    v_user RECORD;
    v_mode TEXT;
    v_carried_score REAL;
BEGIN
    SELECT ch.mode INTO v_mode
    FROM rounds r
    JOIN cycles cy ON cy.id = r.cycle_id
    JOIN chats ch ON ch.id = cy.chat_id
    WHERE r.id = p_round_id;

    DROP TABLE IF EXISTS temp_proposing_scores;
    CREATE TEMP TABLE temp_proposing_scores AS
    SELECT
        p.participant_id,
        AVG(COALESCE(pgs.global_score, 50.0)) as avg_score,
        COUNT(*)::INTEGER as proposition_count
    FROM propositions p
    LEFT JOIN proposition_global_scores pgs
        ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
    WHERE p.round_id = p_round_id
    AND p.carried_from_id IS NULL
    AND p.participant_id IS NOT NULL
    -- Exclude the AI participant's proposition: it competes in the vote but must
    -- not occupy a rank slot that shifts the human proposers' scores.
    AND NOT EXISTS (
        SELECT 1 FROM participants pt
        WHERE pt.id = p.participant_id AND pt.is_agent = true
    )
    GROUP BY p.participant_id;

    IF v_mode = 'game' THEN
        SELECT AVG(COALESCE(pgs.global_score, 50.0))::REAL
        INTO v_carried_score
        FROM propositions p
        LEFT JOIN proposition_global_scores pgs
            ON pgs.proposition_id = p.id AND pgs.round_id = p_round_id
        WHERE p.round_id = p_round_id
        AND p.carried_from_id IS NOT NULL;

        IF v_carried_score IS NOT NULL THEN
            INSERT INTO temp_proposing_scores (participant_id, avg_score, proposition_count)
            SELECT a.participant_id, v_carried_score, 0
            FROM affirmations a
            WHERE a.round_id = p_round_id
            AND NOT EXISTS (
                SELECT 1 FROM temp_proposing_scores t
                WHERE t.participant_id = a.participant_id
            );
        END IF;
    END IF;

    SELECT MIN(t.avg_score), MAX(t.avg_score)
    INTO v_min_avg, v_max_avg
    FROM temp_proposing_scores t;

    FOR v_user IN
        SELECT * FROM temp_proposing_scores
    LOOP
        participant_id := v_user.participant_id;
        avg_score := v_user.avg_score;
        proposition_count := v_user.proposition_count;

        IF v_max_avg IS NULL OR v_min_avg IS NULL THEN
            rank := NULL;
        ELSIF v_max_avg = v_min_avg THEN
            rank := 100.0;
        ELSE
            rank := LEAST(100.0, GREATEST(0.0,
                ((v_user.avg_score - v_min_avg) / (v_max_avg - v_min_avg)) * 100.0));
        END IF;

        RETURN NEXT;
    END LOOP;

    DROP TABLE IF EXISTS temp_proposing_scores;
END;
$function$;
