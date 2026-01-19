# Edge Functions Guide

This document covers setup, development, and troubleshooting for Supabase Edge Functions in OneMind.

---

## Quick Reference

### Local Development

```bash
# Start Edge Functions locally (from project root)
npx supabase functions serve --env-file supabase/functions/.env --no-verify-jwt
```

### Required Environment Variables

Create `supabase/functions/.env`:

```env
# Required for email sending
RESEND_API_KEY=re_xxxxx

# Required for cron job authentication
CRON_SECRET=your-secret-min-32-chars

# Auto-provided by runtime (don't set manually):
# SUPABASE_URL
# SUPABASE_ANON_KEY
# SUPABASE_SERVICE_ROLE_KEY
```

---

## Available Functions

| Function | Purpose | Auth | Deploy Flag |
|----------|---------|------|-------------|
| `send-email` | Transactional emails (invites, receipts, welcome) | User JWT | (default) |
| `process-timers` | Cron job for phase timers | CRON_SECRET | `--no-verify-jwt` |
| `process-auto-refill` | Cron job for credit auto-refills | CRON_SECRET | `--no-verify-jwt` |
| `translate` | AI translations (Anthropic) | Service role JWT | `--no-verify-jwt` |
| `create-checkout-session` | Stripe checkout | User JWT | (default) |
| `confirm-payment-method` | Stripe payment confirmation | User JWT | (default) |
| `setup-payment-method` | Stripe payment method setup | User JWT | (default) |
| `stripe-webhook` | Stripe webhook handler | Stripe signature | `--no-verify-jwt` |
| `health` | Health check endpoint | None | `--no-verify-jwt` |

---

## Authentication

### How Auth Works

1. **Production**: Supabase Edge Runtime automatically validates JWTs before your function code runs. Invalid tokens are rejected with 401.

2. **Local Development**: Use `--no-verify-jwt` flag to bypass runtime validation. Your function code still runs, but tokens aren't verified.

### Best Practices

```typescript
// DON'T manually verify JWT in function code - let runtime handle it
// This breaks local development and duplicates work

// BAD - Don't do this:
const { error } = await supabase.auth.getUser(token);
if (error) return errorResponse("Invalid token");

// GOOD - Just check header exists, runtime validates:
const authHeader = req.headers.get("Authorization");
if (!authHeader) {
  return errorResponse("Missing authorization header");
}
// Continue with function logic...
```

### Auth Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    PRODUCTION                                │
├─────────────────────────────────────────────────────────────┤
│  Client Request                                              │
│       │                                                      │
│       ▼                                                      │
│  ┌─────────────────┐                                        │
│  │ Edge Runtime    │ ◄── Validates JWT automatically        │
│  │ (Supabase)      │                                        │
│  └────────┬────────┘                                        │
│           │ Valid token                                      │
│           ▼                                                  │
│  ┌─────────────────┐                                        │
│  │ Your Function   │ ◄── Token already validated            │
│  │ Code            │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                 LOCAL DEVELOPMENT                            │
├─────────────────────────────────────────────────────────────┤
│  Client Request                                              │
│       │                                                      │
│       ▼                                                      │
│  ┌─────────────────┐                                        │
│  │ Edge Runtime    │ ◄── --no-verify-jwt: skips validation  │
│  │ (Local)         │                                        │
│  └────────┬────────┘                                        │
│           │ Token passed through                             │
│           ▼                                                  │
│  ┌─────────────────┐                                        │
│  │ Your Function   │ ◄── Same code, tokens not validated    │
│  │ Code            │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Database Trigger Authentication (translate function)

The `translate` function is called by database triggers (not clients or cron jobs), requiring a different auth approach.

### How It Works

1. **Database trigger** fires on chat/proposition INSERT
2. **Trigger function** reads the service role JWT from Supabase Vault
3. **pg_net** sends HTTP request to Edge Function with JWT in Authorization header
4. **Edge Function** validates the JWT by decoding and checking claims

### Vault Secret Setup

The vault must contain the **legacy JWT service role key** (not the new `sb_secret_...` format):

```sql
-- Check current vault secret
SELECT name, LENGTH(decrypted_secret) as length,
       SUBSTRING(decrypted_secret, 1, 20) as prefix
FROM vault.decrypted_secrets
WHERE name = 'edge_function_service_key';

-- The secret should be ~219 chars and start with "eyJhbGciOiJIUzI1NiIs"
-- This is the JWT format, NOT the new "sb_secret_..." format
```

To set/update the vault secret, use the Supabase Dashboard:
1. Go to Project Settings > Vault
2. Add/update secret named `edge_function_service_key`
3. Value: The JWT service role key from API Settings (starts with `eyJ...`)

### Why JWT Validation (Not Exact Match)

Supabase introduced new API key formats (`sb_secret_...`) that Edge Functions receive in `SUPABASE_SERVICE_ROLE_KEY`. However, the vault stores the legacy JWT format.

The translate function validates JWTs by **decoding and checking claims** rather than exact string matching:

```typescript
// Decode JWT payload and verify:
// 1. role === "service_role"
// 2. iss === "supabase"
// 3. ref === project_ref (extracted from SUPABASE_URL)
```

This approach works regardless of what format `SUPABASE_SERVICE_ROLE_KEY` contains.

### Troubleshooting Translation 401 Errors

If translations aren't being created:

1. **Check vault secret exists and is JWT format:**
   ```sql
   SELECT LENGTH(decrypted_secret), SUBSTRING(decrypted_secret, 1, 20)
   FROM vault.decrypted_secrets WHERE name = 'edge_function_service_key';
   -- Should show ~219 chars, starting with "eyJhbGciOiJIUzI1NiIs"
   ```

2. **Check Edge Function logs:**
   ```bash
   npx supabase functions logs translate --linked
   ```

3. **Verify function deployed with `--no-verify-jwt`:**
   ```bash
   npx supabase functions deploy translate --no-verify-jwt
   ```

---

## Email Setup (Resend)

### 1. Create Resend Account

1. Sign up at https://resend.com (free tier: 100 emails/day)
2. Verify your domain or use their test domain
3. Create an API key

### 2. Configure Environment

Add to `supabase/functions/.env`:

```env
RESEND_API_KEY=re_YOUR_API_KEY
```

### 3. Test Email Sending

```bash
# Direct API test (bypasses Edge Function)
curl -X POST 'https://api.resend.com/emails' \
  -H 'Authorization: Bearer re_YOUR_API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "from": "OneMind <hello@mail.onemind.life>",
    "to": "test@example.com",
    "subject": "Test Email",
    "html": "<p>Hello World</p>"
  }'

# Via Edge Function (local dev)
curl -X POST http://127.0.0.1:54321/functions/v1/send-email \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer any-token" \
  -d '{
    "type": "invite",
    "to": "test@example.com",
    "chatName": "Test Chat",
    "inviteCode": "ABC123"
  }'
```

---

## Troubleshooting

### Common Issues

#### 1. "Invalid JWT" or "Invalid or expired token"

**Cause**: Running locally without `--no-verify-jwt` flag.

**Solution**:
```bash
# Add --no-verify-jwt flag
npx supabase functions serve --env-file supabase/functions/.env --no-verify-jwt
```

#### 2. "Email service not configured"

**Cause**: Missing `RESEND_API_KEY` in environment.

**Solution**:
1. Get API key from https://resend.com/api-keys
2. Add to `supabase/functions/.env`:
   ```env
   RESEND_API_KEY=re_xxxxx
   ```
3. Restart Edge Functions

#### 3. "TypeError: Key for the ES256 algorithm must be of type CryptoKey"

**Cause**: Local JWT verification failing due to key format mismatch.

**Solution**: Use `--no-verify-jwt` flag (see #1 above).

#### 4. Function not found / 404

**Cause**: Edge Functions not running or wrong URL.

**Solution**:
```bash
# Check functions are running
curl http://127.0.0.1:54321/functions/v1/health

# Should return: {"status":"ok"}
```

#### 5. CORS errors in browser

**Cause**: Missing CORS headers or wrong origin.

**Solution**: All functions should use the shared CORS helpers:
```typescript
import { handleCorsPreFlight, corsJsonResponse } from "../_shared/cors.ts";

if (req.method === "OPTIONS") {
  return handleCorsPreFlight(req);
}
// ... function logic ...
return corsJsonResponse(data, req);
```

---

## Development Workflow

### 1. Start Local Stack

```bash
# Terminal 1: Start Supabase (database, auth, etc.)
npx supabase start

# Terminal 2: Start Edge Functions
npx supabase functions serve --env-file supabase/functions/.env --no-verify-jwt

# Terminal 3: Start Flutter app
flutter run -d chrome
```

### 2. View Function Logs

Edge Function logs appear in the terminal where you ran `functions serve`.

### 3. Hot Reload

Edge Functions automatically reload when you save changes. No restart needed.

### 4. Testing Functions

```bash
# Test with curl
curl -X POST http://127.0.0.1:54321/functions/v1/your-function \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{"key": "value"}'
```

---

## Deployment

### Deploy All Functions

```bash
# Deploy functions WITH JWT verification (default)
npx supabase functions deploy

# Functions that handle their own auth MUST be deployed separately:
npx supabase functions deploy process-timers --no-verify-jwt
npx supabase functions deploy process-auto-refill --no-verify-jwt
npx supabase functions deploy translate --no-verify-jwt
npx supabase functions deploy stripe-webhook --no-verify-jwt
npx supabase functions deploy health --no-verify-jwt
```

**Important:** The `--no-verify-jwt` functions implement internal authentication (CRON_SECRET header, JWT validation, or Stripe signatures). Deploying them without this flag will cause 401 errors.

### Deploy Single Function

```bash
npx supabase functions deploy send-email
```

### Set Production Secrets

```bash
# Set individual secret
npx supabase secrets set RESEND_API_KEY=re_xxxxx

# Set from file
npx supabase secrets set --env-file supabase/functions/.env.production
```

### Verify Deployment

```bash
# Check function is deployed
npx supabase functions list

# Test production endpoint
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/health
```

---

## File Structure

```
supabase/functions/
├── .env                    # Local environment variables (gitignored)
├── .env.example            # Template for .env
├── _shared/                # Shared utilities
│   ├── cors.ts            # CORS helpers
│   ├── email.ts           # Email templates and sending
│   ├── rate-limiter.ts    # Rate limiting
│   └── validation.ts      # Input validation
├── send-email/
│   └── index.ts           # Email sending function
├── process-timers/
│   └── index.ts           # Cron job for phase timers
├── process-auto-refill/
│   └── index.ts           # Cron job for credit auto-refills
├── translate/
│   └── index.ts           # AI translations (called by DB triggers)
├── create-checkout-session/
│   └── index.ts           # Stripe checkout
├── confirm-payment-method/
│   └── index.ts           # Stripe payment confirmation
├── setup-payment-method/
│   └── index.ts           # Stripe payment method setup
├── stripe-webhook/
│   └── index.ts           # Stripe webhook handler
├── health/
│   └── index.ts           # Health check
└── tests/
    └── *.ts               # Deno tests for functions
```

---

## Security Checklist

- [ ] Never commit `.env` files with real secrets
- [ ] Use `--no-verify-jwt` only in local development
- [ ] Validate and sanitize all user inputs
- [ ] Use rate limiting for sensitive operations
- [ ] Log errors but never log sensitive data (tokens, emails, etc.)
- [ ] Test CORS configuration before deploying
