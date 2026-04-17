-- FCM token storage for web push notifications
CREATE TABLE public.fcm_tokens (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  CONSTRAINT fcm_tokens_token_unique UNIQUE (token)
);

CREATE INDEX idx_fcm_tokens_user ON public.fcm_tokens (user_id);

ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Users can manage their own tokens
CREATE POLICY "Users can insert their own tokens"
  ON public.fcm_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own tokens"
  ON public.fcm_tokens FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own tokens"
  ON public.fcm_tokens FOR DELETE
  USING (auth.uid() = user_id);

-- Users can read their own tokens (needed for upsert)
CREATE POLICY "Users can read their own tokens"
  ON public.fcm_tokens FOR SELECT
  USING (auth.uid() = user_id);

-- Service role reads all tokens for sending
