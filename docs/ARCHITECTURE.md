# OneMind Architecture

This document provides a technical overview of the OneMind platform architecture, data flows, and implementation details.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Technology Stack](#technology-stack)
3. [Data Model](#data-model)
4. [Service Layer](#service-layer)
5. [State Management](#state-management)
6. [Real-time Subscriptions](#real-time-subscriptions)
7. [Authentication Flow](#authentication-flow)
8. [Consensus Algorithm](#consensus-algorithm)
9. [Edge Functions](#edge-functions)
10. [Time-Based Flows](#time-based-flows)
11. [Email Service](#email-service)
12. [Billing & Payments](#billing--payments)
13. [Scheduled Chats](#scheduled-chats)
14. [Adaptive Duration](#adaptive-duration)
15. [Email Invitations](#email-invitations)
16. [Analytics & Error Tracking](#analytics--error-tracking)
17. [Security](#security)
18. [Deployment Guide](#deployment-guide)

---

## System Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER CLIENT                               │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │   Screens   │  │  Providers  │  │  Services   │  │   Models    │ │
│  │             │  │  (Riverpod) │  │             │  │             │ │
│  │ - Home      │→→│ - Session   │→→│ - Chat      │→→│ - Chat      │ │
│  │ - Chat      │  │ - Chat      │  │ - Particip. │  │ - Particip. │ │
│  │ - Create    │  │ - Particip. │  │ - Proposit. │  │ - Round     │ │
│  │ - Join      │  │ - Proposit. │  │ - Session   │  │ - Proposit. │ │
│  │ - Discover  │  │             │  │             │  │ - PublicChat│ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ HTTPS + WebSocket
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         SUPABASE                                     │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │  PostgREST  │  │  Realtime   │  │    Auth     │  │   Storage   │ │
│  │   (REST)    │  │ (WebSocket) │  │  (OAuth)    │  │  (Future)   │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────────────┘ │
│         │                │                │                          │
│         └────────────────┼────────────────┘                          │
│                          ▼                                           │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                      PostgreSQL                                │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  │  │
│  │  │  chats  │ │ cycles  │ │ rounds  │ │ props   │ │ ratings │  │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘  │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐              │  │
│  │  │ users   │ │ particip│ │join_reqs│ │ invites │              │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘              │  │
│  │                                                                │  │
│  │  Triggers: invite_code, expiration, consensus, activity       │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Request Flow

```
User Action → Screen → Provider → Service → Supabase → PostgreSQL
                                     ↓
                              (subscription)
                                     ↓
User Update ← Screen ← Provider ← Realtime ← PostgreSQL Trigger
```

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Frontend** | Flutter 3.10+ (Web) | Web-only UI |
| **State** | Riverpod | Dependency injection & state management |
| **Storage** | flutter_secure_storage | Session token persistence (IndexedDB on web) |
| **Backend** | Supabase | BaaS (PostgreSQL + Auth + Realtime) |
| **Database** | PostgreSQL 15 | Primary data store |
| **Realtime** | Supabase Realtime | WebSocket subscriptions |
| **Auth** | Supabase Auth | Google OAuth + Magic Link |
| **Analytics** | Firebase Analytics | User behavior tracking |
| **Error Tracking** | Sentry | Error reporting & monitoring (web) |
| **Payments** | Stripe Checkout | Hosted payment pages via Edge Functions |
| **Email** | Resend | Transactional emails (invites, receipts, welcome) |
| **Testing** | flutter_test, mocktail, pgtap | Unit & integration tests |

---

## Data Model

### Entity Relationship Diagram

```
┌─────────────┐
│    users    │
├─────────────┤
│ id (PK)     │
│ email       │
│ display_name│
│ avatar_url  │
└──────┬──────┘
       │
       │ 1:N (optional)
       ▼
┌─────────────────────────────────────────────────────────────────┐
│                            chats                                 │
├─────────────────────────────────────────────────────────────────┤
│ id (PK)            │ invite_code (unique)                       │
│ name               │ access_method (public/code/invite_only)    │
│ initial_message    │ require_auth, require_approval             │
│ description        │ proposing_duration_seconds                  │
│ creator_id (FK)────┘ rating_duration_seconds                    │
│ creator_session_token │ proposing_minimum, rating_minimum       │
│ is_active, is_official │ *_threshold_percent, *_threshold_count │
│ expires_at         │ enable_ai_participant, ai_propositions_count│
│                    │ confirmation_rounds_required (1-10)        │
│                    │ show_previous_results (bool)               │
│                    │ propositions_per_user (1-20)               │
└────────┬───────────┴────────────────────────────────────────────┘
         │
         │ 1:N
         ▼
┌─────────────────┐         ┌─────────────────┐
│   participants  │         │     cycles      │
├─────────────────┤         ├─────────────────┤
│ id (PK)         │         │ id (PK)         │
│ chat_id (FK)────┼────────→│ chat_id (FK)    │
│ user_id (FK)    │         │ winning_prop_id │
│ session_token   │         │ completed_at    │
│ display_name    │         └────────┬────────┘
│ is_host         │                  │
│ is_authenticated│                  │ 1:N
│ status          │                  ▼
└────────┬────────┘         ┌─────────────────┐
         │                  │   rounds    │
         │                  ├─────────────────┤
         │                  │ id (PK)         │
         │                  │ cycle_id (FK)   │
         │                  │ custom_id       │◄── Round # within cycle
         │                  │ phase           │◄── waiting/proposing/rating
         │                  │ phase_started_at│
         │                  │ phase_ends_at   │
         │                  │ winning_prop_id │
         │                  │ completed_at    │
         │                  └────────┬────────┘
         │                           │
         │                           │ 1:N
         │                           ▼
         │                  ┌─────────────────┐
         │                  │  propositions   │
         │                  ├─────────────────┤
         │                  │ id (PK)         │
         │                  │ round_id(FK)│
         └─────────────────→│ participant_id  │◄── WHO proposed (hidden)
                            │ content         │
                            └────────┬────────┘
                                     │
                       ┌─────────────┼─────────────┐
                       │             │             │
                       ▼             │             ▼
              ┌─────────────┐       │    ┌──────────────────┐
              │   ratings   │       │    │proposition_ratings│
              ├─────────────┤       │    ├──────────────────┤
              │ id (PK)     │       │    │ proposition_id   │◄── Computed
              │ proposition │───────┘    │ rating (avg)     │
              │ participant │            │ rank             │
              │ rating      │◄── Converted from grid position
              └─────────────┘
```

### Table Relationships

| Parent | Child | Relationship | Notes |
|--------|-------|--------------|-------|
| `users` | `chats` | 1:N | `creator_id` (optional - anon can create) |
| `chats` | `participants` | 1:N | Chat membership |
| `chats` | `cycles` | 1:N | Series of rounds |
| `cycles` | `rounds` | 1:N | Individual rounds |
| `rounds` | `propositions` | 1:N | Ideas submitted |
| `propositions` | `ratings` | 1:N | Individual votes |
| `propositions` | `proposition_ratings` | 1:1 | Computed average |
| `participants` | `propositions` | 1:N | Who submitted (hidden) |
| `participants` | `ratings` | 1:N | Who rated (hidden) |

### Model Patterns

All models follow these patterns:

1. **Equatable:** Extend `Equatable` for value equality
2. **Complete Props:** Include ALL fields in `props` (not just id)
3. **Factory Constructor:** Use `factory fromJson()` for parsing
4. **Fail-Fast Enums:** Throw on unknown enum values

```dart
class Round extends Equatable {
  final int id;
  final int cycleId;
  final RoundPhase phase;
  final DateTime createdAt;

  const Round({...});

  factory Round.fromJson(Map<String, dynamic> json) => Round(
    id: json['id'] as int,
    cycleId: json['cycle_id'] as int,
    phase: _parsePhase(json['phase'] as String?),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  @override
  List<Object?> get props => [id, cycleId, phase, createdAt]; // ALL fields
}
```

### Key Constraints

```sql
-- Only one official chat
CREATE UNIQUE INDEX ON chats (is_official) WHERE is_official = TRUE;

-- One participant per session per chat
CREATE UNIQUE INDEX ON participants (chat_id, session_token);

-- Limit propositions per user per round (enforced by trigger)
-- Each user can submit up to `propositions_per_user` propositions per round

-- One rating per participant per proposition
CREATE UNIQUE INDEX ON ratings (proposition_id, participant_id);
```

---

## Error Handling

### AppException Hierarchy

All services throw `AppException` (not generic `Exception`) for typed error handling.

**Location:** `lib/core/errors/app_exception.dart`

| Factory | When to Use |
|---------|-------------|
| `AppException.authRequired()` | User not signed in |
| `AppException.validation()` | Invalid input, unknown enum value |
| `AppException.billingError()` | Payment/credit errors |
| `AppException.notFound()` | Resource doesn't exist |

**Usage:**
```dart
if (userId == null) {
  throw AppException.authRequired(
    message: 'User must be signed in to create a chat',
  );
}
```

### Fail-Fast Enum Parsing

Enum parsing throws on unknown values (fail-fast) rather than silently defaulting:

```dart
static RoundPhase _parsePhase(String? phase) {
  switch (phase) {
    case 'proposing': return RoundPhase.proposing;
    case 'rating': return RoundPhase.rating;
    case 'waiting':
    case null: return RoundPhase.waiting; // Only null defaults
    default:
      throw AppException.validation(
        message: 'Unknown round phase: $phase',
        field: 'phase',
      );
  }
}
```

### Silent Catch Logging

All catch blocks that don't rethrow must log the error:

```dart
} catch (e) {
  debugPrint('MyNotifier._refreshData failed: $e');
}
```

---

## Service Layer

### Service Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Riverpod Providers                               │
├─────────────────────────────────────────────────────────────────────────┤
│ CORE PROVIDERS                                                           │
│ ├─ supabaseProvider → SupabaseClient (singleton, no auth header)        │
│ ├─ supabaseWithSessionProvider → SupabaseClient (with X-Session-Token)  │
│ ├─ sessionServiceProvider → SessionService                               │
│ ├─ sessionTokenProvider → Future<String>                                 │
│ └─ displayNameProvider → Future<String?>                                 │
├─────────────────────────────────────────────────────────────────────────┤
│ BASE SERVICE PROVIDERS (public queries, no RLS validation)               │
│ ├─ chatServiceProvider → ChatService(client)                            │
│ ├─ participantServiceProvider → ParticipantService(client)              │
│ └─ propositionServiceProvider → PropositionService(client)              │
├─────────────────────────────────────────────────────────────────────────┤
│ SECURE SERVICE PROVIDERS (with X-Session-Token for RLS policies)        │
│ ├─ secureChatServiceProvider → Future<ChatService>                      │
│ ├─ secureParticipantServiceProvider → Future<ParticipantService>        │
│ └─ securePropositionServiceProvider → Future<PropositionService>        │
├─────────────────────────────────────────────────────────────────────────┤
│ AUXILIARY PROVIDERS                                                      │
│ ├─ analyticsServiceProvider → AnalyticsService                          │
│ ├─ inviteServiceProvider → InviteService(client)                        │
│ └─ billingServiceProvider → BillingService(client) [requires OAuth]     │
└─────────────────────────────────────────────────────────────────────────┘
```

**Secure vs Base Providers:**

The secure service providers (`secureChatServiceProvider`, etc.) use a Supabase client
configured with the `X-Session-Token` header. This allows PostgreSQL RLS policies to
validate that operations are performed by the correct participant:

```sql
-- Example RLS policy using session token
CREATE POLICY "Participants can view their chat's propositions"
ON propositions FOR SELECT
USING (
  round_id IN (
    SELECT r.id FROM rounds r
    JOIN cycles c ON r.cycle_id = c.id
    JOIN participants p ON p.chat_id = c.chat_id
    WHERE p.session_token = current_setting('request.headers')::json->>'x-session-token'
  )
);
```

Use **base providers** for:
- Public queries (getPublicChats, getOfficialChat)
- Initial data loading before authentication context is established

Use **secure providers** for:
- User-specific queries (getMyChats, getMyParticipant)
- Write operations (submitProposition, submitRatings)
- Any operation where RLS needs to verify participant ownership

### SessionService

Manages anonymous identity persistence.

| Method | Returns | Description |
|--------|---------|-------------|
| `getSessionToken()` | `Future<String>` | Get or create UUID session token |
| `getDisplayName()` | `Future<String?>` | Get stored display name |
| `setDisplayName(name)` | `Future<void>` | Store display name |
| `hasDisplayName()` | `Future<bool>` | Check if name is set |
| `clearSession()` | `Future<void>` | Clear all session data |

**Storage:** `flutter_secure_storage` with keys:
- `onemind_session_token`
- `onemind_display_name`

### ChatService

Manages chats, cycles, and rounds.

| Method | Returns | Description |
|--------|---------|-------------|
| `getMyChats(sessionToken)` | `Future<List<Chat>>` | User's active chats |
| `getOfficialChat()` | `Future<Chat?>` | The official OneMind chat |
| `getPublicChats(limit, offset)` | `Future<List<PublicChatSummary>>` | Discoverable public chats |
| `searchPublicChats(query, limit)` | `Future<List<PublicChatSummary>>` | Search public chats |
| `getChatByCode(code)` | `Future<Chat?>` | Find chat by invite code |
| `getChatById(id)` | `Future<Chat?>` | Get chat by ID |
| `createChat(...)` | `Future<Chat>` | Create new chat |
| `getCurrentCycle(chatId)` | `Future<Cycle?>` | Active cycle for chat |
| `getCurrentRound(cycleId)` | `Future<Round?>` | Active round |
| `getConsensusItems(chatId)` | `Future<List<Proposition>>` | All cycle winners |
| `subscribeToChatChanges(id, cb)` | `RealtimeChannel` | Watch chat updates |
| `subscribeToRoundChanges(id, cb)` | `RealtimeChannel` | Watch round updates |
| `subscribeToCycleChanges(id, cb)` | `RealtimeChannel` | Watch cycle updates |

### ParticipantService

Manages chat membership.

| Method | Returns | Description |
|--------|---------|-------------|
| `getParticipants(chatId)` | `Future<List<Participant>>` | Active participants |
| `getMyParticipant(chatId, token)` | `Future<Participant?>` | Current user's record |
| `joinChat(...)` | `Future<Participant>` | Join a chat |
| `requestToJoin(...)` | `Future<void>` | Request approval |
| `getPendingRequests(chatId)` | `Future<List<Map>>` | Pending join requests |
| `approveRequest(requestId)` | `Future<void>` | Host approves join |
| `denyRequest(requestId)` | `Future<void>` | Host denies join |
| `kickParticipant(id)` | `Future<void>` | Host kicks user |
| `subscribeToParticipants(id, cb)` | `RealtimeChannel` | Watch participant changes |

### PropositionService

Manages propositions and ratings.

| Method | Returns | Description |
|--------|---------|-------------|
| `getPropositions(roundId)` | `Future<List<Proposition>>` | All propositions |
| `getPropositionsWithRatings(id)` | `Future<List<Proposition>>` | Sorted by rank |
| `submitProposition(...)` | `Future<Proposition>` | Submit idea |
| `getMyProposition(roundId, partId)` | `Future<Proposition?>` | User's proposition |
| `submitRatings(ids, ratings, partId)` | `Future<void>` | Submit all ratings |
| `hasRated(roundId, partId)` | `Future<bool>` | Check if rated all |
| `getMyRatings(roundId, partId)` | `Future<Map<int,int>>` | User's ratings |
| `subscribeToPropositions(id, cb)` | `RealtimeChannel` | Watch new propositions |

### WinnerCalculator

Utility class for calculating winners from grid rankings. Extracted for testability.

| Method | Returns | Description |
|--------|---------|-------------|
| `calculateWinners(rankings)` | `Map<String, dynamic>` | Calculate winner(s) from grid positions |

**Return structure:**
```dart
{
  'winnerIds': List<int>,      // All winning proposition IDs (handles ties)
  'highestScore': double,      // The winning average position score
  'isSoleWinner': bool,        // True if exactly one winner (no tie)
}
```

**Algorithm:**
1. Aggregate all grid positions by proposition ID
2. Calculate average position for each proposition
3. Find the highest (best) average position
4. Return ALL propositions with that score (handles ties)

### InviteService

Manages email invitations for private chats.

| Method | Returns | Description |
|--------|---------|-------------|
| `sendInvite(chatId, email, hostId)` | `Future<void>` | Send invitation email |
| `getInviteByToken(token)` | `Future<Map?>` | Validate invite token |
| `markInviteUsed(inviteId)` | `Future<void>` | Mark invite as consumed |
| `getPendingInvites(chatId)` | `Future<List<Map>>` | List pending invites |
| `revokeInvite(inviteId)` | `Future<void>` | Cancel pending invite |

### AnalyticsService

Tracks user behavior via Firebase Analytics (web only).

| Method | Returns | Description |
|--------|---------|-------------|
| `logScreenView(name)` | `void` | Track screen views |
| `logEvent(name, params)` | `void` | Track custom events |
| `setUserId(id)` | `void` | Set user identifier |
| `setUserProperty(name, value)` | `void` | Set user properties |

---

## State Management

### Riverpod Provider Hierarchy

```
supabaseProvider (singleton - base client)
    │
    ├─→ chatServiceProvider (base)
    │       └─→ ChatService(client)
    │
    ├─→ participantServiceProvider (base)
    │       └─→ ParticipantService(client)
    │
    ├─→ propositionServiceProvider (base)
    │       └─→ PropositionService(client)
    │
    ├─→ inviteServiceProvider
    │       └─→ InviteService(client)
    │
    └─→ analyticsServiceProvider
            └─→ AnalyticsService()

sessionServiceProvider (standalone - secure storage)
    │
    ├─→ sessionTokenProvider (FutureProvider<String>)
    │       │
    │       └─→ supabaseWithSessionProvider (client + X-Session-Token header)
    │               │
    │               ├─→ secureChatServiceProvider (FutureProvider)
    │               │       └─→ ChatService(authenticatedClient)
    │               │
    │               ├─→ secureParticipantServiceProvider (FutureProvider)
    │               │       └─→ ParticipantService(authenticatedClient)
    │               │
    │               └─→ securePropositionServiceProvider (FutureProvider)
    │                       └─→ PropositionService(authenticatedClient)
    │
    └─→ displayNameProvider (FutureProvider<String?>)

// Screen-level state providers (lib/providers/chat_providers.dart)
myChatsProvider (AsyncNotifier<List<Chat>>)
    └─→ MyChatsNotifier - manages user's chat list
        └─→ uses secureChatServiceProvider for RLS validation

publicChatsProvider (AsyncNotifier<List<PublicChatSummary>>)
    └─→ PublicChatsNotifier - manages public chat discovery + search
        └─→ uses base chatServiceProvider (public data)

chatDetailProvider (StateNotifier<AsyncValue<ChatDetailState>>)
    └─→ ChatDetailNotifier - manages chat room state + realtime subscriptions
        └─→ uses secure providers for participant-specific data

gridRankingProvider (StateNotifier<AsyncValue<GridRankingState>>)
    └─→ GridRankingNotifier - manages grid ranking flow state
```

### Notifier Patterns

**AsyncNotifier Pattern** (for simple async data):

```dart
// lib/providers/notifiers/my_chats_notifier.dart
class MyChatsNotifier extends AsyncNotifier<List<Chat>> {
  @override
  Future<List<Chat>> build() async {
    final chatService = ref.watch(chatServiceProvider);
    final sessionToken = await ref.watch(sessionTokenProvider.future);
    return chatService.getMyChats(sessionToken);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  void removeChat(int chatId) {
    state.whenData((chats) {
      state = AsyncData(chats.where((c) => c.id != chatId).toList());
    });
  }
}
```

**StateNotifier Pattern** (for complex state with subscriptions):

```dart
// lib/providers/notifiers/chat_detail_notifier.dart
class ChatDetailNotifier extends StateNotifier<AsyncValue<ChatDetailState>> {
  final ChatService _chatService;
  RealtimeChannel? _chatChannel;

  ChatDetailNotifier({required ChatService chatService, ...})
      : _chatService = chatService,
        super(const AsyncLoading()) {
    _loadAll();
    _setupSubscriptions();
  }

  Future<void> _loadAll() async {
    // Parallel load of cycle, round, participants, etc.
  }

  void _setupSubscriptions() {
    _chatChannel = _chatService.subscribeToChatChanges(chatId, _onChatChange);
    // ... more subscriptions
  }

  @override
  void dispose() {
    _chatChannel?.unsubscribe();
    super.dispose();
  }
}
```

### Usage in Screens

**Preferred Pattern** (ConsumerWidget with AsyncValue.when):

```dart
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myChatsAsync = ref.watch(myChatsProvider);

    return myChatsAsync.when(
      data: (chats) => _buildChatList(chats),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView.fromError(e, onRetry: () => ref.invalidate(myChatsProvider)),
    );
  }
}
```

**With local UI state** (ConsumerStatefulWidget for TextEditingController, etc.):

```dart
class ChatScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(chatDetailProvider(chatId));

    return detailAsync.when(
      data: (detail) => _buildContent(detail),
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView.fromError(e),
    );
  }
}
```

---

## Real-time Subscriptions

### Subscription Channels

| Channel Pattern | Table | Events | Filter |
|-----------------|-------|--------|--------|
| `chat:{id}` | `chats` | UPDATE | `id = {id}` |
| `rounds:{cycleId}` | `rounds` | ALL | `cycle_id = {cycleId}` |
| `cycles:{chatId}` | `cycles` | ALL | `chat_id = {chatId}` |
| `participants:{chatId}` | `participants` | ALL | `chat_id = {chatId}` |
| `propositions:{roundId}` | `propositions` | INSERT | `round_id = {roundId}` |

### Subscription Lifecycle

```dart
// In StatefulWidget
RealtimeChannel? _channel;

@override
void initState() {
  super.initState();
  _channel = chatService.subscribeToChatChanges(
    chatId,
    (data) => setState(() => _chat = Chat.fromJson(data)),
  );
}

@override
void dispose() {
  _channel?.unsubscribe();
  super.dispose();
}
```

### Debouncing & Rate Limiting

To handle Realtime race conditions (events fire before transactions commit), notifiers use:

1. **Debouncing (150ms):** Coalesces rapid-fire events
2. **Rate Limiting (1s):** Prevents refresh storms

```dart
class MyNotifier extends StateNotifier<AsyncValue<MyState>> {
  Timer? _debounceTimer;
  DateTime? _lastRefreshTime;

  static const _debounceDuration = Duration(milliseconds: 150);
  static const _minRefreshInterval = Duration(seconds: 1);

  void _scheduleRefresh() {
    // Rate limiting: skip if refreshed too recently
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _minRefreshInterval) {
      return;
    }

    // Debouncing: wait for events to settle
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _lastRefreshTime = DateTime.now();
      _refresh();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
```

---

## Authentication Flow

### Anonymous Flow

```
┌─────────┐     ┌─────────────────┐     ┌──────────────────┐
│  User   │────→│ SessionService  │────→│ SecureStorage    │
│ opens   │     │ getSessionToken │     │ read/write UUID  │
│  app    │     └────────┬────────┘     └──────────────────┘
└─────────┘              │
                         ▼
              ┌─────────────────────┐
              │ Token persisted in  │
              │ flutter_secure_storage│
              │ (survives app close)│
              └─────────────────────┘
```

### Authenticated Flow (Future)

```
┌─────────┐     ┌─────────────────┐     ┌──────────────────┐
│  User   │────→│ Supabase Auth   │────→│ Google OAuth /   │
│ signs   │     │                 │     │ Magic Link       │
│  in     │     └────────┬────────┘     └──────────────────┘
└─────────┘              │
                         ▼
              ┌─────────────────────┐
              │ Link session_token  │
              │ to user_id in       │
              │ participants table  │
              └─────────────────────┘
```

---

## Consensus Algorithm

### N-in-a-Row Rule (Configurable)

The number of consecutive wins required is configurable via `confirmation_rounds_required` (default: 2, range: 1-10).

**Example with confirmation_rounds_required = 2 (default):**
```
Cycle 1:
  Round 1: Winner = Proposition A
  Round 2: Winner = Proposition B  (different → continue)
  Round 3: Winner = Proposition B  (same → 2-in-a-row → CONSENSUS!)
                        ↓
              Cycle 1 complete, Proposition B is permanent winner
                        ↓
              New Cycle 2 auto-created
```

**Example with confirmation_rounds_required = 1:**
```
Cycle 1:
  Round 1: Winner = Proposition A  (1-in-a-row → CONSENSUS!)
                        ↓
              Cycle 1 complete immediately after first round
```

**Example with confirmation_rounds_required = 3:**
```
Cycle 1:
  Round 1: Winner = Proposition A
  Round 2: Winner = Proposition A  (2 in a row, need 3)
  Round 3: Winner = Proposition A  (3-in-a-row → CONSENSUS!)
```

### Tie Handling

When multiple propositions have equal (or near-equal within 0.001 tolerance) MOVDA scores, they are ALL recorded as winners in the `round_winners` table. However, **only sole wins count toward consensus**.

**Key rules:**
- Sole winner: `is_sole_winner = TRUE` → counts toward consecutive wins
- Tied winners: `is_sole_winner = FALSE` → does NOT count toward consensus
- Ties break the consecutive win chain
- The oldest proposition among ties is used for `winning_proposition_id` (backward compatibility)

**Example with ties (confirmation_rounds_required = 2):**
```
Cycle 1:
  Round 1: Winner = A (sole)         → consecutive = 1
  Round 2: Winner = A+B (tie)        → consecutive = 0 (tie breaks chain!)
  Round 3: Winner = A (sole)         → consecutive = 1 (fresh start)
  Round 4: Winner = A (sole)         → consecutive = 2 → CONSENSUS!
```

**UI displays all tied winners** with navigation arrows to cycle through them, and shows a "X-WAY TIE" badge.

### Phase Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   WAITING   │────→│  PROPOSING  │────→│   RATING    │
│ (host start)│     │ (timer runs)│     │ (timer runs)│
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                                               ▼
                                      ┌─────────────────┐
                                      │ Calculate Winner │
                                      │ (MOVDA algorithm)│
                                      └────────┬────────┘
                                               │
                    ┌──────────────────────────┼──────────────────────────┐
                    │                          │                          │
                    ▼                          ▼                          ▼
         ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
         │ Same as last    │      │ Different from  │      │ First round     │
         │ round winner    │      │ last round      │      │ of cycle        │
         │  → N-in-a-row?  │      │     → Continue  │      │     → Continue  │
         └────────┬────────┘      └────────┬────────┘      └────────┬────────┘
                  │                        │                        │
                  ▼                        └────────────┬───────────┘
         ┌─────────────────┐                           │
         │ CYCLE COMPLETE  │                           ▼
         │ Set cycle winner│               ┌─────────────────────┐
         │ Create new cycle│               │ NEW ROUND           │
         └─────────────────┘               │ (same cycle)        │
                                           │ Start in PROPOSING  │
                                           └─────────────────────┘
```

### Timer & Threshold Logic

**Advance Phase When:**
1. Timer expires AND minimum met, OR
2. Auto-advance threshold met (both % AND count)

**Extend Timer When:**
- Timer expires but minimum NOT met
- Extension = full duration again (no limit)

```
if (timer_expired) {
  if (minimum_met) {
    advance_phase();
  } else {
    extend_timer(full_duration);
  }
}

if (threshold_percent_met AND threshold_count_met AND minimum_met) {
  advance_phase();  // Early advance
}
```

---

## Edge Functions

### Overview

Supabase Edge Functions handle background processing that can't be done purely in the database or client.

| Function | Purpose | Trigger | JWT Verify |
|----------|---------|---------|------------|
| `process-timers` | Phase advancement, winner calculation, auto-start | Cron (every minute) | No (uses X-Cron-Secret) |
| `process-auto-refill` | Automatic credit refills when balance low | Cron (every minute) | No (uses X-Cron-Secret) |
| `translate` | AI-powered translations of chat content | DB trigger (pg_net) | No (uses service role key) |
| `health` | Health check endpoint for deployment verification | HTTP GET | No (public) |
| `stripe-webhook` | Stripe payment event processing | Stripe webhook | No (uses Stripe signature) |
| `create-checkout-session` | Create Stripe checkout for credit purchase | HTTP POST | Yes |
| `setup-payment-method` | Setup Stripe payment method for auto-refill | HTTP POST | Yes |
| `confirm-payment-method` | Confirm Stripe SetupIntent | HTTP POST | Yes |
| `send-email` | Transactional emails (invites, receipts) | HTTP POST | Yes |

### process-timers

**Location:** `supabase/functions/process-timers/index.ts`

**Schedule:** Runs every minute via Supabase Cron

**Responsibilities:**

| Task | Description |
|------|-------------|
| **Expired Timer Processing** | Check rounds where `phase_ends_at < NOW()` |
| **Auto-Advance Thresholds** | Check if threshold % AND count met for early advance |
| **Auto-Start** | Start waiting rounds when participant count reached |
| **Winner Calculation** | Calculate average ratings and set round winner |

### Function Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    process-timers                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. EXPIRED TIMERS                                          │
│     ├─ Find rounds: phase_ends_at < NOW()               │
│     ├─ For each:                                            │
│     │   ├─ Check minimum met?                               │
│     │   │   ├─ YES → Advance phase                          │
│     │   │   └─ NO  → Extend timer by duration               │
│     │   └─ If rating phase → Calculate winner               │
│                                                              │
│  2. AUTO-ADVANCE (early advance)                            │
│     ├─ Find active rounds (not expired)                 │
│     ├─ Check threshold % AND count met                      │
│     └─ If both met → Advance phase early                    │
│                                                              │
│  3. AUTO-START                                              │
│     ├─ Find waiting rounds with auto start_mode         │
│     ├─ Count active participants                            │
│     └─ If count >= auto_start_participant_count → Start     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Response Format

```json
{
  "rounds_checked": 5,
  "phases_advanced": 2,
  "timers_extended": 1,
  "auto_started": 0,
  "errors": []
}
```

### Testing Edge Functions

All Edge Functions have comprehensive Deno test suites covering authentication, validation, CORS, and rate limiting.

```bash
# Start local Supabase
supabase start

# Serve functions locally (in separate terminal)
supabase functions serve <function-name>

# Run Deno tests
deno test --allow-all supabase/functions/tests/<function>-test.ts

# Run all Edge Function tests
deno test --allow-all supabase/functions/tests/
```

**Test files:**
| Function | Test File | Tests |
|----------|-----------|-------|
| process-timers | process-timers-test.ts | Timer lifecycle, cron auth |
| stripe-webhook | stripe-webhook-test.ts | Signature verification, idempotency |
| create-checkout-session | create-checkout-session-test.ts | Auth, validation, rate limiting |
| setup-payment-method | setup-payment-method-test.ts | Auth, Stripe customer handling |
| confirm-payment-method | confirm-payment-method-test.ts | SetupIntent validation |
| process-auto-refill | process-auto-refill-test.ts | Queue management, error tracking |
| send-email | send-email-test.ts | Email types, XSS prevention |

---

## Time-Based Flows

### Timer Lifecycle

```
┌─────────────┐
│   WAITING   │ ← No timer (phase_ends_at = NULL)
└──────┬──────┘
       │ Host clicks "Start" OR auto-start triggered
       ▼
┌─────────────────────────────────────────────────────────────┐
│                      PROPOSING                               │
│  phase_started_at = NOW()                                   │
│  phase_ends_at = NOW() + proposing_duration_seconds         │
└──────┬──────────────────────────────────────────────────────┘
       │
       │ Timer expires OR auto-advance threshold met
       │
       ├─── Minimum NOT met → EXTEND (phase_ends_at += duration)
       │
       └─── Minimum met ↓
       ▼
┌─────────────────────────────────────────────────────────────┐
│                       RATING                                 │
│  phase_started_at = NOW()                                   │
│  phase_ends_at = NOW() + rating_duration_seconds            │
└──────┬──────────────────────────────────────────────────────┘
       │
       │ Timer expires OR auto-advance threshold met
       │
       ├─── Minimum NOT met → EXTEND (phase_ends_at += duration)
       │
       └─── Minimum met ↓
       ▼
┌─────────────────────────────────────────────────────────────┐
│                  CALCULATE WINNER                            │
│  1. Average ratings per proposition                         │
│  2. Set winning_proposition_id                              │
│  3. Trigger checks N-in-a-row (configurable)                │
│  4. Create next round OR complete cycle                 │
└─────────────────────────────────────────────────────────────┘
```

### Minimum Requirements (Stop Loss)

| Phase | Setting | Default | Check |
|-------|---------|---------|-------|
| Proposing | `proposing_minimum` | 2 | Count of propositions |
| Rating | `rating_minimum` | 2 | Avg raters per proposition |

**If minimum NOT met when timer expires:**
- Timer extends by full duration
- No limit on extensions
- Phase stays the same

### Auto-Advance Thresholds (Take Profit)

| Phase | Percent Setting | Count Setting |
|-------|-----------------|---------------|
| Proposing | `proposing_threshold_percent` | `proposing_threshold_count` |
| Rating | `rating_threshold_percent` | `rating_threshold_count` |

**Logic:** `MAX(percent_required, count_required)` - both must be met

**Example:**
```
Participants: 10
Threshold %: 80% → 8 required
Threshold #: 5

Required = MAX(8, 5) = 8 participants must have acted
```

### Auto-Start Flow

For auto-mode chats, rounds are created directly in the appropriate phase:

**When a round is created (first join, after round completion, or after consensus):**
- If `start_mode = 'auto'` AND `active_participants >= auto_start_participant_count`:
  - Round created in **PROPOSING** phase immediately (no waiting)
- Otherwise:
  - Round created in **WAITING** phase (cron job will start when conditions met)

```
┌─────────────────────────────────────────────────────────────┐
│ Chat Settings:                                              │
│   start_mode = 'auto'                                       │
│   auto_start_participant_count = 3                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SCENARIO A: Conditions met at round creation               │
│  (e.g., 3+ participants when round winner set)              │
│           │                                                  │
│           └─→ Round created directly in PROPOSING           │
│               phase_started_at = NOW()                      │
│               phase_ends_at = calculate_round_minute_end()  │
│                                                              │
│  SCENARIO B: Conditions NOT met at round creation           │
│  (e.g., only 3 participants)                                │
│           │                                                  │
│           └─→ Round created in WAITING phase                │
│                       │                                      │
│                       │ [process-timers runs every minute]  │
│                       │                                      │
│                       ├─── Participants < 3 → Stay WAITING  │
│                       │                                      │
│                       └─── Participants >= 3 ↓              │
│                                                              │
│               Transition to PROPOSING:                      │
│                 phase = 'proposing'                         │
│                 phase_started_at = NOW()                    │
│                 phase_ends_at = NOW() + duration            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Helper Function:** `create_round_for_cycle(cycle_id, chat_id, custom_id)` handles this logic and is used by:
- `on_round_winner_set` (creating next round in same cycle)
- `on_cycle_winner_set` (creating first round in new cycle)
- `check_auto_start_on_participant_join` (creating first round when threshold met)

### Pause/Resume Mechanism

The timer can be paused by two independent mechanisms:

| Pause Type | Column | Controlled By | Trigger |
|------------|--------|---------------|---------|
| Schedule Pause | `chats.schedule_paused` | System | Schedule windows (recurring) |
| Host Pause | `chats.host_paused` | Host | Manual button in UI |

**Combined check:** `is_chat_paused(chat_id)` returns `schedule_paused OR host_paused`

#### Timer State During Pause

```
ACTIVE (timer running):
  rounds.phase_ends_at = <future timestamp>      ← Edge Function processes this
  rounds.phase_time_remaining_seconds = NULL

PAUSED (timer frozen):
  rounds.phase_ends_at = NULL                    ← Edge Function ignores (no match)
  rounds.phase_time_remaining_seconds = <saved>  ← Preserved for resume
```

**Key insight:** Setting `phase_ends_at = NULL` naturally stops the timer because the Edge Function queries for `phase_ends_at < NOW()`. A NULL value never matches.

#### Pause/Resume Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│                    Pause Lifecycle                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PAUSE (host_pause_chat or schedule triggers):              │
│    1. Calculate remaining: phase_ends_at - NOW()            │
│    2. Save: phase_time_remaining_seconds = remaining        │
│    3. Stop: phase_ends_at = NULL                            │
│    4. Flag: host_paused = TRUE (or schedule_paused = TRUE)  │
│                                                              │
│  RESUME (host_resume_chat or schedule triggers):            │
│    1. Clear flag: host_paused = FALSE                       │
│    2. Check: is_chat_paused() still true?                   │
│       ├─ YES → Keep timer frozen (other pause active)       │
│       └─ NO  → Restore timer:                               │
│                phase_ends_at = NOW() + saved_time           │
│                phase_time_remaining_seconds = NULL          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Database vs Edge Function Responsibilities

| Responsibility | Where | How |
|----------------|-------|-----|
| Store timer settings | Database | `chats` table columns |
| Track phase state | Database | `rounds.phase`, `phase_ends_at` |
| Check timer expiration | Edge Function | `process-timers` cron job |
| Extend expired timer | Edge Function | UPDATE `phase_ends_at` |
| Advance phase | Edge Function | UPDATE `phase`, `phase_started_at` |
| Calculate winner | Edge Function | AVG ratings, UPDATE winner |
| Create next round | Database Trigger | `on_round_winner_set` → `create_round_for_cycle()` |
| Create new cycle | Database Trigger | `on_cycle_winner_set` → `create_round_for_cycle()` |
| Create round in correct phase | Database Function | `create_round_for_cycle()` (auto checks conditions) |
| Pause timer (host) | Database Function | `host_pause_chat()` SECURITY DEFINER |
| Resume timer (host) | Database Function | `host_resume_chat()` SECURITY DEFINER |
| Pause timer (schedule) | Database Function | `schedule_pause_chat()` |
| Resume timer (schedule) | Database Function | `schedule_resume_chat()` |

### Cron Job Setup

```sql
-- In Supabase Dashboard > Database > Extensions
-- Enable pg_cron and pg_net extensions

-- Schedule process-timers to run every minute
SELECT cron.schedule(
  'process-timers',
  '* * * * *',  -- Every minute
  $$
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT.supabase.co/functions/v1/process-timers',
    headers := '{"Content-Type": "application/json", "X-Cron-Secret": "YOUR_CRON_SECRET"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);

-- Schedule process-auto-refill to run every minute
SELECT cron.schedule(
  'process-auto-refills',
  '* * * * *',  -- Every minute
  $$
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT.supabase.co/functions/v1/process-auto-refill',
    headers := '{"Content-Type": "application/json", "X-Cron-Secret": "YOUR_CRON_SECRET"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
```

**Note:** The `X-Cron-Secret` header value must exactly match the `CRON_SECRET` Edge Function secret.

---

## Email Service

### Overview

OneMind uses Resend for transactional emails. The `send-email` Edge Function handles all email sending.

### Email Types

| Type | Template | Trigger |
|------|----------|---------|
| `welcome` | Welcome new user | User signup |
| `invite` | Chat invitation | Host invites someone |
| `receipt` | Payment receipt | Credit purchase |

### Edge Function: send-email

**Location:** `supabase/functions/send-email/index.ts`

**Request Format:**
```json
{
  "type": "welcome" | "invite" | "receipt",
  "to": "user@example.com",
  ...typeSpecificParams
}
```

**Welcome Email:**
```json
{
  "type": "welcome",
  "to": "user@example.com",
  "userName": "Joel"
}
```

**Invite Email:**
```json
{
  "type": "invite",
  "to": "friend@example.com",
  "inviterName": "Joel",
  "chatName": "Team Decisions",
  "inviteCode": "A7X3K9",
  "message": "Join us!"
}
```

**Receipt Email:**
```json
{
  "type": "receipt",
  "to": "user@example.com",
  "userName": "Joel",
  "credits": 100,
  "amount": 9.99,
  "transactionId": "txn_123"
}
```

### Configuration

| Secret | Description | Example |
|--------|-------------|---------|
| `RESEND_API_KEY` | Resend API key | `re_xxxxx` |
| `FROM_EMAIL` | Sender address | `OneMind <hello@mail.onemind.life>` |
| `REPLY_TO_EMAIL` | Reply-to address | `joel@onemind.life` |
| `APP_URL` | App base URL | `https://onemind.life` |

### Setup

```bash
# Set Resend API key
supabase secrets set RESEND_API_KEY=re_YOUR_KEY

# Optional overrides (have sensible defaults)
supabase secrets set FROM_EMAIL='OneMind <hello@mail.onemind.life>'
supabase secrets set REPLY_TO_EMAIL='support@onemind.life'
supabase secrets set APP_URL='https://onemind.life'
```

---

## Billing & Payments

### Overview

OneMind uses a credit-based billing system. Users purchase credits which are consumed when creating chats or using premium features.

### Credit System

| Action | Cost | Notes |
|--------|------|-------|
| Create Chat | 1 credit | Per chat created |
| Premium Features | Variable | Based on feature |

### BillingService

**Location:** `lib/services/billing_service.dart`

| Method | Returns | Description |
|--------|---------|-------------|
| `getCredits(userId)` | `Future<int>` | Get user's credit balance |
| `purchaseCredits(amount)` | `Future<bool>` | Purchase credits |
| `consumeCredits(amount)` | `Future<bool>` | Use credits for action |
| `getTransactionHistory(userId)` | `Future<List<Transaction>>` | Get purchase history |

### Payment Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Payment Flow                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. User selects credit package                             │
│     └─→ Package options: 100, 500, 1000 credits             │
│                                                              │
│  2. Checkout initiated                                       │
│     └─→ logCheckoutStarted() analytics event                │
│                                                              │
│  3. Payment processor (Stripe)                              │
│     └─→ Secure payment handled externally                   │
│                                                              │
│  4. Webhook confirms payment                                 │
│     └─→ Credits added to user account                       │
│     └─→ Receipt email sent via send-email Edge Function     │
│     └─→ logPurchaseCompleted() analytics event              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Auto-Refill

Users can enable auto-refill to automatically purchase credits when balance falls below a threshold.

| Setting | Description |
|---------|-------------|
| `auto_refill_enabled` | Enable/disable auto-refill |
| `auto_refill_threshold` | Credit balance that triggers refill |
| `auto_refill_amount` | Number of credits to purchase |

---

## Scheduled Chats *(Not Yet Implemented)*

### Overview

> **Note:** Scheduled mode is designed but not yet implemented. The UI is hidden until the pause/resume logic for time windows is built.

Chats can be scheduled to start at specific times rather than immediately. This is useful for recurring meetings or time-boxed discussions.

### Schedule Types

| Type | Description |
|------|-------------|
| `once` | One-time scheduled start |
| `recurring` | Repeats on specified days within time window |

### Database Fields

```sql
-- In chats table
schedule_type         -- 'once' or 'recurring'
schedule_timezone     -- e.g., 'America/New_York'
scheduled_start_at    -- For one-time schedules
schedule_days         -- Array of days: ['mon', 'tue', 'wed', ...]
schedule_start_time   -- Daily start time (TIME)
schedule_end_time     -- Daily end time (TIME)
visible_outside_schedule -- Show chat outside active hours
```

### One-Time Schedule

```
┌─────────────────────────────────────────────────────────────┐
│  Schedule Type: once                                         │
│  scheduled_start_at: 2024-01-15T14:00:00Z                   │
│                                                              │
│  Before: Chat visible, round in WAITING phase            │
│  At scheduled time: Auto-transitions to PROPOSING           │
│  After: Normal phase flow continues                         │
└─────────────────────────────────────────────────────────────┘
```

### Recurring Schedule

```
┌─────────────────────────────────────────────────────────────┐
│  Schedule Type: recurring                                    │
│  schedule_days: ['mon', 'wed', 'fri']                       │
│  schedule_start_time: 09:00:00                              │
│  schedule_end_time: 17:00:00                                │
│  schedule_timezone: 'America/New_York'                      │
│                                                              │
│  Behavior:                                                   │
│  - Active window: Mon/Wed/Fri 9am-5pm ET                    │
│  - Inside window: Normal operation                          │
│  - Outside window (visible_outside_schedule=true):          │
│    Chat visible but read-only                               │
│  - Outside window (visible_outside_schedule=false):         │
│    Chat hidden from list                                    │
└─────────────────────────────────────────────────────────────┘
```

### UI: Schedule Settings Card

The Create Chat screen includes a ScheduleSettingsCard with:
- One-time vs Recurring toggle
- Date/time picker for one-time
- Day chips (Mon-Sun) for recurring
- Start/end time pickers
- Timezone selector
- "Visible outside schedule" toggle

---

## Adaptive Duration

### Overview

Adaptive duration automatically adjusts phase timers based on participation levels. This helps balance between slow-moving discussions (need more time) and fast-moving ones (don't need full timer).

### Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `adaptive_duration_enabled` | FALSE | Enable adaptive timing |
| `adaptive_threshold_count` | 10 | Participants before adaptation triggers |
| `adaptive_adjustment_percent` | 10 | Max % to adjust duration |
| `min_phase_duration_seconds` | 60 | Floor for duration (1 minute) |
| `max_phase_duration_seconds` | 86400 | Ceiling for duration (1 day) |

### Adaptation Logic

```
┌─────────────────────────────────────────────────────────────┐
│                    Adaptive Duration                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Base Duration: 1 hour (3600 seconds)                       │
│  Adjustment: 10%                                            │
│  Threshold: 10 participants                                 │
│                                                              │
│  Scenario A: High participation (fast responses)            │
│  - 90% complete in first 30 min                             │
│  - Next phase: 3600 - 10% = 3240 seconds                    │
│                                                              │
│  Scenario B: Low participation (slow responses)             │
│  - Only 50% complete when timer expires                     │
│  - Next phase: 3600 + 10% = 3960 seconds                    │
│                                                              │
│  Constraints:                                                │
│  - Never below min_phase_duration_seconds                   │
│  - Never above max_phase_duration_seconds                   │
│  - Only adapts after adaptive_threshold_count reached       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Database Fields

```sql
-- In chats table
adaptive_duration_enabled      BOOLEAN DEFAULT FALSE
adaptive_threshold_count       INT DEFAULT 10
adaptive_adjustment_percent    INT DEFAULT 10
min_phase_duration_seconds     INT DEFAULT 60
max_phase_duration_seconds     INT DEFAULT 86400
```

---

## Email Invitations

### Overview

The invite system allows hosts to send email invitations to specific people. This is especially useful for `invite_only` access method chats.

### InviteService

**Location:** `lib/services/invite_service.dart`

| Method | Returns | Description |
|--------|---------|-------------|
| `createInvite(...)` | `Future<String>` | Create invite and send email |
| `sendInvites(...)` | `Future<Map<String, String>>` | Batch invite multiple emails |
| `getPendingInvites(chatId)` | `Future<List<Map>>` | Get pending invites |
| `resendInvite(...)` | `Future<void>` | Resend invite email |
| `cancelInvite(token)` | `Future<void>` | Cancel pending invite |
| `validateInviteByEmail(...)` | `Future<String?>` | Validate email has invite |
| `acceptInvite(...)` | `Future<bool>` | Mark invite as accepted |
| `isInviteOnly(chatId)` | `Future<bool>` | Check if chat requires invite |

### Invite Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Email Invite Flow                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. HOST: Adds email addresses in EmailInviteSection        │
│     └─→ Validates email format                              │
│     └─→ Prevents duplicates                                 │
│                                                              │
│  2. SYSTEM: Creates invite records                          │
│     └─→ INSERT INTO invites (chat_id, email, ...)          │
│     └─→ Generate unique invite_token                        │
│                                                              │
│  3. SYSTEM: Sends invite emails                             │
│     └─→ Calls send-email Edge Function                      │
│     └─→ Email contains invite code + deep link              │
│                                                              │
│  4. INVITEE: Opens app or link                              │
│     ├─→ /join/CODE route                                    │
│     └─→ Prompted to verify email                            │
│                                                              │
│  5. SYSTEM: Validates invite                                │
│     └─→ RPC: validate_invite_email(chat_id, email)         │
│     └─→ Returns invite_token if valid                       │
│                                                              │
│  6. INVITEE: Joins chat                                     │
│     └─→ RPC: accept_invite(token, participant_id)          │
│     └─→ Invite status → 'accepted'                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- invites table
CREATE TABLE invites (
  id SERIAL PRIMARY KEY,
  chat_id INT REFERENCES chats(id),
  email TEXT NOT NULL,
  invite_token UUID DEFAULT gen_random_uuid(),
  invited_by INT REFERENCES participants(id),
  accepted_by INT REFERENCES participants(id),
  status TEXT DEFAULT 'pending',  -- pending, accepted, expired
  created_at TIMESTAMPTZ DEFAULT NOW(),
  accepted_at TIMESTAMPTZ
);

-- RPC functions
validate_invite_email(p_chat_id, p_email) -- Returns invite_token
accept_invite(p_invite_token, p_participant_id) -- Returns boolean
```

### UI: EmailInviteSection Widget

The Create Chat screen includes an EmailInviteSection for `invite_only` chats:
- Email input with validation
- Add button (validates format, prevents duplicates)
- List of added emails with remove option
- Emails are sent after chat creation

### Email Normalization

All emails are normalized before storage and comparison:
```dart
email.toLowerCase().trim()
```

---

## Analytics & Error Tracking

### Firebase Integration

OneMind uses Firebase for both analytics and crash reporting.

### Analytics Events

| Event | When | Parameters |
|-------|------|------------|
| `chat_created` | User creates a chat | `chat_id`, `is_official`, `access_method` |
| `chat_joined` | User joins a chat | `chat_id`, `is_official`, `method` |
| `proposition_submitted` | User submits proposition | `chat_id`, `round_id` |
| `rating_completed` | User completes rating | `chat_id`, `round_id`, `propositions_rated` |
| `consensus_reached` | Cycle completes | `chat_id`, `cycle_id`, `rounds_count` |
| `purchase_completed` | Credit purchase | `credits`, `amount`, `currency` |

### AnalyticsService

**Location:** `lib/services/analytics_service.dart`

```dart
final analyticsService = ref.read(analyticsServiceProvider);

// Log events
await analyticsService.logChatCreated(chatId: '123', isOfficial: false);
await analyticsService.logPropositionSubmitted(chatId: '123', roundId: 1);
```

### Error Tracking (Sentry)

Errors are captured via Sentry for web:

1. **SentryFlutter.init:** Wraps app for automatic error capture
2. **Custom Errors:** `ErrorHandler.reportCallback`
3. **Breadcrumbs:** Log trail for debugging

```dart
// Custom error reporting
ErrorHandler(
  reportCallback: (error, stackTrace) async {
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('error_code', error.codeString);
      },
    );
  },
);
```

### Setup

1. Run `flutterfire configure` to generate `firebase_options.dart` (for Analytics)
2. Configure Sentry DSN at build time:

```bash
flutter build web --dart-define=SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
```

3. Sentry is optional - app runs without DSN, just skips error tracking

---

## Security

### Security Headers

All Edge Functions include security headers via `_shared/cors.ts`:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevent MIME sniffing |
| `X-Frame-Options` | `DENY` | Prevent clickjacking |
| `Strict-Transport-Security` | `max-age=31536000` | Force HTTPS |
| `X-XSS-Protection` | `1; mode=block` | XSS protection (legacy browsers) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Control referrer |
| `Permissions-Policy` | `camera=(), microphone=()` | Restrict permissions |

### CORS Configuration

```typescript
// Default: localhost only (development)
// Production: Set ALLOWED_ORIGINS secret
supabase secrets set ALLOWED_ORIGINS='https://onemind.life,https://app.onemind.life'
```

### Authentication

- **User calls:** Require valid JWT in `Authorization` header
- **Internal calls:** Use `X-Internal-Call: true` header (server-to-server only)
- **JWT verification:** Enabled on all Edge Functions by default

---

## Deployment Guide

### Prerequisites

1. Supabase account (https://supabase.com)
2. Flutter SDK 3.10+
3. Dart SDK 3.0+
4. Firebase project (for Analytics)
5. Sentry account (optional, for error tracking)
6. Resend account (for transactional emails)
7. Stripe account (for payments)

### Step 1: Create Supabase Project

1. Go to https://app.supabase.com
2. Create new project in your organization
3. Choose region closest to your users
4. Save the project URL and anon key

### Step 2: Configure Flutter App

```dart
// lib/config/supabase_config.dart
class SupabaseConfig {
  static const String url = 'https://YOUR_PROJECT.supabase.co';
  static const String anonKey = 'YOUR_ANON_KEY';
}
```

Or use environment variables:
```bash
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
```

### Step 3: Apply Database Migrations

```bash
# Install Supabase CLI
npm install -g supabase

# Link to your project
supabase link --project-ref YOUR_PROJECT_REF

# Apply migrations
supabase db push
```

### Step 4: Run Database Tests

```bash
# Start local Supabase (optional, for local testing)
supabase start

# Run pgtap tests
supabase test db
```

### Step 5: Create Official Chat

```sql
-- Run in Supabase SQL Editor
INSERT INTO chats (
  name,
  initial_message,
  description,
  is_official,
  is_active
) VALUES (
  'OneMind',
  'What should humanity focus on?',
  'The official OneMind chat - humanity''s public square for collective alignment.',
  TRUE,
  TRUE
);
```

### Step 6: Run Flutter App

```bash
# Install dependencies
flutter pub get

# Run tests
flutter test

# Run app
flutter run
```

### Environment-Specific Configurations

| Environment | Supabase Project | Notes |
|-------------|------------------|-------|
| Development | Local or dev project | `supabase start` for local |
| Staging | Staging project | Test with real data |
| Production | Production project | Live user data |

---

## Directory Structure

```
onemind_app/
├── docs/
│   ├── DESIGN.md          # Design decisions & UI spec
│   └── ARCHITECTURE.md    # This file
├── lib/
│   ├── config/            # Configuration
│   ├── core/              # Core utilities (errors, api client)
│   ├── models/            # Data models
│   ├── providers/         # Riverpod providers
│   │   ├── providers.dart         # Service providers
│   │   ├── chat_providers.dart    # Screen state providers
│   │   └── notifiers/             # State notifiers
│   │       ├── my_chats_notifier.dart
│   │       ├── public_chats_notifier.dart
│   │       ├── chat_detail_notifier.dart
│   │       └── grid_ranking_notifier.dart
│   ├── screens/           # UI screens
│   ├── services/          # Business logic
│   ├── widgets/           # Reusable widgets
│   └── main.dart          # App entry point
├── test/
│   ├── fixtures/          # Test data factories
│   ├── helpers/           # Test utilities
│   ├── mocks/             # Mock implementations
│   ├── models/            # Model tests
│   ├── providers/         # Provider & notifier tests
│   │   └── notifiers/     # Notifier unit tests
│   ├── services/          # Service tests
│   ├── screens/           # Screen widget tests
│   └── widgets/           # Widget tests
├── supabase/
│   ├── functions/         # Edge Functions
│   │   ├── process-timers/    # Timer management function
│   │   │   └── index.ts
│   │   └── tests/             # Deno tests for edge functions
│   │       └── process-timers-test.ts
│   ├── migrations/        # Database migrations
│   └── tests/             # pgtap database tests (614 tests)
├── pubspec.yaml           # Dependencies
└── README.md              # Quick start guide
```

---

## Related Documentation

- [README.md](../README.md) - Quick start guide
- [DESIGN.md](./DESIGN.md) - Design decisions, schema, UI specification
