# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Install dependencies
flutter pub get

# Run all tests
flutter test

# Run specific test file
flutter test test/models/chat_test.dart

# Run tests with coverage
flutter test --coverage

# Static analysis
dart analyze lib/

# Code generation (Riverpod)
dart run build_runner build --delete-conflicting-outputs
```

## Architecture Overview

OneMind is a Flutter mobile app for collective consensus-building, backed by Supabase.

### Layer Architecture

```
Screens (UI) → Notifiers (State) → Services (Business Logic) → Supabase (Backend)
```

**Services** (`lib/services/`) - Singleton business logic, injected via Riverpod:
- `AuthService` - Supabase Anonymous Auth (JWT-based), display names
- `ChatService` - Chat CRUD, cycles, rounds, winner calculation
- `ParticipantService` - Join/leave/kick, approval workflow
- `PropositionService` - Submit and rate propositions
- `AnalyticsService` - Firebase Analytics event tracking
- `BillingService` - Credits and billing operations
- `InviteService` - Invite codes and email invitations
- `TutorialService` - Tutorial completion state

**Utils** (`lib/utils/`) - Standalone utility functions:
- `timezone_utils.dart` - Timezone auto-detection and mapping

**Notifiers** (`lib/providers/notifiers/`) - Stateful controllers with Realtime subscriptions:
- `MyChatsNotifier` - User's chat list with debounced refresh (150ms)
- `ChatDetailNotifier` - Individual chat state with phase management
- `RatingNotifier` - Proposition ranking state
- `PublicChatsNotifier` - Public chat discovery with pagination

**Providers** (`lib/providers/providers.dart`) - Dependency injection:
```dart
final chatServiceProvider = Provider<ChatService>((ref) => ...);
final myChatsProvider = StateNotifierProvider<MyChatsNotifier, AsyncValue<MyChatsState>>(...);
```

### Key Patterns

**State Management**: Riverpod with `AsyncValue<T>` for loading/error/data states. Notifiers extend `StateNotifier<AsyncValue<State>>`.

**Realtime Updates**: Postgres Change subscriptions filtered by user_id. Notifiers debounce refreshes to handle race conditions where events fire before transactions commit.

**Optimistic Updates**: Update local state immediately, revert on API failure:
```dart
state = AsyncData(currentState.copyWith(...));
try { await service.operation(); }
catch { state = AsyncData(currentState); }  // Revert
```

**Auth Model**: Supabase Anonymous Auth - all users get a UUID via `auth.uid()`. RLS policies enforce access at the database level.

### Domain Model

- `Chat` → has many `Cycle` → has many `Round` → has many `Proposition`
- `Chat` → has many `Participant` (via user_id)
- `Round` phases: `waiting` → `proposing` → `rating`
- Consensus: Same proposition wins N consecutive rounds (configurable)

### Carry Forward Propositions

When a round ends, winning propositions are automatically "carried forward" to the next round by a database trigger. These are tracked via `propositions.carried_from_id`:
- `NULL` = new proposition submitted by user
- `NOT NULL` = carried forward from previous round (references root proposition)

**Important rule**: `proposing_minimum` only counts NEW propositions (`carried_from_id IS NULL`). Carried forward propositions don't count toward the minimum. This ensures each round requires fresh user participation, not just inherited winners.

## Testing Patterns

**Widget Tests**: Use `pumpApp` extension for provider overrides:
```dart
await tester.pumpApp(
  MyWidget(),
  chatService: mockChatService,
  authService: mockAuthService,
);
```

**Service Mocks**: Use mocktail with setup extensions:
```dart
final mockChatService = MockChatService();
mockChatService.setupGetMyChats([ChatFixtures.model()]);
```

**Fixtures**: Factory classes in `test/fixtures/` for test data:
```dart
ChatFixtures.model(id: 1, name: 'Test')
ChatFixtures.public()
ChatFixtures.withAutoStart(participantCount: 5)
```

**Realtime Mocking**: Mock `RealtimeChannel` for subscription tests. Register fallback values in `setUpAll()`:
```dart
setUpAll(() => registerFallbackValues());
```

## Supabase Integration

- All services use `auth.uid()` for user identification (RLS enforced)
- Realtime subscriptions use `PostgresChangeFilter` on user_id or chat_id
- Services return domain models, not raw JSON
- Migrations live in `supabase/` with ~1100 pgtap tests

## Models

All models in `lib/models/` use:
- `fromJson()` factory constructors
- `equatable` mixin for value equality
- snake_case JSON keys matching Supabase columns

## User Onboarding Flow

The app is designed to make onboarding as smooth as possible so users can quickly start participating with one another.

### Entry Points

Users can arrive at OneMind via two paths:

1. **Direct visit** (`onemind.life`) - User discovers the app organically
2. **Invite link** (`onemind.life/join/CODE`) - User was invited to join an existing chat

### Tutorial Flow

All new users go through the tutorial to learn how the app works. This is critical because the consensus-building mechanics are unique and users won't understand how to participate without guidance.

**Tutorial sequence:**
1. User arrives at app → redirected to tutorial (if not completed)
2. Tutorial teaches: proposing ideas, rating, viewing results, sharing
3. Tutorial ends with share dialog showing a prominent "Continue" button

### Post-Tutorial Navigation

After completing the tutorial, the app checks if the user has any chats or pending join requests:

| Condition | Action | Rationale |
|-----------|--------|-----------|
| Has chats or pending requests | Navigate to Home | User came via invite link - a chat is waiting for them |
| No chats and no pending | Navigate to Create Chat | User visited directly - they need to create a chat to use the app |

**Why this logic?**
- **Invite flow**: User clicks invite link → requests to join → tutorial starts → tutorial ends → they already have a pending request, so go to Home where they can see it
- **Direct flow**: User visits onemind.life → tutorial starts → tutorial ends → no chats exist, so guide them to create one immediately

### Invite Link Behavior

When a user clicks an invite link (`/join/CODE`):
- If tutorial not completed: The join request is processed, then user is redirected to tutorial
- If tutorial completed: User goes directly to the join screen (skips tutorial)

This ensures invited users learn the app before participating, while returning users can join quickly.

### Key Files

- `lib/config/router.dart` - Routing logic, tutorial redirect, post-tutorial navigation
- `lib/screens/tutorial/` - Tutorial implementation
- `lib/services/tutorial_service.dart` - Tutorial completion state (persisted locally)

## Local Development

### CRITICAL: After Database Reset

After running `npx supabase db reset --local`, you MUST:

```bash
# 1. Setup local cron jobs (timers won't work without this!)
psql "postgresql://postgres:postgres@localhost:54322/postgres" -f scripts/setup_local_cron.sql

# 2. Restart the Flutter app (full restart, not hot reload)
```

**Why?** Migrations create cron jobs using vault-based URL helpers with placeholder values. Without running the setup script, the vault secrets won't point to your local instance and timed features (phase advancement, timer extension, auto-start) will silently fail.

### Verify Cron Setup

```bash
# Check cron jobs use vault-based helpers (not hardcoded URLs)
psql "postgresql://postgres:postgres@localhost:54322/postgres" -c "
  SELECT jobname, CASE
    WHEN command LIKE '%get_edge_function_url%' THEN 'VAULT-BASED ✓'
    ELSE 'HARDCODED ✗'
  END as target
  FROM cron.job WHERE jobname IN ('process-timers', 'process-auto-refills', 'cleanup-inactive-chats');"

# Verify vault secret points to local
psql "postgresql://postgres:postgres@localhost:54322/postgres" -c "
  SELECT name, LEFT(decrypted_secret, 40) as url_preview
  FROM vault.decrypted_secrets WHERE name = 'project_url';"
```
