ALTER TABLE public.cycles
ADD COLUMN IF NOT EXISTS audio_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('cycle-audio', 'cycle-audio', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'objects' AND policyname = 'Public read access for cycle audio'
  ) THEN
    CREATE POLICY "Public read access for cycle audio"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'cycle-audio');
  END IF;
END $$;
