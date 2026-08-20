-- Add platform to fcm_tokens so the push sender can shape FCM messages
-- per platform:
--   * web     → data-only (service worker renders it; a `notification`
--               block would bypass the SW and double-display)
--   * android/ios → `notification` block (OS renders natively when the
--               app is backgrounded; data-only shows nothing on mobile)
-- Existing rows are all web tokens (mobile registration shipped with this
-- change), so the default backfills them correctly.
ALTER TABLE public.fcm_tokens
  ADD COLUMN platform text NOT NULL DEFAULT 'web';
