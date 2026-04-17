-- Migration: Automatic personal code lifecycle management
-- When a user joins a personal_code chat (directly or via approval),
-- their reserved code is automatically marked as used.
-- When a join request is cancelled or denied, the reservation is cleared.

-- ============================================================================
-- STEP 1: Mark personal code as used when participant joins a personal_code chat
-- Fires on INSERT into participants for personal_code chats.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.on_participant_join_mark_code_used()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Only for active participants (not pending)
    IF NEW.status != 'active' THEN
        RETURN NEW;
    END IF;

    -- Only for personal_code chats
    IF NOT EXISTS (
        SELECT 1 FROM chats
        WHERE id = NEW.chat_id
        AND access_method = 'personal_code'
    ) THEN
        RETURN NEW;
    END IF;

    -- Mark the reserved code as used (if this user has one reserved)
    UPDATE personal_codes
    SET used_by = NEW.user_id,
        used_at = NOW(),
        reserved_by = NULL,
        reserved_at = NULL
    WHERE chat_id = NEW.chat_id
      AND reserved_by = NEW.user_id
      AND used_at IS NULL
      AND revoked_at IS NULL;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_participant_join_mark_code
    AFTER INSERT ON participants
    FOR EACH ROW
    EXECUTE FUNCTION on_participant_join_mark_code_used();

-- ============================================================================
-- STEP 2: Mark personal code as used when join request is approved
-- The approve_join_request function inserts a participant (which fires
-- the trigger above). But if the participant already existed (reactivated
-- from kicked/left), the INSERT trigger won't fire. Handle that here.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.on_join_request_resolved_update_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Only fire on status changes
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    -- Only for personal_code chats
    IF NOT EXISTS (
        SELECT 1 FROM chats
        WHERE id = NEW.chat_id
        AND access_method = 'personal_code'
    ) THEN
        RETURN NEW;
    END IF;

    IF NEW.status = 'approved' THEN
        -- Mark the reserved code as used
        UPDATE personal_codes
        SET used_by = NEW.user_id,
            used_at = NOW(),
            reserved_by = NULL,
            reserved_at = NULL
        WHERE chat_id = NEW.chat_id
          AND reserved_by = NEW.user_id
          AND used_at IS NULL
          AND revoked_at IS NULL;

    ELSIF NEW.status IN ('cancelled', 'denied') THEN
        -- Clear the reservation so the code becomes available again
        UPDATE personal_codes
        SET reserved_by = NULL,
            reserved_at = NULL
        WHERE chat_id = NEW.chat_id
          AND reserved_by = NEW.user_id
          AND used_at IS NULL
          AND revoked_at IS NULL;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_join_request_resolved_code
    AFTER UPDATE ON join_requests
    FOR EACH ROW
    EXECUTE FUNCTION on_join_request_resolved_update_code();

-- ============================================================================
-- STEP 3: Also handle participant status change back to active
-- (e.g. reactivating a kicked participant via approve_join_request)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.on_participant_reactivate_mark_code_used()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Only when changing TO active from something else
    IF NEW.status != 'active' OR OLD.status = 'active' THEN
        RETURN NEW;
    END IF;

    -- Only for personal_code chats
    IF NOT EXISTS (
        SELECT 1 FROM chats
        WHERE id = NEW.chat_id
        AND access_method = 'personal_code'
    ) THEN
        RETURN NEW;
    END IF;

    -- Mark the reserved code as used
    UPDATE personal_codes
    SET used_by = NEW.user_id,
        used_at = NOW(),
        reserved_by = NULL,
        reserved_at = NULL
    WHERE chat_id = NEW.chat_id
      AND reserved_by = NEW.user_id
      AND used_at IS NULL
      AND revoked_at IS NULL;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_participant_reactivate_mark_code
    AFTER UPDATE ON participants
    FOR EACH ROW
    EXECUTE FUNCTION on_participant_reactivate_mark_code_used();

-- ============================================================================
-- STEP 4: Comments
-- ============================================================================

COMMENT ON FUNCTION on_participant_join_mark_code_used() IS
'Marks the personal code as used when a user joins a personal_code chat directly.';

COMMENT ON FUNCTION on_join_request_resolved_update_code() IS
'On approval: marks code used. On cancel/deny: clears reservation so code is available again.';

COMMENT ON FUNCTION on_participant_reactivate_mark_code_used() IS
'Marks code used when a kicked/left participant is reactivated in a personal_code chat.';
