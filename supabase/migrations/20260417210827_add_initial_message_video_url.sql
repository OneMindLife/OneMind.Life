-- Add initial_message_video_url to chats for per-chat initial-message videos.
-- Videos are uploaded manually (no auto-generation trigger).

ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS initial_message_video_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('initial-message-videos', 'initial-message-videos', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'objects' AND policyname = 'Public read access for initial message videos'
  ) THEN
    CREATE POLICY "Public read access for initial message videos"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'initial-message-videos');
  END IF;
END $$;
