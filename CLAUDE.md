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

## User Onboarding Flow

The app is designed to make onboarding as smooth as possible so users can quickly start participating with one another.

### Entry Points

Users can arrive at OneMind via two paths:

1. **Direct visit** (`onemind.life`) - User discovers the app organically
2. **Invite link** (`onemind.life/join/CODE`) - User was invited to join an existing chat

### Tutorial Flow

All new users go through the tutorial to learn how the app works. This is critical because the consensus-building mechanics are unique and users won't understand how to participate without guidance.

The tutorial is a simulated 3-round chat that teaches proposing, rating, viewing results, and convergence. After that, a Home Tour teaches the main UI.

#### Step 1: Template Selection (`intro`)
User picks one of 6 localized templates (Personal, Family, Community, Workplace, Government, World). Each template provides a question, chat name, fake participant propositions, and a predetermined winner for R1. A "Classic" template exists as a fallback but is not shown in the UI.

#### Steps 2-5: Chat Tour (`chatTourTitle` → `chatTourProposing`)
A 4-step progressive-reveal walkthrough of the chat interface. Elements fade in one at a time (title → participants button → initial message → proposing input). Each step shows a `TourTooltipCard` with titles: "Chat Name", "Participants", "Discussion Question", "Submit Ideas". The proposing input includes a visible 5-minute countdown timer; the "Submit Ideas" tooltip mentions the timer ("before the timer runs out").

#### Timers
All tutorial rounds display a 5-minute countdown timer (same `CountdownTimer` widget used in real chats). If the timer reaches 0, it shows "Time expired" but nothing else happens — the tutorial does not auto-advance on expiry.

#### Steps 6-8: Round 1 — Propose, Rate, Results
- **`round1Proposing`**: User types a custom proposition. (Chat tour already explained this area — no additional hint.)
- **`round1Rating`**: Floating hint explains rating. Title: "Rate Ideas", desc: "Everyone has submitted. Now rate their ideas to pick a winner before the timer runs out!" User taps "Start Rating" to open rating screen (titled "Rate Ideas"). Rating screen has inline icon hints: binary phase (title: "Compare Ideas", markers: `[swap]`, `[check]`) and positioning phase (title: "Position Ideas", markers: `[up]`, `[down]`).
- **`round1Result`**: Results screen auto-opens (titled "Rating Results"). Hint title: "Rating Results", desc: "'{winner}' won! Press the back arrow to continue."

#### Steps 9-12: Round 2 — Propose, Rate, Results (User Wins)
- **`round2Prompt`**: Emergence card shows the R1 winner. Floating hint title: "Round 2", desc: "'{winner}' will compete again this round. If it wins again, that's convergence — the group's answer. Can you beat it?" User can submit their proposition during this step or the next.
- **`round2Proposing`**: User submits a second proposition (if not already submitted during `round2Prompt`).
- **`round2Rating`**: Rating screen auto-opens. No hints (user learned rating mechanics in R1).
- **`round2Result`**: Results screen **auto-opens** showing the user's idea as winner. Hint title: "You Won!", desc: "Your idea won! Press the back arrow to continue." On dismiss, auto-advances to Round 3.

#### Steps 13-16: Round 3 — Convergence
- **`round3CarryForward`**: Emergence card shows the R2 winner (user's idea) being carried forward.
- **`round3Proposing`**: Floating hint title: "You Won!", desc: "'{winner}' replaced '{previousWinner}'. One more win means convergence!" (reinforcement only — no new concepts)
- **`round3Rating`**: Rating screen auto-opens. No hint (user is experienced by now).
- **`round3Consensus`**: Spotlight overlay highlights the consensus card. Title: "Convergence Reached!", description: '"{proposition}" won 2 rounds in a row, so it gets added permanently to the chat.'

#### Steps 17-19: Process Continues, Share & Complete
- **`convergenceContinue`**: Tooltip positioned above the bottom text field. Title: "The Process Continues", desc: "Now the group works toward its next convergence." Everything on screen is fully visible (no dimming). The emergence card is hidden. A new Round 4 proposing phase is set so the text field appears, reinforcing that the process continues.
- **`shareDemo`**: Tooltip with title "Share Your Chat" prompts user to tap Share in the app bar. A "Continue" button also advances the tutorial without requiring the share tap.
- **`complete`**: Success screen ("Chat tutorial complete!") with fade animation → "Continue" button → navigates to Home Tour.

#### Hint System — `TourTooltipCard`

All hints across the entire onboarding (chat tour, round hints, rating hints, results hints, home tour) use a single unified widget: `TourTooltipCard` in `lib/screens/home_tour/widgets/spotlight_overlay.dart`.

- **Style**: Elevated Material card (`elevation: 8`, `surface` color, `borderRadius: 16`)
- **Content**: Bold title + description text (or rich `descriptionWidget` for inline icons)
- **Buttons**: Single `FilledButton` (label varies: "Next", "Finish", "Continue", etc.). No skip button, no progress dots.
- **Round hints float** as `Positioned` overlays in a `Stack` wrapper — they never shift layout.
- **Dismissal**: Tap the button, or the hint auto-disappears when the user takes the expected action. Dismissed hints are tracked in `Set<String> _dismissedHints`.

### Home Tour (9 Steps)

After the tutorial completes, the Home Tour teaches the main UI. Same progressive-reveal pattern: elements fade from invisible (0.0) → highlighted (1.0) → dimmed (0.25).

| Step | Element | Tooltip Title |
|------|---------|---------------|
| 1 | Display name | "Your Display Name" |
| 2 | Search bar | "Search Your Chats" |
| 3 | Pending requests | "Pending Requests" |
| 4 | Your Chats | "Your Chats" |
| 5 | Create FAB | "Create a Chat" |
| 6 | Explore button | "Explore Public Chats" |
| 7 | Language selector | "Change Language" |
| 8 | How It Works | "How It Works" |
| 9 | Legal docs | "Legal Documents" |

### Post-Tutorial Navigation

After completing both tutorial + home tour, the router simply redirects to `/` (Home). There is no conditional branching based on chat state — the user always lands on the Home screen.

- **Invite flow**: User clicks invite link → requests to join → tutorial starts → tutorial ends → Home (pending request is visible there)
- **Direct flow**: User visits onemind.life → tutorial starts → tutorial ends → Home

### Invite Link Behavior

When a user clicks an invite link (`/join/CODE`):
- If tutorial not completed: The join request is processed, then user is redirected to tutorial
- If tutorial completed: User goes directly to the join screen (skips tutorial)

### Key Files

- `lib/config/router.dart` - Routing logic, tutorial redirect, post-tutorial navigation
- `lib/screens/tutorial/tutorial_screen.dart` - Main tutorial implementation (chat simulation, floating hints, rating screens)
- `lib/screens/tutorial/models/tutorial_state.dart` - `TutorialStep` enum and state model
- `lib/screens/tutorial/tutorial_data.dart` - Template data (questions, propositions, winners)
- `lib/screens/home_tour/home_tour_screen.dart` - Home tour implementation
- `lib/screens/home_tour/widgets/spotlight_overlay.dart` - `TourTooltipCard` widget (shared across all hints)
- `lib/screens/rating/read_only_results_screen.dart` - Results screen with optional tutorial hint overlay
- `lib/services/tutorial_service.dart` - Tutorial completion state (persisted locally)

## Local Development

See `docs/LOCAL_DEVELOPMENT.md` for detailed instructions.

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
  FROM cron.job WHERE jobname IN ('process-timers', 'process-auto-refills', 'cleanup-inactive-chats', 'moltbook-agent-heartbeat');"

# Verify vault secret points to local
psql "postgresql://postgres:postgres@localhost:54322/postgres" -c "
  SELECT name, LEFT(decrypted_secret, 40) as url_preview
  FROM vault.decrypted_secrets WHERE name = 'project_url';"
```
