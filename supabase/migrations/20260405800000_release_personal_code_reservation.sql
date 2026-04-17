-- Add RPC for users to release their own personal code reservation
-- Called when the user dismisses the join dialog without joining.

CREATE OR REPLACE FUNCTION public.release_personal_code_reservation(p_code TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Only release if reserved by this user and not yet used
    UPDATE personal_codes
    SET reserved_by = NULL, reserved_at = NULL
    WHERE code = UPPER(p_code)
      AND reserved_by = v_user_id
      AND used_at IS NULL
      AND revoked_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.release_personal_code_reservation(TEXT) TO anon, authenticated;

COMMENT ON FUNCTION public.release_personal_code_reservation(TEXT) IS
'Release a personal code reservation. Called when user backs out of the join dialog without joining.';
