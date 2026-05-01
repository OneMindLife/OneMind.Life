# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Answering questions about runtime behavior

When asked how something behaves at runtime — what a trigger does on expiry, what a cron job extends, what an RPC checks, what a state machine transitions to, etc. — **read the source before answering**. Don't reason from priors and don't claim "no, it doesn't do X" without grepping for it.

The high-stakes places where this has burned past sessions:
- `supabase/functions/process-timers/index.ts` — phase expiry behavior (advance vs extend, minimum checks, cron cadence)
- `supabase/migrations/*` — RLS policies, RPC bodies, trigger functions, advance logic
- `lib/providers/notifiers/*` — state-derivation rules (e.g. `canSkipRating`, `canSkip`, `hasParticipated`)

A 30-second grep beats an uninformed answer. If the user pushes back on something runtime-ish, default to "let me check" and pull up the actual code.

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

#### Step 1: Play Button (`intro`)
User taps play on the welcome screen ("Welcome to OneMind! — The idea competition platform — See how it works"). Template is auto-selected (saturday). Each template provides a question, chat name, fake participant propositions, and a predetermined winner for R1.

#### Steps 2-11: Chat Tour (10 steps, `chatTourIntro` → `chatTourSubmit`)
Progressive-reveal walkthrough of the chat interface. Steps advance via fade-out → fade-in animation (`_tooltipFadeController`). `reserveSpace: true` on the `RoundPhaseBar` prevents layout shifts during progressive reveal. Word timings are pre-loaded from cache in `initState`/`didUpdateWidget` to prevent first-frame text flash.

| Step | Element | Tooltip Title | Notes |
|------|---------|---------------|-------|
| 1 | `chatTourIntro` | "Welcome" | Full chat screen fades in at 100% opacity (not dimmed). "This is a OneMind chat. You'll see how ideas compete until the group reaches a decision. Let's walk through how it works." Round status bar shows final state (1 phase chip, progress bar, timer). Auto-advance. |
| 2 | `chatTourTitle` | "Chat Name" | Chat name highlights, everything else dims to 0.25. "This is the chat name." Auto-advance. |
| 3 | `chatTourMessage` | "Discussion Question" | Initial message card highlights. "This is the discussion topic. Everyone submits their idea in response." Auto-advance. |
| 4a | `chatTourPlaceholder` sub 0 | "Placeholder" | Placeholder card fades in, content hidden (`contentOpacity: 0`). "This is where the chosen idea will go." Auto-advance. |
| 4b | `chatTourPlaceholder` sub 1 | "Placeholder" | Label + ellipsis text fade in (`contentOpacity: 1`). "The chat hasn't started yet, so it's empty for now." Auto-advance. |
| 5 | `chatTourRound` | "Round Number" | Round number in status bar highlights. "This shows which round the chat is in. The group goes through multiple rounds to choose the winning idea." Auto-advance. |
| 6a | `chatTourPhases` sub 0 | "Round Phases" | Both [Proposing] and [Rating] chips shown (inline colored chips in dialog). `highlightAllPhases: true`. Auto-advance. |
| 6b | `chatTourPhases` sub 1 | "Round Phases" | "Each round starts in the [Proposing] phase." Rating chip fades out via `AnimatedSize`. Auto-advance. |
| 7a | `chatTourProgress` sub 0 | "Participation" | Progress bar at 0%. Auto-advance. |
| 7b | `chatTourProgress` sub 1 | "Participation" | Progress bar animates 0→100%. "Once it reaches 100%, the chat moves on to the next phase." Resets to 0% on next step. Auto-advance. |
| 8 | `chatTourParticipants` | "Leaderboard" | `NoButtonTtsCard`. Finger taps icon → opens bottom sheet (6-step overlay). |

**Leaderboard Bottom Sheet (6 steps)**:
1. "Participants" — names fade in. Auto-advance.
2. "Rankings" — numbers (#1-#4) appear. Inline [Proposing]/[Rating] chips in dialog. Auto-advance.
3. "Rankings" — "No rounds completed yet, everyone starts unranked." Numbers animate to dashes via `AnimatedSwitcher`. User taps Next.
4. "Submit Ideas" — "Done" tags fade in under NPC names (400ms), then dialog: "Alex, Sam, and Jordan have already submitted their ideas for this [proposing] phase." Inline proposing chip. Auto-advance.
5. "Submit Ideas" — "The better the idea, the higher the rank." Auto-advance.
6. "Close Leaderboard" — finger animation on X button → hint. User taps X. Sheet close auto-advances to step 9.

| Step | Element | Tooltip Title | Notes |
|------|---------|---------------|-------|
| 9 | `chatTourTimer` | "Phase Timer" | Countdown timer highlights (frozen at 5:00). "Each phase has a time limit — when it runs out, the chat moves on." Auto-advance. |
| 10 | `chatTourSubmit` | "Submit Ideas" | Only textfield + placeholder bright. "Type your best idea here to replace the placeholder above." Textfield auto-focuses. Auto-advance. |

On `chatTourSubmit`, during tooltip transition out, all elements restore to 1.0 for seamless exit to main scaffold.

#### Timers
- **Frozen timer**: `CountdownTimer.frozen` param stops the 1-second tick. `frozenDuration: Duration(minutes: 5)` displays exactly "5m 00s".
- **Chat tour**: Timer frozen throughout (demo only).
- **R1 proposing hints** (`r2_new_round`, `r2_replace`): Timer frozen at 5:00, starts after last hint dismissed.
- **R1 rating hints** (`r1_rating_phase`, `r1_rating_button`): Timer frozen at 5:00, starts after "Start Rating" hint dismissed.
- **R1 leaderboard preview**: Timer frozen at 5:00 until `continueToRound2()`.
- Timer shows "Time expired" at 0 but tutorial does not auto-advance on expiry.

#### Round Phase Bar
- `showInactivePhase`: defaults to `false` everywhere. Only the active phase chip shown (Proposing or Rating).
- Exception: chat tour `chatTourPhases` sub-step 0 — both chips shown with `highlightAllPhases: true`.
- Rating chip fades out via `AnimatedSize` (300ms). Whole bar wrapped in `AnimatedSize` for smooth re-centering.
- `reserveSpace: true` in chat tour keeps progress bar and timer in tree at `opacity: 0` to prevent layout shifts.

#### Participation Progress Bar
- **Chat tour**: 0% from `chatTourProgress` onward. Sub-step 1 animates 0→100% then resets.
- **Round phases**: Animates 0→75% (3 of 4 NPCs done) via `TweenAnimationBuilder` (1200ms, easeOut).
- **Real chat**: Static percentage, updates in realtime.

#### Steps 12-13: Round 1 — Propose, Rate, Explore Results
- **`round1Proposing`**: User types a custom proposition. Progress bar animates to 75%.
- **`round1Rating`**: Three sequential dialogs on rating screen:
  1. "Rate Ideas" — "This is the rating screen. You won't rate your own idea — only other people's." Auto-advance.
  2. "Rate Ideas" — "The closer your ratings match the group's, the higher you rank." Auto-advance.
  3. Finger demo plays (swap animation in binary phase).
  4. "Compare Ideas" — inline [swap]/[check] icons. User taps Next.
  Then: "Start Rating" hint with inline `FilledButton.icon` replica. `NoButtonTtsCard`. Timer frozen at 5:00.
  User taps "Start Rating" → rating screen opens. `markRatingStarted` delayed 1300ms.
- **`round1Result`**: Returns to chat screen (not results). Multi-step flow (`_r1ResultDialogStep`):
  1. "Round 1 Winner" — "Everyone has rated. '{winner}' won! It is now the new placeholder." Auto-advance. Winner panel spotlighted, everything else dimmed.
  2. Finger animation taps winner panel. Panel blocked by `AbsorbPointer`.
  3. `NoButtonTtsCard`: "Tap it to continue." User taps winner panel.
  4. Opens `_TutorialR1CycleHistoryPage` (1 round entry, ascending order):
     - "This is where we see all completed round winners. Only 1 round has been completed so far." Auto-advance.
     - Finger taps Round 1 entry. Entry blocked by `AbsorbPointer`.
     - `NoButtonTtsCard`: "Tap it to view the full rating results." User taps.
     - `ReadOnlyResultsScreen`: "These are the group's combined rating results." Auto-advance → finger → "When done viewing, press [back] to continue." Auto-advance. Back enabled after dialog.
     - On return to cycle history: `NoButtonTtsCard` "Press [back] to continue." Back immediately enabled.
  5. Popping cycle history → **R1 leaderboard reveal**:
     - Finger taps leaderboard icon → `NoButtonTtsCard` "Tap [leaderboard icon] to continue." User taps icon.
     - Sheet opens with R1 rankings (Alex #1, user #2). `OverlayEntry` dialogs above sheet:
       - "The leaderboard has been updated with Round 1 results. Currently, Alex is #1." Auto-advance.
       - Finger on X button (2s animation).
       - "When done viewing the leaderboard, press the X to continue." User taps Got it → X enabled → user closes sheet.
     - Sheet close → 300ms delay → `continueToRound2()` → R2 hints fade in after 400ms.

#### Steps 14-16: Round 2 — Propose, Rate, Explore Results
Two sequential floating hints with frozen timer at 5:00 (`_hintFadeController`):
1. **"New Round"** — highlights round status bar, everything else dimmed. Progress bar stays at 0% during hints. Auto-advance.
2. **"Can You Beat It?"** — "Try to replace 'Movie Night'. Send your best idea!" Highlights textfield + placeholder. `autoAdvance: false`, textfield + skip blocked until dismissed. Timer starts after dismiss. Progress bar animates to 75% after dismiss.

Then:
- **`round2Proposing`**: User submits proposition. Progress bar animates to 75%.
- **`round2Rating`**: Rating screen auto-opens. "Previous Winner" dialog appears after first binary comparison (when carried-forward card enters). Controls blocked immediately via `_carriedHintPending` (before dialog shows). Dialog positioned below the card. "'Movie Night' is the previous round's winner. If it also wins this round, it gets placed permanently in the chat." User taps Got it. Back button blocked during dialog.
- **`round2Result`**: Returns to chat screen. Multi-step flow (`_r2ResultDialogStep`):
  1. "You Won!" — "Your idea won! It is now the new placeholder." Auto-advance. Winner panel spotlighted.
  2. Finger taps winner panel. Panel blocked.
  3. `NoButtonTtsCard`: "Tap it to continue." User taps.
  4. Opens `_TutorialR2CycleHistoryPage` (2 round entries, ascending):
     - "Now we have 2 completed rounds." Auto-advance.
     - Finger taps Round 2 entry.
     - `NoButtonTtsCard`: "Tap it to view the full rating results." User taps.
     - `ReadOnlyResultsScreen` with custom dialog: "'Movie Night' lost this round, so it was replaced by the new winner — your idea." Dialog positioned near R1 winner card (`tutorialHintTargetRating: 67.0`). Auto-advance → finger → back dialog. Auto-advance.
     - On return: finger → back → "Press [back] to continue."
  5. Popping cycle history → `continueToRound3()`.

#### Steps 17-19: Round 3 — Propose, Rate, Convergence
Two sequential floating hints (R3 "You Won!" intro removed — merged into R2 result):
1. **"New Round"** — highlights round status bar. Progress bar stays at 0% during hints. Auto-advance.
2. **"Last Chance!"** — "Can you think of something better? Type your best idea and submit it! If you can't think of anything, tap [skip] to skip." Highlights textfield + placeholder. `autoAdvance: false`, textfield + skip blocked by `AbsorbPointer` until dismissed. Timer starts after dismiss.

Then:
- **`round3Proposing`**: User submits or skips. Skip calls `beginRound3Rating()`.
- **`round3Rating`**: Rating screen auto-opens.
- **`round3Consensus`**: Two-dialog flow with finger animation (`_convergenceDialogStep`):
  1. `TourTooltipCard`: "Your idea won again, so it is added permanently to the chat." Auto-advance. Consensus card blocked by `AbsorbPointer`.
  2. Finger animation taps consensus card.
  3. `NoButtonTtsCard`: "Tap it to continue." User taps consensus card → opens cycle history.

#### Cycle History (convergence)
- Shows round winners in ascending order (oldest at top, newest at bottom). Convergence winners (last 2) highlighted in blue (`theme.colorScheme.primary`), others in orange (`AppColors.consensus`).
- Three-dialog flow (`_dialogStep`):
  1. `TourTooltipCard`: "See how the same idea won Round 2 and Round 3? That's called convergence — the group has converged on an idea." Auto-advance. Convergence winner entries highlighted, others + app bar dimmed.
  2. Finger animation → back arrow.
  3. `TourTooltipCard`: "When done viewing round winners, press [back] to continue." `autoAdvance: false`. User taps Got it → back enabled. User browses then presses back.
- `continueToConvergenceContinue()` called in `.then()` when cycle history is popped.

#### Steps 20-22: Process Continues, Share & Complete
- **`convergenceContinue`**: Placeholder card visible (everything else dimmed). `previousRoundWinners` cleared for new cycle. "Now the group works toward its next convergence." Tooltip below placeholder.
- **`shareDemo`**: "Share Your Chat" prompts user to tap Share in the app bar. "Continue" button also advances. Placeholder stays visible.
- **`complete`**: Fade-out (300ms) → centered success message fade-in (300ms) → "Continue" button → navigates to Home Tour.

#### Hint System — `TourTooltipCard` & `NoButtonTtsCard`

All hints use widgets from `lib/screens/home_tour/widgets/spotlight_overlay.dart`.

**`TourTooltipCard`** — dialog with button + TTS:
- **Style**: Elevated Material card (`elevation: 8`, `surface` color, `borderRadius: 16`)
- **Content**: Bold title + description text (or rich `descriptionWidget` for inline icons/buttons)
- **Inline widgets**: `[proposing]`/`[rating]` → colored phase chips via `buildPhaseChipRichText()`. `[leaderboard]` → leaderboard icon. `[startRating]` → `FilledButton.icon` replica. `[skip]` → skip button replica. `[back]` → back arrow icon.
- **Buttons**: Single `FilledButton` (label: "Next", "Finish", "Got it!"). No skip button, no progress dots.
- **TTS**: Auto-speaks description in `initState`. `description` text used for TTS (markers replaced with words). When speech finishes: `autoAdvance: true` → calls `onNext()`; `autoAdvance: false` → shows replay icon, waits for button tap.
- **Round hints float** as `Positioned` overlays in a `Stack` wrapper — never shift layout.

**`NoButtonTtsCard`** — dialog with TTS only (no button):
- Same card style but without action button.
- Auto-speaks description. User must take the expected action (tap a card, press back, etc.) to proceed.

**`TutorialTts`** — shared TTS singleton:
- `preload()` — called in tutorial `initState`. Caches all word timing JSONs and first audio asset so dialogs render without flash.
- `getCachedTimings(text)` — returns preloaded timings for a description. Used in `TourTooltipCard.initState`/`didUpdateWidget` to pre-set `currentTimings` before `speak()` is called, preventing first-frame empty text.
- `speak()` calls `_tts.stop()` + 50ms delay before new speech. Generation counter invalidates stale completion handlers.
- `stop()` bumps generation and cancels speech. Includes stack trace logging for debugging.
- `frozen` duration support: `frozenDuration` param displays exact time without ticking.
- Mute toggle persists across dialogs.
- `_cleanForSpeech()` replaces `[markers]` with spoken equivalents.

#### Finger Animations & Button Blocking

Animated finger demos (tap gestures) play between dialogs. During animations, targets are blocked using `AbsorbPointer`:

| Screen | Target | Blocking mechanism |
|--------|--------|--------------------|
| Chat tour | Leaderboard icon | `AbsorbPointer(absorbing: !_participantsFingerDone)` |
| Leaderboard sheet (chat tour) | X close button | `IgnorePointer(ignoring: tourStep < 4)` |
| R1 leaderboard sheet | X close button | `IgnorePointer(ignoring: dialogStep < 3)` |
| R1/R2 result | Winner panel | `AbsorbPointer` during dialog steps + finger animations |
| Results screen | Back arrow | `AbsorbPointer(absorbing: _resultsDialogStep < 2)` |
| R1/R2 cycle history | Round entry + Back arrow | `AbsorbPointer` per dialog step |
| R3 cycle history | Back arrow | `AbsorbPointer(absorbing: _dialogStep < 2)` |
| Convergence | Consensus card | `AbsorbPointer(absorbing: _convergenceDialogStep == 1)` |
| Rating screen | Grid + back button | `AbsorbPointer` during carried winner hint |
| Chat screen | Winner panel | Blocked during all active hints except "tap it" hints |

### Home Tour (8 Steps)

After the tutorial completes, the Home Tour teaches the main UI. Same progressive-reveal pattern: elements fade from invisible (0.0) → highlighted (1.0) → dimmed (0.25). FAB is always in the widget tree (invisible before its step) for stable layout. FAB step tooltip is positioned by measuring the FAB's actual position via GlobalKey.

| Step | Element | Tooltip Title | Description |
|------|---------|---------------|-------------|
| 1 | Display name | "Your Display Name" | "This is your display name." |
| 2 | Search bar | "Search Your Chats" | "Filter your chats by name." |
| 3 | Your Chats | "Your Chats" | "These are the chats that you are in." |
| 4 | Pending requests | "Pending Requests" | "These are chats you're waiting to be accepted into." |
| 5 | Create FAB | "Quick Actions" | "Tap to create a chat, join an existing one, or discover public chats." Tooltip includes embedded FAB replica. |
| 6 | Language selector | "Change Language" | "Tap here to switch the app language." |
| 7 | How It Works | "How It Works" | "Replay the tutorial to learn how OneMind works." |
| 8 | Menu | "Menu" | "Contact us, view the source code, or read the legal documents." |

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
  FROM cron.job WHERE jobname IN ('process-timers', 'process-auto-refills', 'cleanup-inactive-chats');"

# Verify vault secret points to local
psql "postgresql://postgres:postgres@localhost:54322/postgres" -c "
  SELECT name, LEFT(decrypted_secret, 40) as url_preview
  FROM vault.decrypted_secrets WHERE name = 'project_url';"
```
