# Feature Requests

This document tracks planned features and enhancements for future implementation.

---

## User Authentication (Sign-in/Sign-up)

**Priority:** Medium
**Status:** Planned

### Current State
The app uses **Supabase Anonymous Auth** exclusively. All users are automatically signed in anonymously when they open the app - there is no sign-in/sign-up UI. The only "identity" users have is their display name (stored in auth metadata).

### Problem
The "Require authentication" chat setting exists in the database but is **non-functional** because there's no way for users to upgrade from anonymous to authenticated. The setting has been hidden from the UI until this feature is implemented.

### Proposed Implementation

#### Authentication Methods (in priority order)
1. **Email + Password** - Standard sign-up/sign-in flow
2. **Magic Link** - Passwordless email authentication
3. **OAuth** - Google, Apple, etc. (optional, lower priority)

#### Required Components
1. **Sign-up Screen** - Email, password, confirm password, display name
2. **Sign-in Screen** - Email, password (with "Forgot password" link)
3. **Account Linking** - Allow anonymous users to link their account to email/password
4. **Password Reset Flow** - Email-based password reset
5. **Profile Screen** - View/edit display name, email, change password

#### "Require Authentication" Feature
Once auth is implemented, the hidden "Require authentication" chat setting can be re-enabled:
- When `require_auth = true`: Only authenticated (non-anonymous) users can join
- When `require_auth = false`: Both anonymous and authenticated users can join

#### Database Changes
- `AuthService.linkWithEmail()` method already scaffolded
- No schema changes needed - `require_auth` column already exists

### Related Files (Hidden UI)
- `lib/screens/create/widgets/visibility_section.dart` (SwitchListTile commented out)
- `lib/screens/chat/widgets/chat_settings_sheet.dart` (setting row commented out)
- `lib/services/auth_service.dart` (linkWithEmail scaffolded)

---

## PENDING MANUAL TESTING

> No features currently pending manual testing. All implemented features have been tested.

---

## PLANNED CHANGES

### Rating Auto-Advance: Change from Participant Count to Average Raters Per Proposition

**Priority:** Medium
**Status:** ✅ COMPLETED

#### Summary
Changed `rating_threshold_count` from counting "unique participants who have rated" to "average raters per proposition". This ensures all propositions get adequate rating coverage before auto-advancing.

#### Previous Behavior
```
rating_threshold_count = 2
→ OLD: Advance when 2 different participants have rated (any proposition)
→ BUG: 2 people rating 1 prop each = advance (poor coverage)
```

#### New Behavior
```
rating_threshold_count = 2
→ NEW: Advance when average raters per proposition >= 2
→ FIX: All props must have ~2 raters on average before advancing
```

#### What Was Changed
- Modified `check_early_advance_on_rating()` trigger function
- Now calculates: `total_ratings / total_propositions`
- Compares this average against `rating_threshold_count`
- Aligns with `rating_minimum` which already uses "avg raters per proposition"

#### Related Files
- `supabase/migrations/20260116140000_fix_rating_advance_avg_raters.sql`
- `supabase/tests/40_rating_advance_avg_raters_test.sql` (9 tests)
- Updated `supabase/tests/28_immediate_early_advance_test.sql`
- Updated `supabase/tests/32_adaptive_duration_alignment_test.sql`

---

## Discover Chats Realtime Updates

**Priority:** Medium
**Status:** ✅ COMPLETED (commits 34967bf, 03695a8)

### Implementation Summary
Added realtime subscription to PublicChatsNotifier using the StateNotifier pattern.

### What Was Done
- Rewrote `PublicChatsNotifier` to use StateNotifier pattern (matching MyChatsNotifier)
- Added Supabase Realtime subscription on the `chats` table
- Uses debounced refresh (150ms) with rate limiting (1s) to handle race conditions
- Updated provider definition from AsyncNotifierProvider to StateNotifierProvider
- Added comprehensive tests verifying subscription setup, callback triggers, and cleanup

### Important: No Column Filter on Subscription
The subscription does NOT filter by `access_method = 'public'` because Supabase Realtime DELETE events only include the primary key in `old_record` (not other columns). A filtered subscription would miss DELETE events entirely. The refresh query filters to public chats anyway, so extra events from non-public chat changes are harmless and debounced.

### Current Behavior
The Discover Chats screen now updates automatically when:
- New public chats are created
- Public chats are deleted
- Chat properties change (access_method toggled to/from public)

### Related Files
- `lib/providers/notifiers/public_chats_notifier.dart`
- `lib/providers/chat_providers.dart`
- `test/providers/notifiers/public_chats_notifier_test.dart`

---

## Rating Start Mode (Manual Rating Phase Start)

**Priority:** Medium
**Status:** ✅ COMPLETE

### Summary
Added `rating_start_mode` column to allow decoupling when rating starts from when proposing ends. This setting is **only available when facilitation mode is manual**. When facilitation is auto, rating also starts automatically.

### UI Behavior
| Facilitation Mode | Rating Start Mode Option | Rating Behavior |
|-------------------|-------------------------|-----------------|
| **Auto** | Hidden (forced to auto) | Rating starts automatically after proposing |
| **Manual** | Shown (user can choose) | User controls when rating starts |

### Values
- `auto` (default): Rating starts immediately when proposing ends (existing behavior)
- `manual`: Host must manually start rating phase, allowing time to review propositions first

### New "Waiting for Rating" State
When `rating_start_mode = 'manual'` AND facilitation is manual, a new intermediate state exists between proposing and rating:

```
[waiting] → [proposing] → [waiting-for-rating] → [rating] → [complete/next round]
                              ↑
                         NEW STATE
                    (phase='waiting' but has propositions)
```

The round is in `phase = 'waiting'` but has propositions. The helper function `is_round_waiting_for_rating(round_id)` returns TRUE in this state.

### What Was Implemented
- Added `rating_start_mode` column with CHECK constraint (`'manual'` or `'auto'`)
- Updated `check_early_advance_on_proposition` trigger to respect this setting
- Added `advance_proposing_to_waiting()` function for timer expiry
- Added `is_round_waiting_for_rating()` helper function
- Flutter model and service support for the new column
- Edge Function `process-timers` updated to handle rating_start_mode
- UI hides rating_start_mode option when facilitation is auto

### Automated Tests Status
- ✅ Model parsing tests (`test/models/chat_test.dart`) - 3 tests
- ✅ pgtap tests (`supabase/tests/17_rating_start_mode_test.sql`) - 11 tests
- ✅ Updated `supabase/tests/28_immediate_early_advance_test.sql`
- ✅ UI visibility tests (`test/screens/create/widgets/phase_start_section_test.dart`)

### Manual Testing Status
- ✅ Manual mode flow tested and working
- ✅ Auto mode unchanged (rating starts immediately)
- ✅ UI shows correct messaging in waiting-for-rating state

### Related Files
- `supabase/migrations/20260115100000_add_rating_start_mode.sql`
- `supabase/functions/process-timers/index.ts`
- `lib/models/chat.dart`
- `lib/services/chat_service.dart`
- `lib/providers/notifiers/chat_detail_notifier.dart`
- `lib/screens/create/widgets/phase_start_section.dart`
- `lib/screens/chat/widgets/phase_panels.dart` (WaitingForRatingPanel)

---

## Read-Only Results Grid View

**Priority:** Medium
**Status:** ✅ COMPLETED

### Summary
Replaced the scrollable list (`FullPreviousResults`) with a "See All Results" button that opens a read-only grid view showing all propositions positioned by their final MOVDA scores.

### What Was Implemented
- Added `readOnly` parameter to `GridRankingWidget` that hides editing controls (Place, Undo, arrows) but keeps zoom/pan
- Added `GridRankingModel.fromResults()` factory that creates a model in completed state with propositions positioned by their `finalRating`
- Created `ReadOnlyGridResultsScreen` that displays the grid in read-only mode
- Updated `PreviousWinnerPanel` with optional "See All Results" button
- Removed `FullPreviousResults` widget entirely
- Updated `chat_screen.dart` to always use `PreviousWinnerPanel` with the new button

### UI Behavior
| showPreviousResults | Display |
|---------------------|---------|
| `false` | PreviousWinnerPanel only |
| `true` | PreviousWinnerPanel + "See All Results" button |

The button navigates to a full-screen grid showing all propositions at their final score positions (0-100 scale).

### Tests
- `test/widgets/grid_ranking/grid_ranking_model_test.dart` - 8 tests for `fromResults()` factory
- `test/screens/chat/widgets/previous_round_display_test.dart` - 11 tests for panel and button
- `test/screens/grid_ranking/read_only_grid_results_screen_test.dart` - 6 tests for screen

### Related Files
- `lib/widgets/grid_ranking/grid_ranking_widget.dart` (readOnly param, _buildZoomControls)
- `lib/widgets/grid_ranking/grid_ranking_model.dart` (fromResults factory)
- `lib/screens/grid_ranking/read_only_grid_results_screen.dart` (new)
- `lib/screens/chat/widgets/previous_round_display.dart` (button, FullPreviousResults deleted)
- `lib/screens/chat/chat_screen.dart` (simplified _buildPreviousWinnerPanel)

---

## Host Manual Pause

**Priority:** Medium
**Status:** ✅ COMPLETED

### Summary
Hosts can now manually pause/unpause a chat at any time, independently of the schedule-based pause system.

### How It Works

#### Two Independent Pause Systems
The chat has two separate pause mechanisms:
1. **`schedule_paused`** - Controlled automatically by schedule windows (recurring schedules)
2. **`host_paused`** - Controlled manually by the host via UI button

Both must be `false` for the chat to be active. The helper function `is_chat_paused(chat_id)` returns `schedule_paused OR host_paused`.

#### Timer State Management
When paused, the timer state is preserved:

```
ACTIVE STATE:
  rounds.phase_ends_at = '2024-01-15 14:30:00'  (future timestamp)
  rounds.phase_time_remaining_seconds = NULL

PAUSED STATE:
  rounds.phase_ends_at = NULL                   (cleared - stops timer!)
  rounds.phase_time_remaining_seconds = 120     (saved remaining time)
```

**Key insight:** Setting `phase_ends_at = NULL` naturally stops the timer because the Edge Function queries for `phase_ends_at < NOW()`. A NULL value never matches that condition.

#### Pause Flow
```
host_pause_chat(chat_id):
  1. Verify caller is host (SECURITY DEFINER with auth check)
  2. Find current active round (phase = 'proposing' or 'rating')
  3. Calculate remaining time: EXTRACT(EPOCH FROM (phase_ends_at - NOW()))
  4. Save to: rounds.phase_time_remaining_seconds = remaining_time
  5. Clear: rounds.phase_ends_at = NULL  ← This stops the timer!
  6. Set: chats.host_paused = TRUE
```

#### Resume Flow
```
host_resume_chat(chat_id):
  1. Verify caller is host (SECURITY DEFINER with auth check)
  2. Clear: chats.host_paused = FALSE
  3. IF schedule_paused is ALSO false:
     a. Find round with saved time
     b. Restore: rounds.phase_ends_at = NOW() + saved_time
     c. Clear: rounds.phase_time_remaining_seconds = NULL
  4. ELSE (schedule still paused):
     a. Keep timer frozen (phase_ends_at stays NULL)
     b. Preserve saved time for when schedule resumes
```

#### Schedule + Host Pause Interaction
When both pause types are active:
- Host can resume their pause independently
- Timer only restores when BOTH pauses are false
- Saved time is preserved across both pause types

```
Example scenario:
  t=0:  Chat active, timer running (2:00 remaining)
  t=1:  Host pauses → timer saved (2:00), phase_ends_at = NULL
  t=2:  Schedule also pauses → host_paused=true, schedule_paused=true
  t=3:  Host resumes → host_paused=false, but schedule_paused=true
        → Timer NOT restored (phase_ends_at stays NULL)
        → Saved time (2:00) preserved
  t=4:  Schedule resumes → schedule_paused=false
        → Now both pauses are false
        → Timer restored: phase_ends_at = NOW() + 2:00
```

### What Was Implemented
- Added `host_paused` boolean column to chats table (default FALSE)
- Added `host_pause_chat()` SECURITY DEFINER function with auth check
- Added `host_resume_chat()` SECURITY DEFINER function with auth check
- Added `is_chat_paused()` helper that checks both schedule and host pause
- Updated Chat model with `hostPaused` field and `isPaused` computed property
- Added ChatService methods: `hostPauseChat()`, `hostResumeChat()`
- Added ChatDetailNotifier methods: `pauseChat()`, `resumeChat()`
- Added pause/resume IconButton in chat AppBar (visible only to hosts)
- Added `HostPausedBanner` widget showing different messages for host vs participants

### Tests
- ✅ pgtap tests: `supabase/tests/38_host_pause_test.sql` (21 tests)
  - Schema tests (column and functions exist)
  - Initial state tests
  - Non-host cannot pause (permission check)
  - Pause saves timer state
  - Resume restores timer
  - Double pause/resume idempotency
  - Schedule + host pause interaction
- ✅ Flutter model tests: `test/models/chat_test.dart`
- ✅ Flutter UI tests: `test/screens/chat_screen_test.dart` (Host Pause group)
- ✅ Flutter widget tests: `test/screens/chat/widgets/phase_panels_test.dart` (HostPausedBanner)
- ✅ Manual tests: `docs/TESTING_PLAN.md` (Phase 19: Tests 19.1-19.10)

### Related Files
- `supabase/migrations/20260115110000_add_host_paused.sql`
- `lib/models/chat.dart`
- `lib/services/chat_service.dart`
- `lib/providers/notifiers/chat_detail_notifier.dart`
- `lib/screens/chat/chat_screen.dart`
- `lib/screens/chat/widgets/phase_panels.dart`

---

## Optional Close Time for Schedules

**Priority:** Medium
**Status:** Planned

### Current Behavior
- One-time scheduled chats: Only have a `scheduled_start_at` time, no close time
- Recurring windows: Each window has both start and end time (required)

### Proposed Behavior
1. **One-time schedules**: Add optional `scheduled_end_at` field
   - If set: chat pauses when end time arrives
   - If not set: chat stays open indefinitely after start

2. **Recurring windows**: Make end time optional per window
   - If set: window closes at end time
   - If not set: window stays open until next window's start time (or indefinitely if last window)

### Edge Case: Window Collision
When a window has no close time and the next window's open time arrives:
- The chat is already open, so no action needed
- Log/track that windows overlapped
- Consider: Should this merge into one continuous session or trigger any special behavior?

### Implementation Notes
- Update `schedule_windows` JSONB structure to allow null `end_time`
- Update `is_chat_in_schedule_window()` to handle open-ended windows
- Update `process_scheduled_chats()` pause logic for open-ended windows

---

## Conceptual Clarification: Facilitation Mode vs Schedule

**Status:** ✅ COMPLETED (commit ffcc891)

### The Two Separate Concepts

**1. Facilitation Mode** - Controls HOW/WHEN the proposing phase starts:
- `manual`: Host clicks "Start Phase" button to begin proposing
- `auto`: Proposing starts automatically when participant threshold is met

**2. Schedule** - Controls WHEN the chat room is OPEN (locked vs unlocked):
- `none`: Chat room is always open (no schedule)
- `once`: Chat room opens at a specific time (optionally closes at end time)
- `recurring`: Chat room is only open during defined windows

### Key Insight: Schedule is NOT a Facilitation Mode

**WRONG (current implementation):** `start_mode` includes `scheduled` as a third option

**CORRECT:** Schedule and facilitation mode are orthogonal:
- Schedule = Is the room OPEN or LOCKED?
- Facilitation mode = Once in the room, how does proposing START?

Think of it like a physical meeting room:
1. The room has business hours (schedule) - you can't enter when it's locked
2. Once inside, someone calls the meeting to order (facilitation) - either the host says "let's begin" (manual) or it starts when enough people arrive (auto)

### Correct Mental Model

| Schedule | Facilitation | Behavior |
|----------|--------------|----------|
| none + manual | Room always open, host clicks to start proposing |
| none + auto | Room always open, proposing starts on participant count |
| once + manual | Room opens at time X, host clicks to start proposing |
| once + auto | Room opens at time X, proposing starts on participant count |
| recurring + manual | Room opens during windows, host clicks to start proposing |
| recurring + auto | Room opens during windows, proposing starts on participant count |

### Current Implementation Problems

1. `start_mode = 'scheduled'` exists as if schedule is a facilitation mode
2. Code conflates "room is open" with "proposing should start"
3. The `process_scheduled_chats()` function only handles pause/resume, not the facilitation trigger

### Required Refactor

1. **Remove `scheduled` from `start_mode`** - only allow `manual` and `auto`
2. **Add separate schedule fields:**
   - `schedule_enabled: boolean`
   - `schedule_type: 'once' | 'recurring'`
   - `schedule_start_at: timestamp` (for one-time)
   - `schedule_end_at: timestamp` (optional, for one-time)
   - `schedule_windows: jsonb` (for recurring)
3. **Separate the triggers:**
   - Lock/unlock trigger: Based on schedule - controls `schedule_paused`
   - Start trigger: Based on facilitation mode - creates cycle/round
4. **Update UI** to show schedule and facilitation as separate settings

---

## Adaptive Duration (Hidden)

**Priority:** Low
**Status:** Hidden - Requires Design Rework

### Current State
The adaptive duration feature is fully implemented in the database but **hidden from the UI** due to a fundamental design flaw.

### The Oscillation Problem
Adaptive duration adjusts phase timers based on participation relative to thresholds:
- If participation meets threshold → duration **decreases**
- If participation is below threshold → duration **increases**

This creates a stuck oscillation cycle:
1. Round 1: Participation meets threshold → duration decreases (e.g., 5min → 4.5min)
2. Round 2: Shorter duration causes lower participation → below threshold → duration increases
3. Round 3: Back to original duration → participation meets threshold again → decreases
4. Cycle repeats indefinitely

The system never stabilizes because the adjustment that "worked" immediately causes the opposite condition.

### Infrastructure Preserved
All database infrastructure remains intact:
- `adaptive_duration_enabled` column
- `adaptive_adjustment_percent` column
- `min_phase_duration_seconds` / `max_phase_duration_seconds` columns
- `apply_adaptive_duration()` function
- `calculate_adaptive_duration()` function
- Early advance trigger integration

### Potential Future Solutions
To fix this feature, consider:
1. **Hysteresis** - Different thresholds for increase vs decrease (e.g., increase if < 40%, decrease if > 60%)
2. **Moving average** - Base adjustments on participation trend over N rounds, not single round
3. **One-way adjustment** - Only decrease duration when participation is high, never increase
4. **Cooldown period** - Don't adjust if last adjustment was within N rounds

### Related Files
- `lib/screens/create/create_chat_screen.dart` (hidden here)
- `lib/screens/create/widgets/adaptive_duration_section.dart` (widget exists but unused)
- `supabase/migrations/20260110220000_add_adaptive_duration.sql`
- `supabase/migrations/20260114210000_simplify_adaptive_duration.sql`

---
