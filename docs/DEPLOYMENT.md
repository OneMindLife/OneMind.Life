# Deployment Guide

This document describes how to deploy OneMind to production with a remote Supabase backend.

---

## Prerequisites

- Supabase CLI installed (`npm install -g supabase`)
- Supabase account with a project created
- Flutter SDK installed
- (Optional) Resend account for email invites

---

## 1. Supabase Project Setup

### 1.1 Login to Supabase CLI

```bash
npx supabase login
```

### 1.2 Link to Your Project

```bash
# List available projects
npx supabase projects list

# Link to your project (replace with your project ref)
npx supabase link --project-ref YOUR_PROJECT_REF
```

**Current linked project:** `ccyuxrtrklgpkzcryzpj` (OneMind SaaS)

---

## 2. Database Setup

### 2.1 Push Migrations to Remote

```bash
# Push all migrations to remote database
npx supabase db push
```

This applies all migrations from `supabase/migrations/` to your remote database.

### 2.2 Verify Migration Status

```bash
# Check which migrations have been applied
npx supabase migration list
```

---

## 3. Edge Functions Deployment

### 3.1 Deploy All Functions

```bash
# Deploy most functions (with JWT verification)
npx supabase functions deploy

# Deploy functions WITHOUT JWT verification (they handle their own auth)
# These are called by cron jobs, webhooks, or database triggers
npx supabase functions deploy process-timers --no-verify-jwt
npx supabase functions deploy process-auto-refill --no-verify-jwt
npx supabase functions deploy translate --no-verify-jwt
npx supabase functions deploy stripe-webhook --no-verify-jwt
npx supabase functions deploy health --no-verify-jwt
```

**Important:** These functions must be deployed with `--no-verify-jwt` because:
- `process-timers` / `process-auto-refill`: Called by database cron jobs using X-Cron-Secret
- `translate`: Called by database triggers using service role key from vault
- `stripe-webhook`: Called by Stripe with webhook signature verification
- `health`: Public health check endpoint for deployment verification

All these functions implement their own authentication internally.

This deploys all functions from `supabase/functions/`.

### 3.2 Set Function Secrets

Edge Functions need these secrets:

| Secret | Required | Description |
|--------|----------|-------------|
| `CRON_SECRET` | Yes | Auth for cron job requests (must match cron job header) |
| `STRIPE_SECRET_KEY` | Yes | Stripe API key for payment processing |
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for AI translations |
| `RESEND_API_KEY` | Optional | For sending invite emails |

```bash
# Set secrets via CLI
npx supabase secrets set CRON_SECRET="your-secret-here"
npx supabase secrets set STRIPE_SECRET_KEY="sk_live_xxx"
npx supabase secrets set ANTHROPIC_API_KEY="sk-ant-xxx"
npx supabase secrets set RESEND_API_KEY="re_xxxxx"

# Or set via Supabase Dashboard:
# Project Settings > Edge Functions > Manage Secrets

# Verify secrets are set
npx supabase secrets list

# Verify health check passes
curl https://YOUR_PROJECT.supabase.co/functions/v1/health
```

### 3.3 Set Vault Secret for Database Triggers

The `translate` function is called by database triggers via `pg_net`. These triggers read the service role key from Supabase Vault.

**Important:** The vault must contain the **legacy JWT service role key** (starts with `eyJ...`), NOT the new `sb_secret_...` format.

```sql
-- Run in Supabase SQL Editor to set/update the vault secret
-- First, check if it exists:
SELECT name FROM vault.secrets WHERE name = 'edge_function_service_key';

-- To insert (if doesn't exist):
INSERT INTO vault.secrets (name, secret)
VALUES ('edge_function_service_key', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...');

-- Or update via Dashboard: Project Settings > Vault > Add/Edit Secret
```

Get the JWT service role key from: Dashboard > Settings > API > Service Role Key (the long `eyJ...` token)

---

## 4. Cron Jobs Setup

Two Edge Functions need to be called every minute by cron jobs:
- `process-timers`: Handles phase advancement, winner calculation, auto-start
- `process-auto-refill`: Processes automatic credit refills

### 4.1 Configure Cron Jobs in Database

Run this SQL in the Supabase SQL Editor (Dashboard > SQL Editor > New query):

**Dashboard URL:** https://supabase.com/dashboard/project/ccyuxrtrklgpkzcryzpj/sql/new

```sql
-- ============================================
-- CONFIGURE CRON JOBS FOR PRODUCTION
-- ============================================

-- 1. Remove existing jobs if any
SELECT cron.unschedule('process-timers');
SELECT cron.unschedule('process-auto-refills');

-- 2. Create process-timers cron job
SELECT cron.schedule(
    'process-timers',
    '* * * * *',  -- Every minute
    $$
    SELECT net.http_post(
        url := 'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/process-timers',
        headers := '{"Content-Type": "application/json", "X-Cron-Secret": "YOUR_CRON_SECRET_HERE"}'::jsonb,
        body := '{}'::jsonb
    );
    $$
);

-- 3. Create process-auto-refills cron job
SELECT cron.schedule(
    'process-auto-refills',
    '* * * * *',  -- Every minute
    $$
    SELECT net.http_post(
        url := 'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/process-auto-refill',
        headers := '{"Content-Type": "application/json", "X-Cron-Secret": "YOUR_CRON_SECRET_HERE"}'::jsonb,
        body := '{}'::jsonb
    );
    $$
);

-- 4. Verify the jobs were created
SELECT jobname, schedule FROM cron.job WHERE jobname IN ('process-timers', 'process-auto-refills');
```

**Important:**
- Replace `YOUR_CRON_SECRET_HERE` with the CRON_SECRET you set in step 3.2
- The X-Cron-Secret header value MUST exactly match the CRON_SECRET Edge Function secret

Current CRON_SECRET (set 2026-01-18): `855dd968210a46ed2334a6281b016a94ce4fb56bfc496851`

---

## 5. Get Production Credentials

### 5.1 From Supabase Dashboard

Go to **Supabase Dashboard > Settings > API**:

- **Project URL**: `https://YOUR_PROJECT_REF.supabase.co`
- **Anon/Public Key**: The `anon` key (safe to expose in client apps)

### 5.2 Via CLI

```bash
# Get project API settings
npx supabase status --linked
```

---

## 6. Flutter App Configuration

### 6.1 Build with Production Credentials

```bash
# Android APK
flutter build apk \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENVIRONMENT=production

# Android App Bundle (for Play Store)
flutter build appbundle \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENVIRONMENT=production

# iOS
flutter build ios \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENVIRONMENT=production

# Web
flutter build web \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENVIRONMENT=production
```

### 6.2 Run Locally with Production Backend (Testing)

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ENVIRONMENT=staging
```

---

## 7. Verification Checklist

After deployment, verify:

- [ ] Migrations applied: `npx supabase migration list` shows all migrations
- [ ] Edge Functions deployed: `npx supabase functions list`
- [ ] Secrets set: `npx supabase secrets list`
- [ ] Vault secret configured: Check `edge_function_service_key` exists (see 3.3)
- [ ] Cron job running: Check `cron.job_run_details` table in SQL Editor
- [ ] Translations working: Create a chat and verify translations appear
- [ ] App connects: Run Flutter app with production credentials

### Test the Cron Job

```sql
-- Check recent cron executions (use cron_execution_log, not cron.job_run_details)
SELECT id, job_name, started_at, completed_at, status, result_code, error_message
FROM cron_execution_log
WHERE job_name = 'process-timers'
ORDER BY started_at DESC
LIMIT 10;
```

Or via REST API (useful for scripting):
```bash
curl -s "https://YOUR_PROJECT_REF.supabase.co/rest/v1/cron_execution_log?job_name=eq.process-timers&order=started_at.desc&limit=5" \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
```

---

## Troubleshooting

### Migrations fail to push

```bash
# Check for conflicts
npx supabase db diff --linked

# Reset remote (DANGEROUS - deletes all data)
npx supabase db reset --linked
```

### Edge Function errors

View logs in the Supabase Dashboard:
https://supabase.com/dashboard/project/YOUR_PROJECT_REF/functions

Or test the function directly:
```bash
curl -s -X POST "https://YOUR_PROJECT_REF.supabase.co/functions/v1/process-timers" \
  -H "Content-Type: application/json" \
  -H "X-Cron-Secret: YOUR_CRON_SECRET" \
  -d '{}'
```

### Cron job not running

1. Verify pg_cron extension is enabled
2. Check the job exists: `SELECT jobname, schedule FROM cron.job;`
3. Check job history: `SELECT * FROM cron_execution_log ORDER BY started_at DESC LIMIT 10;`
4. Verify CRON_SECRET matches between DB cron job and Edge Function secrets
5. Verify function deployed with `--no-verify-jwt` flag

---

## Environment Summary

| Environment | Supabase URL | Notes |
|-------------|--------------|-------|
| Local Dev | `http://127.0.0.1:54321` | `npx supabase start` |
| Production | `https://ccyuxrtrklgpkzcryzpj.supabase.co` | Linked project |

### Production Credentials (OneMind SaaS)

```bash
# Project Reference
PROJECT_REF=ccyuxrtrklgpkzcryzpj

# Supabase URL
SUPABASE_URL=https://ccyuxrtrklgpkzcryzpj.supabase.co

# Anon Key (safe for client apps)
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjeXV4cnRya2xncGt6Y3J5enBqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkzOTksImV4cCI6MjA4MzU2NTM5OX0.RR7W2SZD7BS9y3-I1YpyfB550fb0ZckduN-814RqycE

# Run Flutter with production backend
flutter run \
  --dart-define=SUPABASE_URL=https://ccyuxrtrklgpkzcryzpj.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjeXV4cnRya2xncGt6Y3J5enBqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkzOTksImV4cCI6MjA4MzU2NTM5OX0.RR7W2SZD7BS9y3-I1YpyfB550fb0ZckduN-814RqycE \
  --dart-define=ENVIRONMENT=production
```

---

## Quick Reference Commands

```bash
# Start local Supabase
npx supabase start

# Push migrations to remote
npx supabase db push

# Deploy functions to remote
npx supabase functions deploy

# Set a secret
npx supabase secrets set KEY="value"

# View function logs
npx supabase functions logs FUNCTION_NAME --linked

# Check migration status
npx supabase migration list
```
