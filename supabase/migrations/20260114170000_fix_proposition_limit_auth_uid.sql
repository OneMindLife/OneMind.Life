-- Fix proposition limit trigger to use auth.uid() instead of session token
-- After auth migration, get_session_token() returns NULL, bypassing the limit check

CREATE OR REPLACE FUNCTION enforce_proposition_limit()
RETURNS TRIGGER AS $$
DECLARE
    current_count INTEGER;
    max_allowed INTEGER;
BEGIN
    -- Skip check for service role (edge functions, tests)
    IF current_setting('role', true) = 'service_role' THEN
        RETURN NEW;
    END IF;

    -- Skip if no authenticated user (direct DB access, migrations)
    IF auth.uid() IS NULL THEN
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION enforce_proposition_limit() IS 
'Enforces propositions_per_user limit. Updated to use auth.uid() after auth migration.';
