# Architecture Patterns

## 1. Service Layer Pattern

Services encapsulate Supabase queries and return domain models.

**Rules:**
- Inject `SupabaseClient` via constructor
- Return domain models (not raw JSON)
- Throw `AppException` on errors (not generic `Exception`)
- Handle auth via `_supabase.auth.currentUser?.id`

**Location:** `lib/services/*.dart`

---

## 2. Riverpod Provider Architecture

Providers wire services to notifiers with dependency injection.

**Rules:**
- Use `.family` for parameterized providers (e.g., chatId)
- Use `.autoDispose` for screen-scoped state
- Define providers in `lib/providers/providers.dart`
- Use `ref.read()` in notifier constructors, `ref.watch()` in UI

---

## 3. State Notifier Pattern

Notifiers manage async state with realtime subscriptions.

**Rules:**
- Extend `StateNotifier<AsyncValue<XxxState>>`
- State classes extend `Equatable` with complete `props`
- Initialize with `super(const AsyncLoading())`
- Set `state = AsyncData(...)` on success
- Set `state = AsyncError(e, st)` on failure

**Optimistic Updates:**
```dart
// 1. Save current state
final currentState = state.valueOrNull;

// 2. Optimistic update
state = AsyncData(currentState.copyWith(...));

// 3. Try operation
try {
  await service.doThing();
} catch (_) {
  // 4. Revert on failure
  state = AsyncData(currentState);
  rethrow;
}
```

---

## 4. Realtime Subscription Pattern

Handle Supabase Realtime with debouncing and rate limiting.

**Rules:**
- Debounce: 150ms to handle rapid-fire events
- Rate limit: 1s minimum between refreshes
- Unsubscribe in `dispose()`
- Use separate timers for different refresh types

**Pattern:**
```dart
static const _debounceDuration = Duration(milliseconds: 150);
static const _minRefreshInterval = Duration(seconds: 1);
DateTime? _lastRefreshTime;

void _scheduleRefresh() {
  final now = DateTime.now();
  if (_lastRefreshTime != null &&
      now.difference(_lastRefreshTime!) < _minRefreshInterval) {
    return; // Rate limited
  }

  _debounceTimer?.cancel();
  _debounceTimer = Timer(_debounceDuration, () {
    _lastRefreshTime = DateTime.now();
    _refresh();
  });
}
```

---

## 5. Error Handling Pattern

Use `AppException` hierarchy for typed errors.

**Rules:**
- Throw `AppException.xxx()` factory constructors
- Fail-fast on unknown enum values (throw, don't default)
- Log errors in catch blocks with `debugPrint()`
- Never silently swallow errors

**Enum Parsing:**
```dart
static MyEnum _parseEnum(String? value) {
  switch (value) {
    case 'foo': return MyEnum.foo;
    case 'bar': return MyEnum.bar;
    case null: return MyEnum.foo; // Default for null only
    default:
      throw AppException.validation(
        message: 'Unknown value: $value',
        field: 'field_name',
      );
  }
}
```

---

## 6. Model Pattern

Models use Equatable with complete props for proper equality.

**Rules:**
- Extend `Equatable`
- Include ALL fields in `props` (not just id)
- Use `factory fromJson()` for parsing
- Use fail-fast enum parsing

---

## 7. Testing Pattern

Tests use Mocktail for mocking and fixtures for test data.

**Rules:**
- Use `MockXxx` classes extending `Mock` with `Fake` for types
- Create fixtures with fixed dates for equality tests
- Use `pumpApp()` helper for widget tests
- Test notifiers in isolation from UI
