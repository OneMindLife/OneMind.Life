-- Fix users_language_code_check to allow all 5 supported languages
-- Previously only allowed 'en' and 'es'
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_language_code_check;
ALTER TABLE public.users ADD CONSTRAINT users_language_code_check
  CHECK (language_code IN ('en', 'es', 'pt', 'fr', 'de'));

-- Add spoken_languages column for smart translation fallback
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS spoken_languages TEXT[] DEFAULT ARRAY['en']::TEXT[];

-- Update the RPC to validate all 5 languages
CREATE OR REPLACE FUNCTION public.update_user_language_code(p_language_code TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_language_code NOT IN ('en', 'es', 'pt', 'fr', 'de') THEN
    RAISE EXCEPTION 'Unsupported language code: %', p_language_code;
  END IF;
  UPDATE public.users
  SET language_code = p_language_code
  WHERE id = auth.uid();
END;
$$;

-- RPC to update spoken languages
CREATE OR REPLACE FUNCTION public.update_user_spoken_languages(p_languages TEXT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.users
  SET spoken_languages = p_languages
  WHERE id = auth.uid();
END;
$$;
