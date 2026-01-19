-- Generate invite codes for public and code-based chats (not invite_only)
-- Public chats get codes as a convenience shortcut for sharing

CREATE OR REPLACE FUNCTION public.on_chat_insert_set_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    new_code CHAR(6);
    attempts INT := 0;
BEGIN
    -- Generate code for public and code-based chats (not invite_only)
    IF NEW.access_method IN ('public', 'code') AND NEW.invite_code IS NULL THEN
        LOOP
            new_code := generate_invite_code();
            BEGIN
                NEW.invite_code := new_code;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                attempts := attempts + 1;
                IF attempts > 10 THEN
                    RAISE EXCEPTION 'Could not generate unique invite code';
                END IF;
            END;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

-- Generate codes for existing public chats that don't have one
UPDATE public.chats
SET invite_code = generate_invite_code()
WHERE access_method = 'public' AND invite_code IS NULL;
