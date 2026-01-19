-- Migration: Add billing/credits schema
-- Pricing model:
--   - Anonymous hosts: 1 hour max chat duration (free)
--   - Signed-in hosts: 500 free user-rounds/month, then $0.01/user-round
--   - 1 credit = 1 user-round = $0.01

-- ============================================================================
-- STEP 0: Helper function for updated_at triggers
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 1: User credits balance table
-- ============================================================================

CREATE TABLE public.user_credits (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    credit_balance INTEGER NOT NULL DEFAULT 0 CHECK (credit_balance >= 0),
    free_tier_used INTEGER NOT NULL DEFAULT 0,
    free_tier_reset_at TIMESTAMPTZ NOT NULL DEFAULT date_trunc('month', NOW()) + interval '1 month',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Index for quick lookup by user
CREATE INDEX idx_user_credits_user_id ON public.user_credits(user_id);

-- Auto-update updated_at
CREATE TRIGGER update_user_credits_updated_at
    BEFORE UPDATE ON public.user_credits
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE public.user_credits IS 'Tracks credit balance and free tier usage per user';
COMMENT ON COLUMN public.user_credits.credit_balance IS 'Paid credits available (1 credit = 1 user-round = $0.01)';
COMMENT ON COLUMN public.user_credits.free_tier_used IS 'User-rounds used this month from free tier (resets monthly, max 500)';
COMMENT ON COLUMN public.user_credits.free_tier_reset_at IS 'When the free tier counter resets (start of next month)';

-- ============================================================================
-- STEP 2: Credit transactions table (audit log)
-- ============================================================================

CREATE TABLE public.credit_transactions (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('purchase', 'usage', 'refund', 'adjustment')),
    amount INTEGER NOT NULL, -- positive for credits added, negative for credits used
    balance_after INTEGER NOT NULL,
    description TEXT,
    -- For purchases
    stripe_payment_intent_id TEXT,
    stripe_checkout_session_id TEXT,
    -- For usage
    chat_id INTEGER REFERENCES public.chats(id) ON DELETE SET NULL,
    round_id INTEGER REFERENCES public.rounds(id) ON DELETE SET NULL,
    user_round_count INTEGER, -- how many user-rounds this transaction represents
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for querying transaction history
CREATE INDEX idx_credit_transactions_user_id ON public.credit_transactions(user_id);
CREATE INDEX idx_credit_transactions_created_at ON public.credit_transactions(created_at);
CREATE INDEX idx_credit_transactions_stripe_session ON public.credit_transactions(stripe_checkout_session_id)
    WHERE stripe_checkout_session_id IS NOT NULL;

COMMENT ON TABLE public.credit_transactions IS 'Audit log of all credit transactions (purchases, usage, refunds)';

-- ============================================================================
-- STEP 3: Monthly usage tracking (aggregated for reporting)
-- ============================================================================

CREATE TABLE public.monthly_usage (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    month_start DATE NOT NULL, -- First day of the month
    total_user_rounds INTEGER NOT NULL DEFAULT 0,
    free_tier_user_rounds INTEGER NOT NULL DEFAULT 0,
    paid_user_rounds INTEGER NOT NULL DEFAULT 0,
    total_chats INTEGER NOT NULL DEFAULT 0,
    total_rounds INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, month_start)
);

CREATE INDEX idx_monthly_usage_user_month ON public.monthly_usage(user_id, month_start);

CREATE TRIGGER update_monthly_usage_updated_at
    BEFORE UPDATE ON public.monthly_usage
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE public.monthly_usage IS 'Aggregated monthly usage statistics per user';

-- ============================================================================
-- STEP 4: Constants
-- ============================================================================

-- Store billing constants in a config table for easy adjustment
CREATE TABLE public.billing_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.billing_config (key, value, description) VALUES
    ('free_tier_monthly_limit', '500', 'Free user-rounds per month for signed-in users'),
    ('credit_price_cents', '1', 'Price per credit in cents (1 credit = 1 user-round)'),
    ('anonymous_chat_max_minutes', '60', 'Maximum chat duration in minutes for anonymous hosts');

COMMENT ON TABLE public.billing_config IS 'Billing configuration constants';

-- ============================================================================
-- STEP 5: Function to get or create user credits record
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_or_create_user_credits(p_user_id UUID)
RETURNS public.user_credits
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits public.user_credits;
BEGIN
    -- Try to get existing record
    SELECT * INTO v_credits FROM public.user_credits WHERE user_id = p_user_id;

    -- If not found, create one
    IF v_credits.id IS NULL THEN
        INSERT INTO public.user_credits (user_id)
        VALUES (p_user_id)
        RETURNING * INTO v_credits;
    END IF;

    -- Check if free tier needs reset (new month)
    IF v_credits.free_tier_reset_at <= NOW() THEN
        UPDATE public.user_credits
        SET free_tier_used = 0,
            free_tier_reset_at = date_trunc('month', NOW()) + interval '1 month'
        WHERE id = v_credits.id
        RETURNING * INTO v_credits;
    END IF;

    RETURN v_credits;
END;
$$;

COMMENT ON FUNCTION public.get_or_create_user_credits IS 'Gets user credits record, creating if needed, and resets free tier if new month';

-- ============================================================================
-- STEP 6: Function to check if user can afford user-rounds
-- ============================================================================

CREATE OR REPLACE FUNCTION public.can_afford_user_rounds(p_user_id UUID, p_user_round_count INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits public.user_credits;
    v_free_limit INTEGER;
    v_free_remaining INTEGER;
    v_needed_from_paid INTEGER;
BEGIN
    -- Get user credits (creates if needed, resets free tier if new month)
    v_credits := get_or_create_user_credits(p_user_id);

    -- Get free tier limit from config
    SELECT value::INTEGER INTO v_free_limit
    FROM public.billing_config
    WHERE key = 'free_tier_monthly_limit';

    -- Calculate remaining free tier
    v_free_remaining := GREATEST(0, v_free_limit - v_credits.free_tier_used);

    -- Calculate how many need to come from paid credits
    v_needed_from_paid := GREATEST(0, p_user_round_count - v_free_remaining);

    -- Can afford if we have enough paid credits
    RETURN v_credits.credit_balance >= v_needed_from_paid;
END;
$$;

COMMENT ON FUNCTION public.can_afford_user_rounds IS 'Checks if user has enough credits (free tier + paid) for given user-rounds';

-- ============================================================================
-- STEP 7: Function to deduct user-rounds (called when round completes)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.deduct_user_rounds(
    p_user_id UUID,
    p_user_round_count INTEGER,
    p_chat_id INTEGER,
    p_round_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits public.user_credits;
    v_free_limit INTEGER;
    v_free_remaining INTEGER;
    v_from_free INTEGER;
    v_from_paid INTEGER;
    v_month_start DATE;
BEGIN
    -- Check if can afford
    IF NOT can_afford_user_rounds(p_user_id, p_user_round_count) THEN
        RETURN FALSE;
    END IF;

    -- Get user credits
    v_credits := get_or_create_user_credits(p_user_id);

    -- Get free tier limit
    SELECT value::INTEGER INTO v_free_limit
    FROM public.billing_config
    WHERE key = 'free_tier_monthly_limit';

    -- Calculate split between free and paid
    v_free_remaining := GREATEST(0, v_free_limit - v_credits.free_tier_used);
    v_from_free := LEAST(p_user_round_count, v_free_remaining);
    v_from_paid := p_user_round_count - v_from_free;

    -- Update user credits
    UPDATE public.user_credits
    SET free_tier_used = free_tier_used + v_from_free,
        credit_balance = credit_balance - v_from_paid
    WHERE id = v_credits.id
    RETURNING * INTO v_credits;

    -- Record transaction if paid credits used
    IF v_from_paid > 0 THEN
        INSERT INTO public.credit_transactions (
            user_id, transaction_type, amount, balance_after,
            description, chat_id, round_id, user_round_count
        ) VALUES (
            p_user_id, 'usage', -v_from_paid, v_credits.credit_balance,
            format('Used %s paid credits for %s user-rounds', v_from_paid, p_user_round_count),
            p_chat_id, p_round_id, p_user_round_count
        );
    END IF;

    -- Update monthly usage
    v_month_start := date_trunc('month', NOW())::DATE;

    INSERT INTO public.monthly_usage (
        user_id, month_start, total_user_rounds, free_tier_user_rounds,
        paid_user_rounds, total_rounds
    ) VALUES (
        p_user_id, v_month_start, p_user_round_count, v_from_free,
        v_from_paid, 1
    )
    ON CONFLICT (user_id, month_start) DO UPDATE SET
        total_user_rounds = monthly_usage.total_user_rounds + p_user_round_count,
        free_tier_user_rounds = monthly_usage.free_tier_user_rounds + v_from_free,
        paid_user_rounds = monthly_usage.paid_user_rounds + v_from_paid,
        total_rounds = monthly_usage.total_rounds + 1;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.deduct_user_rounds IS 'Deducts user-rounds from free tier first, then paid credits. Returns false if insufficient.';

-- ============================================================================
-- STEP 8: Function to add purchased credits
-- ============================================================================

CREATE OR REPLACE FUNCTION public.add_purchased_credits(
    p_user_id UUID,
    p_credit_amount INTEGER,
    p_stripe_checkout_session_id TEXT,
    p_stripe_payment_intent_id TEXT DEFAULT NULL
)
RETURNS public.user_credits
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_credits public.user_credits;
    v_existing_tx INT;
BEGIN
    -- Check for existing transaction with same checkout session (idempotency)
    IF p_stripe_checkout_session_id IS NOT NULL THEN
        SELECT id INTO v_existing_tx
        FROM public.credit_transactions
        WHERE stripe_checkout_session_id = p_stripe_checkout_session_id
        LIMIT 1;

        IF v_existing_tx IS NOT NULL THEN
            -- Already processed, return current credits without adding
            SELECT * INTO v_credits
            FROM public.user_credits
            WHERE user_id = p_user_id;

            RETURN v_credits;
        END IF;
    END IF;

    -- Get or create user credits
    v_credits := get_or_create_user_credits(p_user_id);

    -- Add credits
    UPDATE public.user_credits
    SET credit_balance = credit_balance + p_credit_amount
    WHERE id = v_credits.id
    RETURNING * INTO v_credits;

    -- Record transaction
    INSERT INTO public.credit_transactions (
        user_id, transaction_type, amount, balance_after,
        description, stripe_checkout_session_id, stripe_payment_intent_id
    ) VALUES (
        p_user_id, 'purchase', p_credit_amount, v_credits.credit_balance,
        format('Purchased %s credits', p_credit_amount),
        p_stripe_checkout_session_id, p_stripe_payment_intent_id
    );

    RETURN v_credits;
END;
$$;

COMMENT ON FUNCTION public.add_purchased_credits IS 'Adds purchased credits to user balance. Idempotent - same session ID will only add credits once.';

-- ============================================================================
-- STEP 9: Enforce 1-hour max for anonymous host chats
-- ============================================================================

-- Add column to track if host was anonymous at creation
ALTER TABLE public.chats
ADD COLUMN IF NOT EXISTS host_was_anonymous BOOLEAN DEFAULT FALSE;

-- Update the existing expiration trigger function to use billing config
-- Original function set 7 days for anonymous hosts, now we use the configurable value
CREATE OR REPLACE FUNCTION public.on_chat_insert_set_expiration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_max_minutes INTEGER;
BEGIN
    -- Only process if creator is anonymous (has session token but no user ID)
    IF NEW.creator_id IS NULL AND NEW.creator_session_token IS NOT NULL THEN
        NEW.host_was_anonymous := TRUE;

        -- Get max duration from config (defaults to 60 minutes)
        SELECT COALESCE(value::INTEGER, 60) INTO v_max_minutes
        FROM public.billing_config
        WHERE key = 'anonymous_chat_max_minutes';

        -- Fallback if config doesn't exist
        IF v_max_minutes IS NULL THEN
            v_max_minutes := 60;
        END IF;

        -- Set expiry to max duration from now
        NEW.expires_at := NOW() + (v_max_minutes || ' minutes')::INTERVAL;
    END IF;

    RETURN NEW;
END;
$$;

-- Drop our new trigger since we updated the existing function
DROP TRIGGER IF EXISTS set_anonymous_chat_expiry_trigger ON public.chats;

COMMENT ON COLUMN public.chats.host_was_anonymous IS 'True if chat was created by anonymous (non-signed-in) host';
COMMENT ON FUNCTION public.on_chat_insert_set_expiration IS 'Sets expiry for chats created by anonymous hosts (default 1 hour)';

-- ============================================================================
-- STEP 10: RLS Policies
-- ============================================================================

ALTER TABLE public.user_credits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_config ENABLE ROW LEVEL SECURITY;

-- User credits: users can only see their own
CREATE POLICY "Users can view own credits"
    ON public.user_credits FOR SELECT
    USING (auth.uid() = user_id);

-- Credit transactions: users can only see their own
CREATE POLICY "Users can view own transactions"
    ON public.credit_transactions FOR SELECT
    USING (auth.uid() = user_id);

-- Monthly usage: users can only see their own
CREATE POLICY "Users can view own usage"
    ON public.monthly_usage FOR SELECT
    USING (auth.uid() = user_id);

-- Billing config: readable by all authenticated users
CREATE POLICY "Authenticated users can view billing config"
    ON public.billing_config FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- STEP 11: Indexes for performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_chats_host_was_anonymous
    ON public.chats(host_was_anonymous)
    WHERE host_was_anonymous = TRUE;

CREATE INDEX IF NOT EXISTS idx_chats_expires_at
    ON public.chats(expires_at)
    WHERE expires_at IS NOT NULL;

-- ============================================================================
-- STEP 12: Usage tracking trigger on round completion
-- ============================================================================

-- Function to track usage when a round gets a winner (completes)
CREATE OR REPLACE FUNCTION public.on_round_winner_track_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_host_user_id UUID;
BEGIN
    -- Only trigger when winning_proposition_id is set (round completed)
    IF NEW.winning_proposition_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip if already had a winner (update case)
    IF OLD.winning_proposition_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Get the chat for this round
    SELECT c.* INTO v_chat
    FROM public.chats c
    JOIN public.cycles cy ON cy.chat_id = c.id
    WHERE cy.id = NEW.cycle_id;

    IF v_chat.id IS NULL THEN
        RETURN NEW;
    END IF;

    -- If host was anonymous, no usage tracking (already limited by expiry)
    IF v_chat.host_was_anonymous OR v_chat.creator_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_host_user_id := v_chat.creator_id;

    -- Count active participants in this round
    SELECT COUNT(DISTINCT p.session_token) INTO v_participant_count
    FROM public.propositions p
    WHERE p.round_id = NEW.id;

    -- Also count raters who didn't propose
    SELECT v_participant_count + COUNT(DISTINCT r.session_token) INTO v_participant_count
    FROM public.ratings r
    JOIN public.propositions prop ON r.proposition_id = prop.id
    WHERE prop.round_id = NEW.id
      AND r.session_token NOT IN (
          SELECT DISTINCT p2.session_token
          FROM public.propositions p2
          WHERE p2.round_id = NEW.id
      );

    -- Minimum 1 user-round even if no participants recorded
    IF v_participant_count < 1 THEN
        v_participant_count := 1;
    END IF;

    -- Deduct user-rounds from host's account
    -- Note: This will fail silently if host can't afford it
    -- The actual blocking should happen before allowing new rounds
    PERFORM deduct_user_rounds(
        v_host_user_id,
        v_participant_count,
        v_chat.id,
        NEW.id
    );

    RETURN NEW;
END;
$$;

-- Trigger on round winner being set
CREATE TRIGGER trg_round_winner_track_usage
    AFTER UPDATE ON public.rounds
    FOR EACH ROW
    WHEN (NEW.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id IS NULL)
    EXECUTE FUNCTION on_round_winner_track_usage();

COMMENT ON FUNCTION public.on_round_winner_track_usage IS 'Tracks usage (user-rounds) when a round completes and deducts from host credits';

