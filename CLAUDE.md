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

**Utils** (`lib/utils/`) - Standalone utility functions:
- `timezone_utils.dart` - Timezone auto-detection and mapping

**Notifiers** (`lib/providers/notifiers/`) - Stateful controllers with Realtime subscriptions:
- `MyChatsNotifier` - User's chat list with debounced refresh (150ms)
- `ChatDetailNotifier` - Individual chat state with phase management
- `GridRankingNotifier` - Proposition ranking state
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
- Migrations live in `supabase/` with 799 pgtap tests

## Models

All models in `lib/models/` use:
- `fromJson()` factory constructors
- `equatable` mixin for value equality
- snake_case JSON keys matching Supabase columns

## Local Development

See `docs/LOCAL_DEVELOPMENT.md` for detailed instructions.

### CRITICAL: After Database Reset

After running `npx supabase db reset --local`, you MUST:

```bash
# 1. Setup local cron jobs (timers won't work without this!)
psql "postgresql://postgres:postgres@localhost:54322/postgres" -f scripts/setup_local_cron.sql

# 2. Restart the Flutter app (full restart, not hot reload)
```

**Why?** Migrations create cron jobs pointing to **production** Edge Functions. Without running the setup script, timed features (phase advancement, timer extension, auto-start) will silently fail locally.

### Verify Cron Setup

```bash
# Check cron jobs point to LOCAL
psql "postgresql://postgres:postgres@localhost:54322/postgres" -c "
  SELECT jobname, CASE
    WHEN command LIKE '%host.docker.internal%' THEN 'LOCAL ✓'
    ELSE 'PRODUCTION ✗'
  END as target
  FROM cron.job WHERE jobname = 'process-timers';"
```
