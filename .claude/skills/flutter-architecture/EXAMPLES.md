# Code Examples

## Service Example

```dart
// lib/services/chat_service.dart
class ChatService {
  final SupabaseClient _supabase;

  ChatService(this._supabase);

  Future<Chat> getChat(int chatId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw AppException.authRequired(
        message: 'User must be signed in to view chat',
      );
    }

    final response = await _supabase
        .from('chats')
        .select()
        .eq('id', chatId)
        .single();

    return Chat.fromJson(response);
  }
}
```

## Provider Example

```dart
// lib/providers/providers.dart
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(supabaseProvider));
});

final chatDetailProvider = StateNotifierProvider.autoDispose
    .family<ChatDetailNotifier, AsyncValue<ChatDetailState>, ChatDetailParams>(
  (ref, params) => ChatDetailNotifier(
    ref: ref,
    chatId: params.chatId,
    showPreviousResults: params.showPreviousResults,
  ),
);
```

## Notifier Example

```dart
// lib/providers/notifiers/my_chats_notifier.dart
class MyChatsState extends Equatable {
  final List<Chat> chats;
  final List<JoinRequest> pendingRequests;

  const MyChatsState({
    this.chats = const [],
    this.pendingRequests = const [],
  });

  @override
  List<Object?> get props => [chats, pendingRequests];
}

class MyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>> {
  final ChatService _chatService;
  Timer? _debounceTimer;
  DateTime? _lastRefreshTime;

  static const _debounceDuration = Duration(milliseconds: 150);
  static const _minRefreshInterval = Duration(seconds: 1);

  MyChatsNotifier(Ref ref)
      : _chatService = ref.read(chatServiceProvider),
        super(const AsyncLoading()) {
    _loadData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final chats = await _chatService.getMyChats();
      state = AsyncData(MyChatsState(chats: chats));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
```

## Model Example

```dart
// lib/models/round.dart
enum RoundPhase { waiting, proposing, rating }

class Round extends Equatable {
  final int id;
  final int cycleId;
  final RoundPhase phase;
  final DateTime createdAt;

  const Round({
    required this.id,
    required this.cycleId,
    required this.phase,
    required this.createdAt,
  });

  factory Round.fromJson(Map<String, dynamic> json) {
    return Round(
      id: json['id'] as int,
      cycleId: json['cycle_id'] as int,
      phase: _parsePhase(json['phase'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static RoundPhase _parsePhase(String? phase) {
    switch (phase) {
      case 'proposing': return RoundPhase.proposing;
      case 'rating': return RoundPhase.rating;
      case 'waiting':
      case null: return RoundPhase.waiting;
      default:
        throw AppException.validation(
          message: 'Unknown round phase: $phase',
          field: 'phase',
        );
    }
  }

  @override
  List<Object?> get props => [id, cycleId, phase, createdAt];
}
```

## Test Fixture Example

```dart
// test/fixtures/round_fixtures.dart
class RoundFixtures {
  static final DateTime _fixedDate = DateTime.utc(2024, 1, 1);

  static Round model({
    int id = 1,
    int cycleId = 1,
    RoundPhase phase = RoundPhase.proposing,
  }) {
    return Round(
      id: id,
      cycleId: cycleId,
      phase: phase,
      createdAt: _fixedDate, // Fixed for equality tests
    );
  }
}
```

## UI Usage Example

```dart
// lib/screens/chat_screen.dart
class ChatScreen extends ConsumerWidget {
  final int chatId;

  const ChatScreen({required this.chatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ChatDetailParams(
      chatId: chatId,
      showPreviousResults: true,
    );
    final state = ref.watch(chatDetailProvider(params));

    return state.when(
      loading: () => const LoadingIndicator(),
      error: (e, st) => ErrorDisplay(error: e),
      data: (data) => ChatContent(state: data),
    );
  }
}
```
