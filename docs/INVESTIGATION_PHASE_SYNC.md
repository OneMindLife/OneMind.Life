# Investigation: Phase Sync Bug

**Status:** RESOLVED
**Started:** 2026-01-14
**Bug:** U3 doesn't see phase change when host advances from proposing to rating

---

## Problem Statement

When the host advances from proposing phase to rating phase, other participants (U3) sometimes don't see the UI update. They remain stuck on the proposing/submissions view while the host is already in rating.

---

## Code Flow Analysis

### What happens when host clicks "Advance to Rating"

```
Host clicks button
    ↓
ChatService.advanceToRating(roundId, chat)
    ↓
Single UPDATE to rounds table:
  - phase: 'rating'
  - phase_started_at: now
  - phase_ends_at: calculated
    ↓
Supabase sends ONE Realtime event to all subscribers
    ↓
U3's ChatDetailNotifier._onRoundChange() should fire
    ↓
State should update, UI should rebuild
```

### Key Files

| File | Role |
|------|------|
| `lib/services/chat_service.dart` | `advanceToRating()` - executes the UPDATE |
| `lib/providers/notifiers/chat_detail_notifier.dart` | Subscribes to rounds, handles events |
| `lib/screens/chat/chat_screen.dart` | Renders UI based on `currentRound.phase` |

---

## Hypotheses

### H1: Realtime event never arrives
- Subscription not set up in time
- Filter doesn't match
- Network issue

### H2: Event arrives but is dropped
- Rate limiting returns early (FIXED - now defers)
- Event processing throws silently

### H3: Event arrives but state doesn't update correctly
- Payload missing required fields
- Phase parsing fails
- copyWith not working

### H4: State updates but UI doesn't rebuild
- Riverpod not notifying listeners
- Widget not watching correct provider

---

## Changes Made (Potential Fixes)

### 1. Rate Limiting: Defer Instead of Drop

**Before:**
```dart
void _scheduleRefresh() {
  if (now.difference(_lastRefreshTime!) < _minRefreshInterval) {
    return;  // ❌ DROPPED
  }
  // ...
}
```

**After:**
```dart
void _scheduleRefresh() {
  if (now.difference(_lastRefreshTime!) < _minRefreshInterval) {
    // ✅ Schedule deferred refresh
    _refreshDebounce = Timer(delay, () => _loadData());
    return;
  }
  // ...
}
```

**File:** `lib/providers/notifiers/chat_detail_notifier.dart:475-500`

### 2. Direct State Update from Realtime Payload

**Added:** `_onRoundChange()` method that updates state directly from the Realtime payload without waiting for a full refresh.

```dart
void _onRoundChange(PostgresChangeEvent event, Map<String, dynamic>? newRecord) {
  // Parse phase from payload
  final newPhase = RoundPhase.values.firstWhere((p) => p.name == phaseStr);

  // Update state directly
  final updatedRound = currentRound.copyWith(phase: newPhase, ...);
  state = AsyncData(currentState.copyWith(currentRound: updatedRound));
}
```

**File:** `lib/providers/notifiers/chat_detail_notifier.dart:405-472`

### 3. Post-Subscription Refresh

**Added:** A 200ms delayed refresh after subscriptions are set up to catch events that fired during initial load.

```dart
Timer(const Duration(milliseconds: 200), () {
  _lastRefreshTime = null;
  _scheduleRefresh();
});
```

**File:** `lib/providers/notifiers/chat_detail_notifier.dart:334-341`

### 4. Round.copyWith() Method

**Added:** `copyWith()` method to Round model for immutable state updates.

**File:** `lib/models/round.dart:33-57`

---

## Debug Logging Added

```dart
// In _loadData
debugPrint('[ChatDetail] _loadData: starting, setupSubscriptions=$setupSubscriptions');
debugPrint('[ChatDetail] _loadData: loaded round=${currentRound?.id}, phase=${currentRound?.phase}');

// In subscriptions
debugPrint('[ChatDetail] Chat change received');
debugPrint('[ChatDetail] Cycle change received');
debugPrint('[ChatDetail] Participant change received');

// In _onRoundChange
debugPrint('[ChatDetail] _onRoundChange: event=$event, record=$newRecord');
debugPrint('[ChatDetail] Phase changed: ${old} -> $new, updating state directly');

// In _scheduleRefresh
debugPrint('[ChatDetail] _scheduleRefresh: rate limited, deferring by ${delay}ms');
debugPrint('[ChatDetail] _scheduleRefresh: executing refresh');
```

---

## Tests Added

**File:** `test/providers/notifiers/chat_detail_notifier_test.dart`

| Test | What it verifies |
|------|------------------|
| `updates currentRound` | copyWith works for round |
| `can update round phase via copyWith chain` | Full state update flow |
| `updates phase correctly` | Round.copyWith preserves fields |
| `can parse phase from string payload` | Realtime payload parsing |
| `simulates full phase update flow` | End-to-end state update |
| `handles unknown phase gracefully` | Edge case handling |
| `detects when phase has not changed` | No-op case |

---

## Manual Testing Required

### Setup
1. Run app on two devices/browsers
2. Device 1: Host
3. Device 2: U3 (participant)

### Test Steps
1. Host creates chat
2. U3 joins chat
3. Host starts round (proposing phase)
4. Both submit propositions
5. **Host clicks "Advance to Rating"**
6. **Observe U3's screen**

### Expected Behavior
- U3 should immediately see the rating grid
- Console should show: `[ChatDetail] _onRoundChange: event=update`
- Console should show: `[ChatDetail] Phase changed: proposing -> rating`

### Failure Indicators
- U3 stuck on proposing view
- No `_onRoundChange` log → Event not arriving
- `_onRoundChange` log but no state update → Parsing/update issue
- State update log but UI unchanged → Riverpod/widget issue

---

## Investigation Log

### 2026-01-14 - Initial Analysis

1. **Reviewed rate limiting code** - Found it was dropping requests instead of deferring
2. **Traced advanceToRating flow** - Confirmed it's a single UPDATE, single event
3. **Added defer fix** - Rate limiting now schedules deferred refresh
4. **Added direct state update** - `_onRoundChange` updates immediately from payload
5. **Added tests** - 8 tests for state update logic, all passing
6. **Questioned if rate limiting is even the issue** - For single events, it shouldn't matter

### 2026-01-14 - Resolution

**Manual test result:** PASSED ✅

U3's UI updated correctly when host advanced to rating phase.

**Root cause:** Likely a combination of:
1. Rate limiting was dropping refresh requests instead of deferring them
2. No direct state update from Realtime payload (relied only on full refresh)

**Fixes applied:**
1. Rate limiting now defers instead of drops
2. `_onRoundChange()` updates state directly from Realtime payload
3. Post-subscription refresh catches events missed during initial load

---

## Resolution

- [x] Manual test with debug logging enabled
- [x] Confirmed fix works
- [ ] Remove debug logging (optional - can keep for future debugging)
- [ ] Commit final fix

---

## Related Files

- `lib/providers/notifiers/chat_detail_notifier.dart`
- `lib/services/chat_service.dart`
- `lib/models/round.dart`
- `test/providers/notifiers/chat_detail_notifier_test.dart`
- `docs/INVESTIGATION_PHASE_SYNC.md` (this file)
