ALTER TABLE public.cycles
ADD COLUMN IF NOT EXISTS video_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('cycle-videos', 'cycle-videos', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'objects' AND policyname = 'Public read access for cycle videos'
  ) THEN
    CREATE POLICY "Public read access for cycle videos"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'cycle-videos');
  END IF;
END $$;
