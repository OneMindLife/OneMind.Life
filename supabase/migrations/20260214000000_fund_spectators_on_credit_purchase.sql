-- =============================================================================
-- MIGRATION: Fund unfunded spectators when credits are purchased
-- =============================================================================
-- When a host buys credits mid-round, any participants who joined as spectators
-- (because credits were 0 at join time) should be automatically funded.
-- Also publishes round_funding to realtime so clients update immediately.
-- =============================================================================


-- =============================================================================
-- STEP 1: Function to fund unfunded spectators in the current active round
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fund_unfunded_spectators(p_chat_id BIGINT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round_id BIGINT;
    v_balance INTEGER;
    v_unfunded RECORD;
    v_funded_count INTEGER := 0;
BEGIN
    -- Find current active round (proposing or rating)
    SELECT r.id INTO v_round_id
    FROM public.rounds r
    JOIN public.cycles c ON c.id = r.cycle_id
    WHERE c.chat_id = p_chat_id
      AND r.phase IN ('proposing', 'rating')
    ORDER BY r.id DESC
    LIMIT 1;

    -- No active round — nothing to do
    IF v_round_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Lock credits row
    SELECT credit_balance INTO v_balance
    FROM public.chat_credits
    WHERE chat_id = p_chat_id
    FOR UPDATE;

    IF v_balance IS NULL OR v_balance < 1 THEN
        RETURN 0;  -- No credits available
    END IF;

    -- Fund unfunded active participants (oldest first), up to available balance
    FOR v_unfunded IN
        SELECT p.id AS participant_id
        FROM public.participants p
        WHERE p.chat_id = p_chat_id
          AND p.status = 'active'
          AND NOT EXISTS (
              SELECT 1 FROM public.round_funding rf
              WHERE rf.round_id = v_round_id AND rf.participant_id = p.id
          )
        ORDER BY p.created_at ASC
        LIMIT v_balance
    LOOP
        INSERT INTO public.round_funding (round_id, participant_id)
        VALUES (v_round_id, v_unfunded.participant_id)
        ON CONFLICT DO NOTHING;

        v_funded_count := v_funded_count + 1;
    END LOOP;

    -- Deduct credits and record transaction
    IF v_funded_count > 0 THEN
        UPDATE public.chat_credits
        SET credit_balance = credit_balance - v_funded_count,
            updated_at = NOW()
        WHERE chat_id = p_chat_id;

        INSERT INTO public.chat_credit_transactions
            (chat_id, transaction_type, amount, balance_after, round_id, participant_count)
        VALUES
            (p_chat_id, 'mid_round_join', -v_funded_count,
             v_balance - v_funded_count, v_round_id, v_funded_count);

        RAISE NOTICE '[FUND SPECTATORS] Funded % spectators for round % in chat %',
            v_funded_count, v_round_id, p_chat_id;
    END IF;

    RETURN v_funded_count;
END;
$$;

COMMENT ON FUNCTION public.fund_unfunded_spectators IS
'Funds unfunded spectators in the current active round when credits become available.
Called after credit purchases to retroactively fund participants who joined with 0 credits.';


-- =============================================================================
-- STEP 2: Update add_chat_credits to also fund active-round spectators
-- =============================================================================

CREATE OR REPLACE FUNCTION public.add_chat_credits(
    p_chat_id            BIGINT,
    p_amount             INTEGER,
    p_stripe_session_id  TEXT
)
RETURNS public.chat_credits
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result public.chat_credits;
    v_existing_txn BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Credit amount must be positive';
    END IF;

    -- Idempotency check: if this Stripe session was already processed, return current balance
    IF p_stripe_session_id IS NOT NULL THEN
        SELECT id INTO v_existing_txn
        FROM public.chat_credit_transactions
        WHERE stripe_checkout_session_id = p_stripe_session_id;

        IF v_existing_txn IS NOT NULL THEN
            SELECT * INTO v_result
            FROM public.chat_credits
            WHERE chat_id = p_chat_id;
            RETURN v_result;
        END IF;
    END IF;

    -- Add credits
    UPDATE public.chat_credits
    SET credit_balance = credit_balance + p_amount,
        updated_at = NOW()
    WHERE chat_id = p_chat_id
    RETURNING * INTO v_result;

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'No chat_credits row for chat_id %', p_chat_id;
    END IF;

    -- Record transaction
    INSERT INTO public.chat_credit_transactions
        (chat_id, transaction_type, amount, balance_after, stripe_checkout_session_id)
    VALUES
        (p_chat_id, 'purchase', p_amount, v_result.credit_balance, p_stripe_session_id);

    -- Check if a credit-paused waiting round can now resume
    PERFORM public.check_credit_resume(p_chat_id);

    -- Fund any unfunded spectators in the current active round
    PERFORM public.fund_unfunded_spectators(p_chat_id);

    -- Re-read balance after funding (may have decreased)
    SELECT * INTO v_result
    FROM public.chat_credits
    WHERE chat_id = p_chat_id;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.add_chat_credits IS
'Adds purchased credits to a chat. Idempotent via unique constraint on stripe_checkout_session_id.
After adding credits: resumes credit-paused rounds AND funds unfunded spectators in active rounds.';


-- =============================================================================
-- STEP 3: Publish round_funding to realtime so clients update automatically
-- =============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.round_funding;


-- =============================================================================
-- STEP 4: RLS policy for round_funding INSERT (needed for realtime to work)
-- round_funding already has a SELECT policy; realtime only needs SELECT.
-- =============================================================================
-- No changes needed — existing SELECT policy is sufficient for realtime.
