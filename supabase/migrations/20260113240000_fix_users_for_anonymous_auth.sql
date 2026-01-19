-- Fix users table to support anonymous authentication
-- Anonymous users don't have an email address

-- Make email nullable
ALTER TABLE public.users ALTER COLUMN email DROP NOT NULL;

-- Drop the unique constraint on email (allows multiple NULL emails)
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_email_key;

-- Add a partial unique index that only enforces uniqueness for non-null emails
CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_when_not_null
ON public.users (email)
WHERE email IS NOT NULL;

-- Update the trigger to handle anonymous users better
CREATE OR REPLACE FUNCTION on_auth_user_created()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, display_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,  -- Will be NULL for anonymous users
        COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.raw_user_meta_data->>'name'),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = COALESCE(EXCLUDED.email, users.email),
        display_name = COALESCE(EXCLUDED.display_name, users.display_name),
        avatar_url = COALESCE(EXCLUDED.avatar_url, users.avatar_url),
        last_seen_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
