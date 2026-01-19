# Billing & Credits System

This document describes the OneMind credit-based billing system.

> **Note:** This system is designed for authenticated users. Currently, the app only has anonymous auth. The billing system will need to be integrated once proper user authentication (email/password, OAuth) is implemented. See `FEATURE_REQUESTS.md` for the auth roadmap.

---

## Overview

OneMind uses a credit-based billing model:
- **1 credit = 1 user-round** (one participant completing one round)
- **$0.01 USD per credit**
- **500 free user-rounds/month** for authenticated users
- **Anonymous hosts**: Limited to 60-minute chats (no credits needed)

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Flutter App    │────▶│  Edge Functions  │────▶│     Stripe      │
│  (BillingService)│     │  (Supabase)      │     │     API         │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                       │
         │                       ▼
         │              ┌──────────────────┐
         └─────────────▶│   PostgreSQL     │
                        │   (user_credits, │
                        │   transactions)  │
                        └──────────────────┘
```

---

## Database Schema

### Tables

#### `user_credits`
Stores user balance and Stripe integration data.

```sql
CREATE TABLE public.user_credits (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id),
    credit_balance INTEGER NOT NULL DEFAULT 0,        -- Paid credits
    free_tier_used INTEGER NOT NULL DEFAULT 0,        -- Used this month
    free_tier_reset_at TIMESTAMPTZ,                   -- When free tier resets
    stripe_customer_id TEXT,                          -- Stripe customer ID
    stripe_payment_method_id TEXT,                    -- Saved card for auto-refill
    auto_refill_enabled BOOLEAN DEFAULT FALSE,
    auto_refill_threshold INTEGER,                    -- Trigger when balance <= this
    auto_refill_amount INTEGER,                       -- Credits to add
    auto_refill_last_error TEXT,                      -- Last error message
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### `credit_transactions`
Audit log of all credit changes.

```sql
CREATE TABLE public.credit_transactions (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    transaction_type TEXT CHECK (transaction_type IN
        ('purchase', 'usage', 'refund', 'adjustment', 'auto_refill')),
    credit_amount INTEGER NOT NULL,                   -- Positive=add, Negative=deduct
    balance_after INTEGER NOT NULL,
    description TEXT,
    stripe_payment_intent_id TEXT,
    stripe_checkout_session_id TEXT,                  -- For idempotency
    chat_id INTEGER REFERENCES public.chats(id),
    round_id INTEGER REFERENCES public.rounds(id),
    user_round_count INTEGER,                         -- Participants in round
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### `monthly_usage`
Aggregated monthly statistics per user.

```sql
CREATE TABLE public.monthly_usage (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    year_month TEXT NOT NULL,                         -- '2026-01' format
    total_user_rounds INTEGER DEFAULT 0,
    free_tier_used INTEGER DEFAULT 0,
    credits_used INTEGER DEFAULT 0,
    credits_purchased INTEGER DEFAULT 0,
    UNIQUE(user_id, year_month)
);
```

#### `auto_refill_queue`
Async processing queue for automatic refills.

```sql
CREATE TABLE public.auto_refill_queue (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    credits_to_add INTEGER NOT NULL,
    status TEXT DEFAULT 'pending',  -- pending, processing, completed, failed
    stripe_payment_intent_id TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);
```

#### `billing_config`
Configurable billing constants.

```sql
-- Current values:
INSERT INTO billing_config (key, value, description) VALUES
    ('free_tier_monthly_limit', '500', 'Free user-rounds per month'),
    ('credit_price_cents', '1', 'Price per credit in cents'),
    ('anonymous_chat_max_minutes', '60', 'Max chat duration for anonymous hosts');
```

### Key Database Functions

| Function | Purpose |
|----------|---------|
| `get_or_create_user_credits(p_user_id)` | Creates user record, resets free tier monthly |
| `can_afford_user_rounds(p_user_id, p_count)` | Checks if user can afford usage |
| `deduct_user_rounds(p_user_id, p_count, ...)` | Deducts from free tier first, then paid |
| `add_purchased_credits(...)` | Adds credits (idempotent via checkout session ID) |
| `check_and_queue_auto_refill(p_user_id)` | Queues refill if threshold reached |
| `save_stripe_payment_method(...)` | Saves Stripe customer/payment method IDs |

### Trigger

```sql
-- Automatically deducts user-rounds when a round completes
CREATE TRIGGER on_round_winner_track_usage
    AFTER UPDATE OF winning_proposition_id ON rounds
    FOR EACH ROW
    WHEN (NEW.winning_proposition_id IS NOT NULL)
    EXECUTE FUNCTION track_round_usage();
```

---

## Edge Functions

### `create-checkout-session`
Creates a Stripe Checkout session for purchasing credits.

**Endpoint:** `POST /functions/v1/create-checkout-session`

**Request:**
```json
{
  "credits": 100
}
```

**Response:**
```json
{
  "url": "https://checkout.stripe.com/..."
}
```

**Validation:**
- Min: 1 credit
- Max: 100,000 credits ($1,000)
- Rate limit: 10 requests/minute/user

---

### `stripe-webhook`
Handles Stripe webhook events.

**Endpoint:** `POST /functions/v1/stripe-webhook`

**Events Handled:**
- `checkout.session.completed` → Adds credits to user account
- `checkout.session.expired` → Logs expiration

**Security:**
- Validates webhook signature using `STRIPE_WEBHOOK_SECRET`
- Idempotent via UNIQUE constraint on `stripe_checkout_session_id`

---

### `setup-payment-method`
Creates a Stripe SetupIntent for saving a payment method (for auto-refill).

**Endpoint:** `POST /functions/v1/setup-payment-method`

**Response:**
```json
{
  "clientSecret": "seti_xxx_secret_xxx",
  "customerId": "cus_xxx"
}
```

---

### `confirm-payment-method`
Confirms and saves the payment method after SetupIntent completion.

**Endpoint:** `POST /functions/v1/confirm-payment-method`

**Request:**
```json
{
  "setupIntentId": "seti_xxx"
}
```

**Response:**
```json
{
  "success": true,
  "paymentMethod": {
    "last4": "4242",
    "brand": "visa",
    "expMonth": 12,
    "expYear": 2027
  }
}
```

---

### `process-auto-refill`
Cron job that processes queued auto-refill requests.

**Endpoint:** `POST /functions/v1/process-auto-refill`

**Auth:** Requires `X-Cron-Secret` header

**Schedule:** Every minute via pg_cron

**Process:**
1. Fetches pending items from `auto_refill_queue`
2. Creates PaymentIntent with saved payment method
3. Charges card off-session
4. Adds credits to user account
5. Updates queue status

---

## Flutter Integration

### Models

**`lib/models/user_credits.dart`**
```dart
class UserCredits {
  final int creditBalance;
  final int freeTierUsed;
  final DateTime? freeTierResetAt;
  final String? stripeCustomerId;
  final String? stripePaymentMethodId;
  final bool autoRefillEnabled;
  final int? autoRefillThreshold;
  final int? autoRefillAmount;

  // Computed properties
  int get freeTierRemaining => max(0, 500 - freeTierUsed);
  int get totalAvailable => freeTierRemaining + creditBalance;
  bool get hasCredits => totalAvailable > 0;
  bool canAfford(int userRounds) => totalAvailable >= userRounds;
}
```

**`lib/models/credit_transaction.dart`**
```dart
enum TransactionType { purchase, usage, refund, adjustment, autoRefill }

class CreditTransaction {
  final int id;
  final TransactionType type;
  final int creditAmount;
  final int balanceAfter;
  final String? description;
  final DateTime createdAt;
}
```

### Service

**`lib/services/billing_service.dart`**
```dart
class BillingService {
  // Get current user credits
  Future<UserCredits> getMyCredits();

  // Get transaction history
  Future<List<CreditTransaction>> getTransactionHistory({int limit = 50});

  // Create Stripe checkout session
  Future<String> createCheckoutSession(int credits);

  // Setup payment method for auto-refill
  Future<Map<String, dynamic>> setupPaymentMethod();

  // Confirm payment method after Stripe redirect
  Future<Map<String, dynamic>> confirmPaymentMethod(String setupIntentId);

  // Update auto-refill settings
  Future<void> updateAutoRefillSettings({
    required bool enabled,
    int? threshold,
    int? amount,
  });

  // Static helpers
  static int calculateCostCents(int credits) => credits; // 1 cent per credit
  static String formatDollars(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
}
```

### UI

**`lib/screens/billing/credits_screen.dart`**

Features:
- Balance display (paid + free tier remaining)
- Purchase interface with credit amount selector
- Price calculation ($0.01 per credit)
- Transaction history list
- Auto-refill configuration (partial - card saving UI incomplete)

---

## Stripe Configuration

### Required Environment Variables

Set these in Supabase secrets:

```bash
npx supabase secrets set STRIPE_SECRET_KEY="sk_live_..."
npx supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_live_..."
npx supabase secrets set STRIPE_CREDIT_PRICE_ID="price_live_..."
```

### Creating the Stripe Price

1. Go to Stripe Dashboard > Products
2. Create product: "OneMind Credits"
3. Add price:
   - Amount: $0.01 USD
   - Type: One-time
   - Usage type: Metered (quantity adjustable)
4. Copy the Price ID (e.g., `price_1ABC...`)
5. Set as `STRIPE_CREDIT_PRICE_ID`

### Webhook Setup

1. Go to Stripe Dashboard > Developers > Webhooks
2. Add endpoint:
   ```
   https://YOUR_PROJECT_REF.supabase.co/functions/v1/stripe-webhook
   ```
3. Select event: `checkout.session.completed`
4. Copy signing secret → Set as `STRIPE_WEBHOOK_SECRET`

### Test vs Live Mode

| Environment | Keys | Webhook |
|-------------|------|---------|
| Development | `sk_test_...`, `whsec_test_...` | Test webhook endpoint |
| Production | `sk_live_...`, `whsec_live_...` | Live webhook endpoint |

---

## Current Implementation Status

### Complete ✅

- [x] Database schema (user_credits, transactions, queue)
- [x] Database functions (deduct, add, check affordability)
- [x] Usage tracking trigger (on_round_winner_track_usage)
- [x] Edge Functions (checkout, webhook, payment method, auto-refill)
- [x] Flutter models (UserCredits, CreditTransaction, PaymentMethod)
- [x] BillingService with all RPC calls
- [x] CreditsScreen UI (balance, purchase, history)
- [x] Model unit tests
- [x] Widget tests for CreditsScreen

### Incomplete ⚠️

- [ ] Auto-refill card saving UI (shows "coming soon")
- [ ] Post-checkout success/failure screen
- [ ] Real-time balance updates after purchase

### Missing ❌

- [ ] **Credit enforcement** - No checks before creating chats/rounds
- [ ] **Riverpod state management** - No `userCreditsProvider`
- [ ] **Integration with chat flow** - Can create chats without credits
- [ ] **Database (pgtap) tests** - No tests for billing functions
- [ ] **Service unit tests** - No mocked tests for BillingService

---

## Integration with Auth System

> **Current State:** App uses anonymous auth only. All users get a UUID but cannot create persistent accounts.

### When Auth is Implemented

1. **Link credits to verified users** - Credits should persist across devices
2. **Prevent anonymous credit purchases** - Only verified users can buy
3. **Free tier for verified only** - Anonymous users limited to 60-min chats
4. **Account recovery** - Credits tied to email, not anonymous UUID

### Required Changes

```dart
// In chat creation flow:
if (!authService.isVerified && wantsToPurchaseCredits) {
  // Prompt to create account first
  showSignUpDialog();
  return;
}

// In credit check:
if (authService.isAnonymous) {
  // Use anonymous limits (60 min max)
} else {
  // Check credits/free tier
  final canAfford = await billingService.canAfford(estimatedUserRounds);
}
```

---

## Related Files

| Category | Files |
|----------|-------|
| Database | `supabase/migrations/20260110060000_add_billing_schema.sql` |
| | `supabase/migrations/20260110070000_add_auto_refill.sql` |
| | `supabase/migrations/20260110120000_stripe_idempotency.sql` |
| Edge Functions | `supabase/functions/create-checkout-session/` |
| | `supabase/functions/stripe-webhook/` |
| | `supabase/functions/setup-payment-method/` |
| | `supabase/functions/confirm-payment-method/` |
| | `supabase/functions/process-auto-refill/` |
| Flutter | `lib/models/user_credits.dart` |
| | `lib/models/credit_transaction.dart` |
| | `lib/services/billing_service.dart` |
| | `lib/screens/billing/credits_screen.dart` |
| Tests | `test/models/user_credits_test.dart` |
| | `test/screens/credits_screen_test.dart` |

---

## Quick Reference

```bash
# Set Stripe secrets
npx supabase secrets set STRIPE_SECRET_KEY="sk_..."
npx supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_..."
npx supabase secrets set STRIPE_CREDIT_PRICE_ID="price_..."

# Verify secrets
npx supabase secrets list

# Check user credits (SQL)
SELECT * FROM user_credits WHERE user_id = 'uuid';

# Check transactions
SELECT * FROM credit_transactions
WHERE user_id = 'uuid'
ORDER BY created_at DESC
LIMIT 10;

# Check auto-refill queue
SELECT * FROM auto_refill_queue
WHERE status = 'pending';
```
