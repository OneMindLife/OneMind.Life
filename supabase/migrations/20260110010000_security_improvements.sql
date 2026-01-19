-- =============================================================================
-- MIGRATION: Security Improvements
-- =============================================================================
-- This migration:
-- 1. Creates helper function to get session token from request headers
-- 2. Updates RLS policies to validate participant ownership
-- 3. Adds performance indexes
-- 4. Adds rate limiting helper function
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Create helper function to extract session token from headers
-- =============================================================================

-- Function to get session token from request headers
-- Clients must pass X-Session-Token header with their session UUID
CREATE OR REPLACE FUNCTION public.get_session_token()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    headers JSON;
    token TEXT;
BEGIN
    -- Get headers from request context
    BEGIN
        headers := current_setting('request.headers', true)::JSON;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;

    -- Try to get session token from header (case-insensitive)
    token := COALESCE(
        headers->>'x-session-token',
        headers->>'X-Session-Token'
    );

    IF token IS NULL OR token = '' THEN
        RETURN NULL;
    END IF;

    -- Validate it's a proper UUID
    BEGIN
        RETURN token::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;
END;
$$;

-- Function to check if current request owns a participant
CREATE OR REPLACE FUNCTION public.owns_participant(p_participant_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    session_token UUID;
    participant_token UUID;
BEGIN
    session_token := public.get_session_token();

    IF session_token IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT p.session_token INTO participant_token
    FROM participants p
    WHERE p.id = p_participant_id;

    RETURN session_token = participant_token;
END;
$$;

-- =============================================================================
-- STEP 2: Update RLS policies for propositions
-- =============================================================================

-- Drop existing permissive policy
DROP POLICY IF EXISTS "Anyone can create propositions" ON "public"."propositions";

-- Create new policy that validates ownership
-- Allow insert if the participant_id belongs to the session token in headers
-- OR if it's the service role (for edge functions)
CREATE POLICY "Participants can create own propositions" ON "public"."propositions"
FOR INSERT
WITH CHECK (
    -- Service role can always insert (for edge functions)
    (current_setting('role', true) = 'service_role')
    OR
    -- User must own the participant
    public.owns_participant(participant_id)
);

-- =============================================================================
-- STEP 3: Update RLS policies for ratings
-- =============================================================================

-- Drop existing permissive policy
DROP POLICY IF EXISTS "Anyone can submit ratings" ON "public"."ratings";

-- Create new policy that validates ownership
CREATE POLICY "Participants can submit own ratings" ON "public"."ratings"
FOR INSERT
WITH CHECK (
    -- Service role can always insert
    (current_setting('role', true) = 'service_role')
    OR
    -- User must own the participant
    public.owns_participant(participant_id)
);

-- =============================================================================
-- STEP 4: Update RLS policies for participants (join chat)
-- =============================================================================

-- Drop existing permissive policy
DROP POLICY IF EXISTS "Anyone can join chats" ON "public"."participants";

-- Create new policy - session token must match what's being inserted
CREATE POLICY "Users can join with own session" ON "public"."participants"
FOR INSERT
WITH CHECK (
    -- Service role can always insert
    (current_setting('role', true) = 'service_role')
    OR
    -- Session token in record must match request header
    (session_token = public.get_session_token())
);

-- =============================================================================
-- STEP 5: Add performance indexes
-- =============================================================================

-- Index for finding active rounds by phase (used by process-timers)
CREATE INDEX IF NOT EXISTS idx_rounds_phase
ON public.rounds(phase)
WHERE completed_at IS NULL;

-- Index for finding expired timers
CREATE INDEX IF NOT EXISTS idx_rounds_phase_ends_at
ON public.rounds(phase_ends_at)
WHERE phase_ends_at IS NOT NULL AND completed_at IS NULL;

-- Index for counting active participants
CREATE INDEX IF NOT EXISTS idx_participants_chat_status
ON public.participants(chat_id, status)
WHERE status = 'active';

-- Index for finding propositions by round
CREATE INDEX IF NOT EXISTS idx_propositions_round
ON public.propositions(round_id);

-- Index for finding ratings by proposition
CREATE INDEX IF NOT EXISTS idx_ratings_proposition
ON public.ratings(proposition_id);

-- =============================================================================
-- STEP 6: Rate limiting helper (tracks last action time per session)
-- =============================================================================

-- Create rate limit tracking table
CREATE TABLE IF NOT EXISTS public.rate_limits (
    id BIGSERIAL PRIMARY KEY,
    session_token UUID NOT NULL,
    action_type TEXT NOT NULL,
    last_action_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    action_count INTEGER NOT NULL DEFAULT 1,
    window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(session_token, action_type)
);

-- Enable RLS
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

-- Only service role can manage rate limits
CREATE POLICY "Service role manages rate limits" ON public.rate_limits
USING (current_setting('role', true) = 'service_role');

-- Function to check rate limit (returns true if allowed)
CREATE OR REPLACE FUNCTION public.check_rate_limit(
    p_action_type TEXT,
    p_max_per_minute INTEGER DEFAULT 10
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    session_token UUID;
    current_count INTEGER;
    window_start_time TIMESTAMPTZ;
BEGIN
    session_token := public.get_session_token();

    IF session_token IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Get or create rate limit record
    INSERT INTO rate_limits (session_token, action_type, last_action_at, action_count, window_start)
    VALUES (session_token, p_action_type, NOW(), 1, NOW())
    ON CONFLICT (session_token, action_type) DO UPDATE
    SET
        action_count = CASE
            WHEN rate_limits.window_start < NOW() - INTERVAL '1 minute'
            THEN 1  -- Reset count for new window
            ELSE rate_limits.action_count + 1
        END,
        window_start = CASE
            WHEN rate_limits.window_start < NOW() - INTERVAL '1 minute'
            THEN NOW()  -- Reset window
            ELSE rate_limits.window_start
        END,
        last_action_at = NOW()
    RETURNING action_count, window_start INTO current_count, window_start_time;

    -- Check if within limit
    RETURN current_count <= p_max_per_minute;
END;
$$;

-- =============================================================================
-- STEP 7: Add rate limit checks to propositions and ratings
-- =============================================================================

-- Create trigger function to enforce rate limits on propositions
CREATE OR REPLACE FUNCTION public.enforce_proposition_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Skip rate limit check for service role
    IF current_setting('role', true) = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Skip if no session token (tests, direct DB access)
    IF public.get_session_token() IS NULL THEN
        RETURN NEW;
    END IF;

    -- Check rate limit (10 propositions per minute)
    IF NOT public.check_rate_limit('proposition', 10) THEN
        RAISE EXCEPTION 'Rate limit exceeded for propositions'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proposition_rate_limit
BEFORE INSERT ON public.propositions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_proposition_rate_limit();

-- Create trigger function to enforce rate limits on ratings
CREATE OR REPLACE FUNCTION public.enforce_rating_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Skip rate limit check for service role
    IF current_setting('role', true) = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Skip if no session token (tests, direct DB access)
    IF public.get_session_token() IS NULL THEN
        RETURN NEW;
    END IF;

    -- Check rate limit (30 ratings per minute - higher since users rate multiple props)
    IF NOT public.check_rate_limit('rating', 30) THEN
        RAISE EXCEPTION 'Rate limit exceeded for ratings'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_rating_rate_limit
BEFORE INSERT ON public.ratings
FOR EACH ROW
EXECUTE FUNCTION public.enforce_rating_rate_limit();

-- =============================================================================
-- STEP 8: Grant permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.get_session_token() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.owns_participant(BIGINT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, INTEGER) TO anon, authenticated, service_role;

COMMIT;
