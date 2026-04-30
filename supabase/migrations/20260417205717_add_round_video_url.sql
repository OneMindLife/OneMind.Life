-- Add video_url to rounds for per-round winner videos (official chats).
-- Unlike audio, videos are uploaded manually (no auto-generation trigger yet).

ALTER TABLE public.rounds ADD COLUMN IF NOT EXISTS video_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('round-videos', 'round-videos', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'objects' AND policyname = 'Public read access for round videos'
  ) THEN
    CREATE POLICY "Public read access for round videos"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'round-videos');
  END IF;
END $$;
