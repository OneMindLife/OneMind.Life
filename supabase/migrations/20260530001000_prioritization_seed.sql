-- Quick-Create flow, part 2: seed a prioritization round + on-demand advance.
--
-- A prioritization chat has a PREDEFINED list of options. There is nothing to propose,
-- so the chat skips proposing and starts directly in a single RATING round whose
-- propositions are "ownerless" (participant_id = NULL):
--   * NULL participant_id is exempt from idx_propositions_unique_new_per_round, so we can
--     seed many options in one round (the index only constrains non-null participants).
--   * Nobody owns them, so matches self-exclusion lets EVERYONE (incl. the creator) rate
--     the full list — exactly what "rank my list" needs.
--
-- The chat row itself is created by the client via the normal createChat path (so all the
-- ~40 chat columns get their correct values); this RPC only adds the cycle/round/options.

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

    -- cycle + round directly in RATING phase (no proposing — options are pre-supplied)
    INSERT INTO cycles (chat_id) VALUES (p_chat_id) RETURNING id INTO v_cycle_id;

    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(),
            calculate_round_minute_end(p_rating_duration_seconds))
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
    -- matches early-advance keys off get_rating_eligible_count, not funding, but we fund
    -- anyway for parity with the normal round-creation path.
    PERFORM fund_round_participants(v_round_id, p_chat_id);

    RETURN v_round_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seed_prioritization_round(BIGINT, TEXT[], INTEGER) TO authenticated;

COMMENT ON FUNCTION public.seed_prioritization_round(BIGINT, TEXT[], INTEGER) IS
    'Quick-create: seeds a single matches/full_rank rating round with ownerless options (participant_id NULL) so the host (and any invitees) can rank a predefined list. Host-only; one cycle per chat.';

-- On-demand timer processing. The solo preview should finalize the instant the creator
-- finishes rating, not wait up to 60s for the cron. This nudges the SAME process-timers
-- edge function the cron calls (no duplicated advance logic), which then early-advances any
-- round whose raters are all done (done >= eligible). Idempotent and global-safe: it only
-- advances rounds that already meet their criteria — exactly what the every-minute cron does.
CREATE OR REPLACE FUNCTION public.trigger_process_timers()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM net.http_post(
        url     := get_edge_function_url('process-timers'),
        headers := get_cron_headers(),
        body    := '{}'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_process_timers() TO authenticated;

COMMENT ON FUNCTION public.trigger_process_timers() IS
    'Client-callable nudge that invokes the process-timers edge function immediately (same path as cron). Used so the solo prioritization preview finalizes results instantly instead of waiting for the next cron tick.';
