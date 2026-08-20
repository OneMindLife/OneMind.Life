-- Quick-create: let seed_prioritization_round create a RATING round with no timer.
--
-- The PREVIEW seeds with a duration (timer is a harmless backstop; the preview also
-- auto-finalizes via matches_preview_maybe_finalize). The REAL chat the host shares
-- should have NO countdown — a 24h timer just confuses invitees ("why is there a clock?")
-- and a real chat finalizes via the host "End voting" button, not a timer.
--
-- Passing p_rating_duration_seconds => NULL now yields phase_ends_at = NULL (no timer),
-- which process-timers ignores (its passes require phase_ends_at IS NOT NULL). Behavior
-- for a non-null duration is unchanged. Only the phase_ends_at expression changed.

CREATE OR REPLACE FUNCTION public.seed_prioritization_round(
    p_chat_id BIGINT,
    p_options TEXT[],
    p_rating_duration_seconds INTEGER DEFAULT 86400
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_host        BOOLEAN;
    v_existing_cycle BIGINT;
    v_cycle_id       BIGINT;
    v_round_id       BIGINT;
    v_opt            TEXT;
    v_count          INTEGER := 0;
BEGIN
    -- authz: caller must be the chat's active host
    SELECT EXISTS(
        SELECT 1 FROM participants
        WHERE chat_id = p_chat_id
          AND user_id = auth.uid()
          AND is_host = true
          AND status = 'active'
    ) INTO v_is_host;
    IF NOT v_is_host THEN
        RAISE EXCEPTION 'Only the chat host can seed options';
    END IF;

    -- guard: never double-seed (one cycle per quick-create chat)
    SELECT id INTO v_existing_cycle FROM cycles WHERE chat_id = p_chat_id LIMIT 1;
    IF v_existing_cycle IS NOT NULL THEN
        RAISE EXCEPTION 'Chat % already has a cycle; cannot seed', p_chat_id;
    END IF;

    -- need >= 2 options (rating_minimum default is 2; matches needs >=2 to compare)
    IF array_length(p_options, 1) IS NULL OR array_length(p_options, 1) < 2 THEN
        RAISE EXCEPTION 'Need at least 2 options to seed (got %)', COALESCE(array_length(p_options, 1), 0);
    END IF;

    -- keep it free: a popular ranking must never stall on credits
    UPDATE chat_credits
    SET credit_balance = GREATEST(credit_balance, 100000), updated_at = NOW()
    WHERE chat_id = p_chat_id;

    -- cycle + round directly in RATING phase (no proposing — options are pre-supplied).
    -- NULL duration => NULL phase_ends_at (no timer); real shared chats use this.
    INSERT INTO cycles (chat_id) VALUES (p_chat_id) RETURNING id INTO v_cycle_id;

    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(),
            CASE WHEN p_rating_duration_seconds IS NULL
                 THEN NULL
                 ELSE calculate_round_minute_end(p_rating_duration_seconds) END)
    RETURNING id INTO v_round_id;

    -- seed ownerless options
    FOREACH v_opt IN ARRAY p_options LOOP
        v_opt := TRIM(v_opt);
        IF length(v_opt) > 0 THEN
            INSERT INTO propositions (round_id, participant_id, content)
            VALUES (v_round_id, NULL, LEFT(v_opt, 500));
            v_count := v_count + 1;
        END IF;
    END LOOP;

    IF v_count < 2 THEN
        RAISE EXCEPTION 'Need at least 2 non-empty options (got %)', v_count;
    END IF;

    -- fund participants for this round (harmless; high balance guarantees success).
    PERFORM fund_round_participants(v_round_id, p_chat_id);

    RETURN v_round_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seed_prioritization_round(BIGINT, TEXT[], INTEGER) TO authenticated;
