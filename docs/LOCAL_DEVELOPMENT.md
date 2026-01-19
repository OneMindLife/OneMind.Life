# Local Development Guide

This document covers common issues and setup requirements for local development with Supabase.

---

## ⚠️ CRITICAL: Cron Jobs Don't Work After db reset

**The most common issue**: After `npx supabase db reset --local`, the cron jobs still point to **production** Edge Function URLs. This means:
- Phase timers won't advance automatically
- Timer extensions won't happen
- Auto-start won't trigger
- Everything appears to work until a timer expires

**Always run the setup script after db reset!**

---

## Quick Start After Database Reset

Run these commands after `npx supabase db reset --local`:

```bash
# 1. Setup local cron jobs (required for timed features)
psql "postgresql://postgres:postgres@localhost:54322/postgres" -f scripts/setup_local_cron.sql

# 2. Restart the Flutter app (full restart, not hot reload)
# This creates a fresh anonymous auth session
```

---

## Prerequisites

- Docker running (for Supabase local)
- `npx supabase start` completed
- Flutter app configured to use `http://localhost:54321`

---

## Database Reset

After running `npx supabase db reset --local`:

### Issue: "User must be signed in" or Auth Errors

**Cause:** App has cached JWT from before reset, but user no longer exists in `auth.users`.

**Solution:**
1. Full app restart (not just hot reload)
2. Or clear app data/cache
3. The app will automatically create a new anonymous session

---

## Cron Jobs for Edge Functions

### Issue: `process-timers` Not Running Locally

**Cause:** The cron job in the database points to the **production** Supabase URL, not localhost.

### Quick Fix (Recommended)

Run the setup script after database reset:
```bash
psql "postgresql://postgres:postgres@localhost:54322/postgres" -f scripts/setup_local_cron.sql
```

### Manual Fix

**Check current cron config:**
```sql
SELECT jobname, command FROM cron.job WHERE jobname = 'process-timers';
```

**Fix for local development:**
```sql
-- Remove production cron job
SELECT cron.unschedule('process-timers');

-- Add local cron job
SELECT cron.schedule(
    'process-timers',
    '* * * * *',
    $$
    SELECT net.http_post(
        url := 'http://host.docker.internal:54321/functions/v1/process-timers',
        headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"}'::jsonb,
        body := '{}'::jsonb
    ) AS request_id;
    $$
);
```

**Note:** Use `host.docker.internal` (not `localhost`) because the cron runs inside Docker.

### Manual Trigger (Alternative)

Instead of fixing cron, manually trigger edge functions:
```bash
curl -X POST http://localhost:54321/functions/v1/process-timers
```

---

## Testing Timed Mode Features

### Test 3.13: Rating Minimum Timer Extension

**Setup:**
1. Create chat with:
   - Timed mode: ON
   - Proposing duration: 60 seconds
   - Rating duration: 60 seconds
   - Rating minimum: 2
   - Proposing minimum: 3

2. Need 3 users (users can't rate their own proposition)

3. Each user submits 1 proposition

4. Start rating phase

5. Have only 1 user rate (leaves avg < 2)

6. Wait for timer to expire

**Expected:** Timer extends by `rating_duration` when `rating_minimum` not met.

**Verify timer extension:**
```sql
SELECT id, phase, phase_ends_at, NOW() as current_time
FROM rounds WHERE completed_at IS NULL;
```

---

## Debugging Tips

### Enable Debug Logging

Key debug prints are in:
- `lib/services/auth_service.dart` - `[AuthService]` prefix
- `lib/providers/providers.dart` - `[Provider]` prefix
- `lib/providers/notifiers/chat_detail_notifier.dart` - `[ChatDetail]` prefix
- `lib/widgets/countdown_timer.dart` - `[CountdownTimer]` prefix

### Check Cron Job Execution

```sql
-- View recent cron job runs
SELECT * FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 10;
```

### Check Edge Function Logs

```bash
npx supabase functions logs process-timers --local
```

---

## Common Issues Checklist

| Issue | Cause | Solution |
|-------|-------|----------|
| "User must be signed in" after db reset | Stale cached JWT | Full app restart |
| Timer not extending | Cron pointing to production | Update cron to localhost |
| Realtime events not received | Subscription not set up | Check `_setupSubscriptions` logs |
| "Time expired" not updating | Timer already past | Check `phase_ends_at` vs `NOW()` |

---

## Environment-Specific Cron Jobs

The cron job URLs need to be different for local vs production:

| Environment | URL Pattern |
|-------------|-------------|
| Local | `http://host.docker.internal:54321/functions/v1/...` |
| Production | `https://<project-ref>.supabase.co/functions/v1/...` |

**Solution**: Use `scripts/setup_local_cron.sql` after every db reset to override cron jobs for local development. This approach is preferred over environment-aware migrations because:
1. Migrations run on both local and production
2. Production needs the hardcoded production URL
3. The local setup script is an explicit, one-time step per reset
