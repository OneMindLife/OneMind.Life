# OneMind

**OneMind is a collective alignment platform for humanity.**

It enhances cooperation through shared direction via a convergence mechanism. Any group of people can use OneMind to reach consensus on ideas through structured, democratic deliberation.

## How It Works

1. Someone poses a question/topic (seed)
2. Participants submit propositions (anonymous)
3. Participants rank propositions (grid ranking)
4. Winner determined by MOVDA algorithm
5. If same proposition wins **N rounds in a row** → consensus reached (N is configurable, default 2)
6. If not → new round, repeat

## Who Is It For?

**Everyone.** Any humans who work together:
- Classrooms & research institutions
- Families & friend groups
- Private sector teams
- Emergency response teams
- Global conversations
- Any group seeking shared direction

## Features

- **Anonymous propositions** - Nobody can see who proposed what
- **Democratic rating** - All participants rank propositions via grid ranking
- **Zoom-like access** - 6-character invite codes, no sign-up required
- **Optional authentication** - Google OAuth or Magic Link for persistence
- **Real-time updates** - See changes as they happen
- **Flexible settings** - Timers, thresholds, approval requirements

## Getting Started

### Prerequisites

- Flutter SDK 3.10+
- Dart SDK 3.0+
- Supabase account

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd onemind_app

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Configuration

Create a `.env` file or configure `lib/config/supabase_config.dart` with your Supabase credentials:

```dart
const supabaseUrl = 'YOUR_SUPABASE_URL';
const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

## Project Structure

```
lib/
├── config/          # Supabase configuration
├── core/            # Core utilities (errors, api client)
├── models/          # Data models (Chat, Participant, Round, etc.)
├── providers/       # Riverpod providers
│   ├── providers.dart         # Service providers
│   ├── chat_providers.dart    # Screen state providers
│   └── notifiers/             # State notifiers (MyChats, PublicChats, ChatDetail, GridRanking)
├── screens/         # UI screens
│   ├── chat/        # Chat room
│   ├── create/      # Create chat flow
│   ├── discover/    # Public chat discovery
│   ├── home/        # Home screen
│   └── join/        # Join chat dialog
├── services/        # Business logic & API calls
│   ├── chat_service.dart         # Chats, cycles, rounds
│   ├── participant_service.dart  # Join, kick, approvals
│   ├── proposition_service.dart  # Submit/rate ideas
│   ├── session_service.dart      # Anonymous identity
│   ├── invite_service.dart       # Email invitations
│   ├── analytics_service.dart    # Firebase Analytics
│   ├── billing_service.dart      # Stripe payments
│   └── winner_calculator.dart    # Consensus calculation
└── widgets/         # Reusable widgets (error views, grid ranking, etc.)

test/
├── fixtures/        # Test data factories
├── helpers/         # Test utilities
├── mocks/           # Mock implementations
├── models/          # Model unit tests
├── providers/       # Provider & notifier tests
├── services/        # Service tests
├── screens/         # Screen widget tests
└── widgets/         # Widget tests

supabase/
├── functions/       # Edge Functions with tests
└── tests/           # pgtap database tests (614 tests)
```

## Testing

```bash
# Run all Flutter tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/models/chat_test.dart
```

### Test Coverage

| Layer | Tests | Coverage |
|-------|-------|----------|
| pgtap Database | 614 | Schema, RLS, triggers, consensus, billing |
| Edge Functions | 57 | Auth, validation, CORS, rate limiting |
| Flutter Total | 1035 | Comprehensive |
| - Models | 40+ | Chat, Round, Proposition, etc. |
| - Services | 60+ | All services with mocked Supabase |
| - Providers/Notifiers | 44 | MyChats, PublicChats, ChatDetail, GridRanking |
| - Screens | 200+ | Widget tests for all screens |
| - Core/API | 50+ | Error handling, API client |

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Quick start guide (this file) |
| [DESIGN.md](docs/DESIGN.md) | Design decisions, database schema, UI specification |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture, service APIs, deployment guide |

## Tech Stack

- **Frontend**: Flutter + Riverpod
- **Backend**: Supabase (PostgreSQL + Realtime + Auth)
- **Testing**: flutter_test, mocktail, pgtap

## License

AGPL-3.0 - See [LICENSE](LICENSE)
