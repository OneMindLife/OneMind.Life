-- =============================================================================
-- MIGRATION: Add propositions_per_user setting
-- =============================================================================
-- Allows chat hosts to configure how many propositions each participant can
-- submit per round. Default is 1 (current behavior).
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Add column to chats table
-- =============================================================================

ALTER TABLE public.chats
ADD COLUMN IF NOT EXISTS propositions_per_user INTEGER NOT NULL DEFAULT 1
CONSTRAINT chk_propositions_per_user CHECK (propositions_per_user >= 1);

COMMENT ON COLUMN public.chats.propositions_per_user IS
'Maximum number of propositions each participant can submit per round. Default is 1.';

-- =============================================================================
-- STEP 2: Create function to count participant propositions in a round
-- =============================================================================

CREATE OR REPLACE FUNCTION public.count_participant_propositions_in_round(
    p_participant_id BIGINT,
    p_round_id BIGINT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    prop_count INTEGER;
BEGIN
    SELECT COUNT(*)::INTEGER INTO prop_count
    FROM propositions
    WHERE participant_id = p_participant_id
      AND round_id = p_round_id;

    RETURN COALESCE(prop_count, 0);
END;
$$;

-- =============================================================================
-- STEP 3: Create function to get max propositions allowed for a round
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_propositions_limit_for_round(
    p_round_id BIGINT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    limit_val INTEGER;
BEGIN
    SELECT ch.propositions_per_user INTO limit_val
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    JOIN chats ch ON ch.id = c.chat_id
    WHERE r.id = p_round_id;

    RETURN COALESCE(limit_val, 1);
END;
$$;

-- =============================================================================
-- STEP 4: Create trigger to enforce proposition limit
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_proposition_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    current_count INTEGER;
    max_allowed INTEGER;
BEGIN
    -- Skip check for service role (edge functions, tests)
    IF current_setting('role', true) = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Skip if no session token (tests, direct DB access)
    IF public.get_session_token() IS NULL THEN
        RETURN NEW;
    END IF;

    -- Get current count (excluding this new one)
    current_count := public.count_participant_propositions_in_round(
        NEW.participant_id,
        NEW.round_id
    );

    -- Get max allowed
    max_allowed := public.get_propositions_limit_for_round(NEW.round_id);

    -- Check if limit exceeded
    IF current_count >= max_allowed THEN
        RAISE EXCEPTION 'Proposition limit exceeded. Maximum % proposition(s) per round.', max_allowed
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

-- Create trigger (runs before rate limit trigger)
DROP TRIGGER IF EXISTS trg_proposition_limit ON public.propositions;
CREATE TRIGGER trg_proposition_limit
BEFORE INSERT ON public.propositions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_proposition_limit();

-- =============================================================================
-- STEP 5: Grant permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.count_participant_propositions_in_round(BIGINT, BIGINT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_propositions_limit_for_round(BIGINT) TO anon, authenticated, service_role;

COMMIT;
