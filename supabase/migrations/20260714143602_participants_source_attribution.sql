-- First-touch acquisition source on participants.
-- The wedge stamps this at join time from the client's `_om_attr` sessionStorage
-- (captured by analytics.tsx on first landing): telegram / google_ads /
-- meta_ad / utm_<source> / invite / organic_search / referral / direct.
-- Makes "which channel did this proposer/voter actually come from?" a plain
-- SQL join instead of a PostHog cross-reference. Nullable, best-effort.
ALTER TABLE public.participants ADD COLUMN IF NOT EXISTS source TEXT;

COMMENT ON COLUMN public.participants.source IS
  'First-touch acquisition source stamped by the wedge at join time (from _om_attr sessionStorage). Values: telegram, google_ads, meta_ad, utm_<source>, invite, organic_search, referral, direct. Nullable/best-effort.';
