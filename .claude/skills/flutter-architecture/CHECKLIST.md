# PR Review Checklist

## Services

- [ ] Uses `AppException` (not generic `Exception`)
- [ ] Returns domain models (not raw JSON)
- [ ] Handles auth with `_supabase.auth.currentUser?.id`
- [ ] Has corresponding test file

## Models

- [ ] Extends `Equatable`
- [ ] `props` includes ALL fields
- [ ] Uses `factory fromJson()`
- [ ] Enum parsing throws on unknown values (fail-fast)
- [ ] Has corresponding test file with equality tests

## Notifiers

- [ ] State class extends `Equatable`
- [ ] State `props` includes ALL fields
- [ ] Starts with `AsyncLoading()`
- [ ] Handles errors with `AsyncError(e, st)`
- [ ] Disposes timers and subscriptions
- [ ] Uses debounce (150ms) for realtime events
- [ ] Uses rate limiting (1s) for refresh methods
- [ ] Logs errors in catch blocks (`debugPrint`)
- [ ] Optimistic updates revert on failure

## Providers

- [ ] Uses `.autoDispose` for screen-scoped state
- [ ] Uses `.family` for parameterized providers
- [ ] Defined in `lib/providers/providers.dart`

## Tests

- [ ] Uses fixtures with fixed dates for equality
- [ ] Tests error cases (not just happy path)
- [ ] Uses Mocktail for mocking services
- [ ] Verifies state transitions

## Realtime

- [ ] Debounce timer: 150ms
- [ ] Rate limit: 1s minimum between refreshes
- [ ] Unsubscribes in `dispose()`
- [ ] Handles race conditions with delays if needed

## Error Handling

- [ ] No silent catch blocks (all log errors)
- [ ] No generic `Exception` throws
- [ ] Fail-fast enum parsing
- [ ] Proper error messages with context
