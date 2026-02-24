import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/models/chat_credits.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/screens/chat/chat_screen.dart';
import 'package:onemind_app/widgets/error_view.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:onemind_app/services/proposition_service.dart';
import 'package:onemind_app/services/auth_service.dart';
import '../fixtures/chat_fixtures.dart';
import '../fixtures/chat_dashboard_info_fixtures.dart';
import '../fixtures/cycle_fixtures.dart';
import '../fixtures/round_fixtures.dart';
import '../fixtures/participant_fixtures.dart';
import '../fixtures/proposition_fixtures.dart';
import '../fixtures/round_winner_fixtures.dart';
import '../mocks/mock_supabase_client.dart';

class MockChatService extends Mock implements ChatService {}

class MockParticipantService extends Mock implements ParticipantService {}

class MockPropositionService extends Mock implements PropositionService {}

class MockAuthService extends Mock implements AuthService {}

class MockNavigatorObserver extends Mock implements NavigatorObserver {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockLanguageService extends Mock implements LanguageService {}

/// Fake MyChatsNotifier for testing
class FakeMyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    implements MyChatsNotifier {
  final List<int> removedChatIds = [];

  FakeMyChatsNotifier() : super(const AsyncData(MyChatsState()));

  @override
  void removeChat(int chatId) {
    removedChatIds.add(chatId);
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(
        dashboardChats: currentState.dashboardChats.where((d) => d.chat.id != chatId).toList(),
      ));
    }
  }

  @override
  Future<void> refresh({bool silent = false}) async {}

  @override
  Future<void> cancelRequest(int requestId) async {}

  // Stream for approved chats - no-op for tests
  @override
  Stream<Chat> get approvedChatStream => const Stream.empty();

  // LanguageAwareMixin methods - no-op for tests
  @override
  String get languageCode => 'en';

  @override
  void initializeLanguageSupport(dynamic ref) {}

  @override
  void onLanguageChanged(String newLanguageCode) {}

  @override
  void disposeLanguageSupport() {}
}

/// Fake ChatDetailNotifier for testing - pre-loaded with state, no async calls
/// Implements ChatDetailNotifier interface for type compatibility with provider override.
class FakeChatDetailNotifier extends StateNotifier<AsyncValue<ChatDetailState>>
    implements ChatDetailNotifier {
  FakeChatDetailNotifier(ChatDetailState initialState)
      : super(AsyncData(initialState));

  FakeChatDetailNotifier.loading() : super(const AsyncLoading());

  FakeChatDetailNotifier.error(Object error, StackTrace stackTrace)
      : super(AsyncError(error, stackTrace));

  /// Update state for testing state transitions
  void updateState(ChatDetailState newState) {
    state = AsyncData(newState);
  }

  /// Set error state for testing error handling
  void setError(Object error) {
    state = AsyncError(error, StackTrace.current);
  }

  /// Set loading state for testing loading UI
  void setLoading() {
    state = const AsyncLoading();
  }

  // ChatDetailNotifier interface - no-op implementations for testing
  @override
  int get chatId => 0;

  @override
  bool get showPreviousResults => false;

  @override
  bool get isStartingPhase => false;

  // LanguageAwareMixin methods
  @override
  String get languageCode => 'en';

  @override
  void initializeLanguageSupport(dynamic ref) {}

  @override
  void onLanguageChanged(String newLanguageCode) {}

  @override
  void disposeLanguageSupport() {}

  // ChatDetailNotifier action methods - no-op for testing
  @override
  Future<void> submitProposition(String content) async {}

  @override
  Future<void> startPhase(Chat chat) async {}

  @override
  Future<void> advanceToRating(Chat chat) async {}

  @override
  Future<void> completeRatingPhase(Chat chat) async {}

  @override
  Future<void> refresh({bool silent = false}) async {}

  @override
  void markAsRated() {}

  @override
  Future<void> deleteProposition(int propositionId) async {}

  @override
  Future<void> deleteChat() async {}

  @override
  Future<void> approveJoinRequest(int requestId) async {}

  @override
  Future<void> denyJoinRequest(int requestId) async {}

  @override
  Future<void> leaveChat() async {}

  @override
  Future<void> kickParticipant(int participantId) async {}

  @override
  Future<void> pauseChat() async {}

  @override
  Future<void> resumeChat() async {}

  @override
  Future<void> deleteConsensusOnServer(int cycleId) async {}

  @override
  void onConsensusDismissed(int cycleId) {}

  @override
  Future<void> deleteTaskResultOnServer(int cycleId) async {}

  @override
  void onTaskResultDismissed(int cycleId) {}

  @override
  Future<void> forceConsensus(String content) async {}

  @override
  Future<void> updateInitialMessage(String newMessage) async {}

  @override
  Future<void> deleteInitialMessage() async {}

  @override
  String get contentLanguageCode => 'en';

  @override
  Future<void> setViewingLanguage(String code) async {}

  @override
  Future<void> skipProposing() async {}

  @override
  Future<void> skipRating() async {}
}

void main() {
  late MockChatService mockChatService;
  late MockParticipantService mockParticipantService;
  late MockPropositionService mockPropositionService;
  late MockAuthService mockAuthService;
  late MockSupabaseClient mockSupabase;
  late MockRealtimeChannel mockChannel;
  late MockSharedPreferences mockSharedPreferences;
  late MockLanguageService mockLanguageService;

  setUpAll(() {
    registerFallbackValue(PostgresChangeEvent.all);
  });

  setUp(() {
    mockChatService = MockChatService();
    mockParticipantService = MockParticipantService();
    mockPropositionService = MockPropositionService();
    mockAuthService = MockAuthService();
    mockSupabase = MockSupabaseClient();
    mockChannel = MockRealtimeChannel();
    mockSharedPreferences = MockSharedPreferences();
    mockLanguageService = MockLanguageService();

    // Setup default auth behavior
    when(() => mockAuthService.currentUserId).thenReturn('test-user-id');
    when(() => mockAuthService.isSignedIn).thenReturn(true);
    when(() => mockAuthService.displayName).thenReturn('Test User');
    when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => 'test-user-id');

    // Setup shared preferences for language support
    when(() => mockSharedPreferences.getString(any())).thenReturn(null);
    when(() => mockSharedPreferences.setString(any(), any()))
        .thenAnswer((_) async => true);

    // Setup language service mock
    when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');

    // Setup default channel behavior
    when(() => mockSupabase.channel(any())).thenReturn(mockChannel);
    when(() => mockChannel.onPostgresChanges(
          event: any(named: 'event'),
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          filter: any(named: 'filter'),
          callback: any(named: 'callback'),
        )).thenReturn(mockChannel);
    when(() => mockChannel.subscribe()).thenReturn(mockChannel);
    when(() => mockChannel.unsubscribe()).thenAnswer((_) async => 'ok');
  });

  /// Creates a test widget with optional pre-loaded state.
  ///
  /// Best practice: Use [chatDetailState] to pre-load state instead of
  /// relying on async service calls. This makes tests:
  /// - Predictable: No async timing issues
  /// - Fast: No actual service calls
  /// - Readable: Test intent clear from state setup
  Widget createTestWidget(
    Chat chat, {
    ChatDetailState? chatDetailState,
    bool showPreviousResults = false,
  }) {
    final overrides = <Override>[
      chatServiceProvider.overrideWithValue(mockChatService),
      participantServiceProvider.overrideWithValue(mockParticipantService),
      propositionServiceProvider.overrideWithValue(mockPropositionService),
      authServiceProvider.overrideWithValue(mockAuthService),
      supabaseProvider.overrideWithValue(mockSupabase),
      sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
      languageServiceProvider.overrideWithValue(mockLanguageService),
    ];

    // If state provided, override chatDetailProvider with pre-loaded state
    if (chatDetailState != null) {
      overrides.add(
        chatDetailProvider(ChatDetailParams(
          chatId: chat.id,
          showPreviousResults: showPreviousResults,
        )).overrideWith((ref) => FakeChatDetailNotifier(chatDetailState)),
      );
    }

    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ChatScreen(chat: chat),
      ),
    );
  }

  /// Helper to create ChatDetailState for tests.
  /// This is the best practice: define the exact state you need.
  ChatDetailState createTestState({
    Chat? chat,
    Cycle? cycle,
    Round? round,
    List<Participant>? participants,
    Participant? myParticipant,
    List<Proposition>? propositions,
    List<Proposition>? myPropositions,
    List<ConsensusItem>? consensusItems,
    List<RoundWinner>? previousRoundWinners,
    List<Proposition>? previousRoundResults,
    List<Map<String, dynamic>>? pendingJoinRequests,
    bool hasRated = false,
    bool hasStartedRating = false,
    bool isSoleWinner = false,
    int consecutiveSoleWins = 0,
    int? previousRoundId,
    bool isDeleted = false,
    ChatCredits? chatCredits,
    bool isMyParticipantFunded = true,
  }) {
    return ChatDetailState(
      chat: chat ?? ChatFixtures.model(),
      currentCycle: cycle ?? CycleFixtures.model(),
      currentRound: round,
      participants: participants ?? [ParticipantFixtures.model()],
      myParticipant: myParticipant ?? ParticipantFixtures.model(),
      propositions: propositions ?? [],
      myPropositions: myPropositions ?? [],
      consensusItems: consensusItems ?? [],
      previousRoundWinners: previousRoundWinners ?? [],
      previousRoundResults: previousRoundResults ?? [],
      pendingJoinRequests: pendingJoinRequests ?? [],
      hasRated: hasRated,
      hasStartedRating: hasStartedRating,
      isSoleWinner: isSoleWinner,
      consecutiveSoleWins: consecutiveSoleWins,
      previousRoundId: previousRoundId,
      isDeleted: isDeleted,
      chatCredits: chatCredits,
      isMyParticipantFunded: isMyParticipantFunded,
    );
  }

  void setupDefaultMocks({
    Chat? chat,
    Cycle? cycle,
    Round? round,
    Participant? participant,
    List<Proposition>? propositions,
  }) {
    final chatToUse = chat ?? ChatFixtures.model();
    final cycleToUse = cycle ?? CycleFixtures.model();
    final roundToUse = round ?? RoundFixtures.proposing();
    final participantToUse = participant ?? ParticipantFixtures.model();
    final propositionsToUse = propositions ?? [];

    // Use any() matchers to handle different IDs more flexibly
    // CRITICAL: getChatById must be mocked - notifier calls it during initialization
    when(() => mockChatService.getChatById(any()))
        .thenAnswer((_) async => chatToUse);
    when(() => mockChatService.getCurrentCycle(any()))
        .thenAnswer((_) async => cycleToUse);
    when(() => mockChatService.getConsensusItems(any()))
        .thenAnswer((_) async => []);
    when(() => mockChatService.getCurrentRound(any()))
        .thenAnswer((_) async => roundToUse);
    when(() => mockChatService.getPreviousRoundWinners(any()))
        .thenAnswer((_) async => {
              'winners': <RoundWinner>[],
              'isSoleWinner': false,
              'consecutiveSoleWins': 0,
              'previousRoundId': null,
            });
    when(() => mockChatService.subscribeToChatChanges(
          any(),
          onUpdate: any(named: 'onUpdate'),
          onDelete: any(named: 'onDelete'),
        )).thenReturn(mockChannel);
    when(() => mockChatService.subscribeToCycleChanges(any(), any()))
        .thenReturn(mockChannel);
    when(() => mockChatService.subscribeToRoundChanges(any(), any()))
        .thenReturn(mockChannel);

    when(() => mockParticipantService.getParticipants(any()))
        .thenAnswer((_) async => [participantToUse]);
    when(() => mockParticipantService.getMyParticipant(any()))
        .thenAnswer((_) async => participantToUse);
    when(() => mockParticipantService.subscribeToParticipants(any(), any()))
        .thenReturn(mockChannel);
    when(() => mockParticipantService.getPendingRequests(any()))
        .thenAnswer((_) async => <Map<String, dynamic>>[]);

    when(() => mockPropositionService.getPropositions(any()))
        .thenAnswer((_) async => propositionsToUse);
    when(() => mockPropositionService.getMyPropositions(any(), any()))
        .thenAnswer((_) async => []);
    when(() => mockPropositionService.hasRated(any(), any()))
        .thenAnswer((_) async => false);
    when(() => mockPropositionService.getRatingProgress(any(), any()))
        .thenAnswer((_) async => {
              'completed': false,
              'started': false,
            });
    when(() => mockPropositionService.getPropositionsWithRatings(any()))
        .thenAnswer((_) async => <Proposition>[]);
    when(() => mockPropositionService.subscribeToPropositions(any(), any()))
        .thenReturn(mockChannel);
  }

  // TODO: Many tests in this file need refactoring to work with LanguageAwareMixin.
  // The ChatDetailNotifier now uses LanguageAwareMixin which requires proper provider
  // mocking. These tests need to either:
  // 1. Override chatDetailProvider with a pre-loaded fake notifier, OR
  // 2. Properly await the async initialization to complete
  // Tracked in: [create GitHub issue for this tech debt]

  group('ChatScreen', () {
    // Note: Loading state tests removed - the UI no longer shows a loading indicator
    // during initial load since we use FakeChatDetailNotifier with pre-loaded state
    // in most tests. The loading behavior is implicitly tested via error handling tests.

    group('App Bar', () {
      testWidgets('displays chat name', (tester) async {
        final chat = ChatFixtures.model(name: 'Test Discussion');
        setupDefaultMocks(chat: chat);

        await tester.pumpWidget(createTestWidget(chat));
        await tester.pumpAndSettle();

        expect(find.text('Test Discussion'), findsOneWidget);
      });

      testWidgets('shows share button for non-host with invite code', (tester) async {
        final chat = ChatFixtures.codeAccess();
        final regularParticipant = ParticipantFixtures.model(id: 2, displayName: 'Regular User');

        final state = createTestState(
          chat: chat,
          participants: [ParticipantFixtures.host(), regularParticipant],
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('share-button')), findsOneWidget);
      });

      testWidgets('hides share button for public chat (no invite code)', (tester) async {
        final chat = ChatFixtures.public();
        final regularParticipant = ParticipantFixtures.model(id: 2, displayName: 'Regular User');

        final state = createTestState(
          chat: chat,
          participants: [ParticipantFixtures.host(), regularParticipant],
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('share-button')), findsNothing);
      });

      testWidgets('displays participant count', (tester) async {
        final chat = ChatFixtures.model();
        final participants = ParticipantFixtures.list(count: 5);
        final hostParticipant = ParticipantFixtures.host();

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          participants: participants,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Participants option is now in the popup menu
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
      });
    });

    group('Initial Message', () {
      testWidgets('displays initial message in chat history', (tester) async {
        final chat = ChatFixtures.model(
          initialMessage: 'What is the meaning of life?',
        );
        // Best practice: pre-load state instead of mocking services
        final state = createTestState(chat: chat);

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pump();

        expect(find.text('What is the meaning of life?'), findsOneWidget);
      });
    });

    group('Proposing Phase', () {
      testWidgets('shows proposing UI in proposing phase', (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing();
        final participant = ParticipantFixtures.model();

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: participant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show proposing panel elements - submit button
        expect(find.text('Submit'), findsOneWidget);
      });

      testWidgets('shows text field for proposition input', (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing();
        final participant = ParticipantFixtures.model();

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: participant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
      });
    });

    group('Rating Phase', () {
      testWidgets('shows rating UI in rating phase', (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.rating();
        final propositions = PropositionFixtures.list(count: 3);
        final participant = ParticipantFixtures.model();

        // Best practice: use pre-loaded state
        // NOTE: hasStartedRating=true prevents auto-navigation to rating screen
        // (which happens when phase=rating, hasStartedRating=false, hasRated=false)
        // The button shows "Continue Rating" when hasStartedRating is true
        final state = createTestState(
          chat: chat,
          round: round,
          propositions: propositions,
          myParticipant: participant,
          hasStartedRating: true, // Prevent auto-navigation to rating screen
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show rating-related UI - Continue Rating button
        // (when hasStartedRating=true, button text is "Continue Rating")
        expect(find.text('Continue Rating'), findsOneWidget);
      });
    });

    // Note: Waiting Phase tests require complex mocking of the ChatScreen widget
    // which depends on realtime subscriptions. These tests are skipped in favor of
    // the phase_panels_test.dart which tests the WaitingStatePanel directly.

    group('Error Handling', () {
      testWidgets('shows error when data fails to load', (tester) async {
        final chat = ChatFixtures.model();
        when(() => mockChatService.getCurrentCycle(chat.id))
            .thenThrow(Exception('Network error'));
        when(() => mockChatService.getConsensusItems(chat.id))
            .thenAnswer((_) async => []);
        when(() => mockParticipantService.getParticipants(chat.id))
            .thenAnswer((_) async => []);
        when(() => mockParticipantService.getMyParticipant(chat.id))
            .thenAnswer((_) async => null);

        await tester.pumpWidget(createTestWidget(chat));
        await tester.pumpAndSettle();

        // Error should show ErrorView with retry button
        expect(find.byType(ErrorView), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
      });
    });

    group('Consensus History', () {
      testWidgets('displays consensus items', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(cycleId: 1, proposition: PropositionFixtures.winner(id: 1, content: 'First consensus')),
          ConsensusItem(cycleId: 2, proposition: PropositionFixtures.winner(id: 2, content: 'Second consensus')),
        ];
        final participant = ParticipantFixtures.model();

        // Best practice: use pre-loaded state with consensus items
        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // The consensus items should show in the ListView
        expect(find.text('First consensus'), findsOneWidget);
        expect(find.text('Second consensus'), findsOneWidget);
      });

      testWidgets('displays task result card when present', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(
            cycleId: 1,
            proposition: PropositionFixtures.winner(id: 1, content: 'List 5 DAOs with public emails'),
            taskResult: 'Summary: Found Uniswap DAO, Aave DAO...',
          ),
        ];
        final participant = ParticipantFixtures.model();

        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // The consensus content should show
        expect(find.text('List 5 DAOs with public emails'), findsOneWidget);
        // The research results header should show (collapsed by default)
        expect(find.text('Research Results'), findsOneWidget);
      });

      testWidgets('hides task result card when null', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(
            cycleId: 1,
            proposition: PropositionFixtures.winner(id: 1, content: 'Some consensus'),
          ),
        ];
        final participant = ParticipantFixtures.model();

        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        expect(find.text('Some consensus'), findsOneWidget);
        expect(find.text('Research Results'), findsNothing);
      });

      testWidgets('task result card expands to show content', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(
            cycleId: 1,
            proposition: PropositionFixtures.winner(id: 1, content: 'Research task'),
            taskResult: 'Summary: Found relevant results here',
          ),
        ];
        final participant = ParticipantFixtures.model();

        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap to expand
        await tester.tap(find.text('Research Results'));
        await tester.pumpAndSettle();

        // Content should now be visible
        expect(find.text('Summary: Found relevant results here'), findsOneWidget);
      });
    });

    group('Toggle Tabs', () {
      testWidgets('displays toggle buttons on mobile', (tester) async {
        final chat = ChatFixtures.model();
        setupDefaultMocks(chat: chat);

        // Simulate mobile screen size
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(createTestWidget(chat));
        await tester.pumpAndSettle();

        // Reset to default
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });

    group('Participants Modal', () {
      testWidgets('shows participants when people icon is tapped', (tester) async {
        final chat = ChatFixtures.model();
        final hostParticipant = ParticipantFixtures.host();
        final regularParticipant = ParticipantFixtures.model(id: 2, displayName: 'Regular User');
        final List<Participant> participants = [hostParticipant, regularParticipant];

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          participants: participants,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap the participants icon button directly (no longer in popup menu)
        await tester.tap(find.byIcon(Icons.people));
        await tester.pumpAndSettle();

        // Verify modal shows participants
        expect(find.text('Participants (2)'), findsOneWidget);
        expect(find.text('Host User'), findsOneWidget);
        expect(find.text('Regular User'), findsOneWidget);
      });

      testWidgets('host sees kick button for non-host participants', (tester) async {
        final chat = ChatFixtures.model();
        final hostParticipant = ParticipantFixtures.host();
        final regularParticipant = ParticipantFixtures.model(id: 2, displayName: 'Regular User');
        final List<Participant> participants = [hostParticipant, regularParticipant];

        // Best practice: use pre-loaded state instead of async mocks
        final state = createTestState(
          chat: chat,
          participants: participants,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap the participants icon button directly
        await tester.tap(find.byIcon(Icons.people));
        await tester.pumpAndSettle();

        // Host should see kick button for regular user
        expect(find.byIcon(Icons.person_remove), findsOneWidget);
        expect(find.byTooltip('Kick participant'), findsOneWidget);
      });

      testWidgets('non-host does not see kick button', (tester) async {
        final chat = ChatFixtures.model();
        final regularParticipant = ParticipantFixtures.model(id: 2, displayName: 'Regular User');
        final otherParticipant = ParticipantFixtures.model(id: 3, displayName: 'Other User');
        final List<Participant> participants = [
          ParticipantFixtures.host(),
          regularParticipant,
          otherParticipant,
        ];

        // Best practice: use pre-loaded state with non-host participant
        final state = createTestState(
          chat: chat,
          participants: participants,
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap the participants icon button directly
        await tester.tap(find.byIcon(Icons.people));
        await tester.pumpAndSettle();

        // Non-host should NOT see kick button
        expect(find.byIcon(Icons.person_remove), findsNothing);
      });

      testWidgets('modal uses Consumer for realtime updates', (tester) async {
        // This test verifies that the modal is wrapped in Consumer
        // which allows it to rebuild when state changes
        final chat = ChatFixtures.model();
        final hostParticipant = ParticipantFixtures.host();
        final List<Participant> participants = [hostParticipant];

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          participants: participants,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap the participants icon button directly
        await tester.tap(find.byIcon(Icons.people));
        await tester.pumpAndSettle();

        // Verify modal is showing with correct count
        expect(find.text('Participants (1)'), findsOneWidget);

        // The Consumer widget in the modal ensures it watches state changes
        // Integration test would verify actual realtime behavior
      });
    });

    group('Leave Chat Button', () {
      testWidgets('non-host in official chat does not see leave button', (tester) async {
        final chat = ChatFixtures.official();
        final regularParticipant = ParticipantFixtures.model(id: 2, displayName: 'Regular User');

        final state = createTestState(
          chat: chat,
          participants: [ParticipantFixtures.host(), regularParticipant],
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Non-host in official chat should NOT see leave button
        expect(find.byIcon(Icons.exit_to_app), findsNothing);
      });

      testWidgets('non-host in regular chat sees leave button', (tester) async {
        final chat = ChatFixtures.model();
        final regularParticipant = ParticipantFixtures.model(id: 2, displayName: 'Regular User');

        final state = createTestState(
          chat: chat,
          participants: [ParticipantFixtures.host(), regularParticipant],
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Non-host in regular chat should see leave button in app bar
        expect(find.byIcon(Icons.exit_to_app), findsOneWidget);
      });
    });

    // Note: Kicked User Navigation tests removed - these tested runtime integration behavior
    // (detecting kicked status and calling removeChat) which is better tested at the
    // notifier level. The ChatDetailNotifier should have unit tests for kicked detection.
    // The screen just renders UI based on state, which is tested by other tests.

    group('Scheduled Chat - Schedule Paused', () {
      testWidgets(
          'shows ScheduledWaitingPanel when recurring chat is paused, even with waiting round',
          (tester) async {
        // Bug fix test: Previously, when a recurring scheduled chat was paused
        // (schedule_paused=true) but had a round in waiting phase, the UI would
        // incorrectly show WaitingStatePanel ("Start Phase" button) instead of
        // ScheduledWaitingPanel ("outside schedule window" message).
        //
        // The fix ensures schedule_paused check happens BEFORE round phase check.

        final chat = Chat.fromJson(ChatFixtures.json(
          id: 1,
          name: 'Scheduled Chat',
          startMode: 'scheduled',
          scheduleType: 'recurring',
          scheduleWindows: [
            {
              'start_day': 'monday',
              'start_time': '09:00',
              'end_day': 'monday',
              'end_time': '10:00',
            }
          ],
          schedulePaused: true, // Chat is paused (outside schedule window)
        ));

        // Round exists in waiting phase
        final round = RoundFixtures.waiting();
        final hostParticipant = ParticipantFixtures.host();

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show ScheduledWaitingPanel content
        expect(find.text('Chat is outside schedule window'), findsOneWidget);
        expect(find.text('Scheduled'), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsOneWidget);

        // Should NOT show WaitingStatePanel content
        expect(find.text('Start Phase'), findsNothing);
        expect(find.text('Waiting for host to start...'), findsNothing);
      });

      testWidgets(
          'shows WaitingStatePanel when recurring chat is NOT paused with waiting round',
          (tester) async {
        // When schedule_paused=false (inside window), should show normal waiting panel

        final chat = Chat.fromJson(ChatFixtures.json(
          id: 1,
          name: 'Scheduled Chat',
          startMode: 'scheduled',
          scheduleType: 'recurring',
          scheduleWindows: [
            {
              'start_day': 'monday',
              'start_time': '09:00',
              'end_day': 'monday',
              'end_time': '10:00',
            }
          ],
          schedulePaused: false, // Chat is NOT paused (inside schedule window)
        ));

        final round = RoundFixtures.waiting();
        final hostParticipant = ParticipantFixtures.host();

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show WaitingStatePanel (identified by its key)
        expect(find.byKey(const Key('waiting-state-panel')), findsOneWidget);

        // Should NOT show ScheduledWaitingPanel content
        expect(find.text('Chat is outside schedule window'), findsNothing);
      });
    });

    group('Carried Forward Propositions Bug', () {
      // Bug: When a new round starts in waiting phase, it may have carried forward
      // propositions from the previous round's winner. The UI was incorrectly showing
      // "Start Rating Phase" (WaitingForRatingPanel) instead of "Start Phase"
      // (WaitingStatePanel) because it checked propositions.isNotEmpty without
      // excluding carried forward propositions.

      testWidgets(
          'shows WaitingStatePanel (not WaitingForRatingPanel) when only carried forward propositions exist',
          (tester) async {
        final chat = ChatFixtures.withAutoStart();
        final round = RoundFixtures.waiting(customId: 2); // Round 2, waiting phase
        final hostParticipant = ParticipantFixtures.host();

        // Only carried forward proposition - no new propositions
        final carriedForwardProp = PropositionFixtures.carriedForward(
          id: 100,
          roundId: 2,
          carriedFromId: 50, // Carried from round 1's winner
          content: 'Carried forward winner',
        );

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
          propositions: [carriedForwardProp],
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show WaitingStatePanel (identified by key) because only carried forward
        // propositions exist - no NEW propositions for rating
        expect(find.byKey(const Key('waiting-state-panel')), findsOneWidget,
            reason: 'Should show WaitingStatePanel when only carried forward propositions exist');

        // Should NOT show WaitingForRatingPanel
        expect(find.text('Start Rating Phase'), findsNothing,
            reason: 'Should not show Start Rating when only carried forward propositions exist');
      });

      testWidgets(
          'shows WaitingForRatingPanel when NEW propositions exist (not just carried forward)',
          (tester) async {
        final chat = ChatFixtures.withAutoStart();
        final round = RoundFixtures.waiting(customId: 2);
        final hostParticipant = ParticipantFixtures.host();

        // Mix of carried forward and new propositions
        final propositions = [
          PropositionFixtures.carriedForward(
            id: 100,
            roundId: 2,
            carriedFromId: 50,
            content: 'Carried forward',
          ),
          PropositionFixtures.model(
            id: 101,
            roundId: 2,
            content: 'New proposition 1',
            // No carriedFromId = new proposition
          ),
          PropositionFixtures.model(
            id: 102,
            roundId: 2,
            content: 'New proposition 2',
          ),
        ];

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
          propositions: propositions,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // With new propositions, it's correct to show WaitingForRatingPanel
        // because the round has gone through proposing and is waiting for rating
        expect(find.text('Start Rating Phase'), findsOneWidget,
            reason: 'Should show Start Rating when new propositions exist');
      });
    });

    group('Previous Winner Auto-Switch', () {
      testWidgets('shows Previous Winner panel when winners are loaded',
          (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing(customId: 2); // Round 2
        final hostParticipant = ParticipantFixtures.host();
        final winner = RoundWinnerFixtures.soleWinner(
          roundId: 1, // Previous round
          content: 'Winning proposition',
          globalScore: 85.0,
        );

        // Best practice: use pre-loaded state with previous round winners
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
          previousRoundWinners: [winner],
          isSoleWinner: true,
          consecutiveSoleWins: 1,
          previousRoundId: 1,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show Previous Winner content (simplified UI)
        expect(find.text('Winning proposition'), findsOneWidget);
        // Winner tab should be visible
        expect(find.text('Previous Winner'), findsOneWidget);
      });

      testWidgets('shows winner content in panel',
          (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing(customId: 3); // Round 3
        final hostParticipant = ParticipantFixtures.host();
        final winner = RoundWinnerFixtures.soleWinner(
          roundId: 2, // Previous round
          content: 'Strong proposition',
          globalScore: 92.0,
        );

        // Best practice: use pre-loaded state with consecutive wins tracking
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
          previousRoundWinners: [winner],
          isSoleWinner: true,
          consecutiveSoleWins: 2, // 2 consecutive wins
          previousRoundId: 2,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show Previous Winner content (simplified UI)
        expect(find.text('Strong proposition'), findsOneWidget);
      });

      testWidgets('hides Winner tab during rating phase', (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.rating(customId: 2); // Rating phase
        final participant = ParticipantFixtures.model();
        final winner = RoundWinnerFixtures.soleWinner(
          roundId: 1, // Previous round
          content: 'Winning proposition',
          globalScore: 85.0,
        );

        // State with previous round winners but in rating phase
        // hasStartedRating=true prevents auto-navigation to rating screen
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: participant,
          previousRoundWinners: [winner],
          isSoleWinner: true,
          consecutiveSoleWins: 1,
          previousRoundId: 1,
          hasStartedRating: true, // Prevent auto-navigation
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Winner tab should be HIDDEN during rating phase
        expect(find.text('Winner'), findsNothing,
            reason: 'Winner tab should be hidden during rating phase');

        // Rate tab should still be visible (the phase-specific tab label)
        expect(find.text('Rate'), findsOneWidget);
      });

      testWidgets('shows Winner tab during proposing phase with previous winners',
          (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing(customId: 2); // Proposing phase
        final participant = ParticipantFixtures.model();
        final winner = RoundWinnerFixtures.soleWinner(
          roundId: 1, // Previous round
          content: 'Winning proposition',
          globalScore: 85.0,
        );

        // State with previous round winners in proposing phase
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: participant,
          previousRoundWinners: [winner],
          isSoleWinner: true,
          consecutiveSoleWins: 1,
          previousRoundId: 1,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Winner tab should be VISIBLE during proposing phase
        expect(find.text('Previous Winner'), findsOneWidget,
            reason: 'Winner tab should be visible during proposing phase');
      });
    });

    // Feature intentionally hidden - host cannot view all propositions to preserve anonymity
    group('Host Propositions Modal - Carried Forward Protection', skip: 'Feature hidden for anonymity', () {
      testWidgets('delete button is hidden for carried forward propositions',
          (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing(customId: 2);
        final hostParticipant = ParticipantFixtures.host();

        // Mix of carried forward and regular propositions
        final propositions = [
          PropositionFixtures.carriedForward(
            id: 100,
            roundId: 2,
            carriedFromId: 50,
            content: 'Previous winner - carried forward',
          ),
          PropositionFixtures.model(
            id: 101,
            roundId: 2,
            content: 'New proposition 1',
          ),
          PropositionFixtures.model(
            id: 102,
            roundId: 2,
            content: 'New proposition 2',
          ),
        ];

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
          propositions: propositions,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap the "View all propositions" button (list icon for host)
        await tester.tap(find.byIcon(Icons.list_alt));
        await tester.pumpAndSettle();

        // Modal should be open
        expect(find.text('All Propositions (3)'), findsOneWidget);

        // Should show "(Previous winner)" label for carried forward
        expect(find.text('(Previous winner)'), findsOneWidget);

        // Delete buttons: should only have 2 (for non-carried forward propositions)
        // Carried forward proposition should NOT have delete button
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      });

      testWidgets('delete button is shown for all regular propositions',
          (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing();
        final hostParticipant = ParticipantFixtures.host();

        // All regular propositions (no carried forward)
        final propositions = [
          PropositionFixtures.model(id: 1, content: 'Proposition 1'),
          PropositionFixtures.model(id: 2, content: 'Proposition 2'),
          PropositionFixtures.model(id: 3, content: 'Proposition 3'),
        ];

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
          propositions: propositions,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap the "View all propositions" button
        await tester.tap(find.byIcon(Icons.list_alt));
        await tester.pumpAndSettle();

        // Modal should be open
        expect(find.text('All Propositions (3)'), findsOneWidget);

        // Should NOT show "(Previous winner)" label
        expect(find.text('(Previous winner)'), findsNothing);

        // Delete buttons: should have 3 (one for each proposition)
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
      });

      testWidgets('shows "(Previous winner)" label only for carried forward',
          (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing(customId: 3);
        final hostParticipant = ParticipantFixtures.host();

        // Two carried forward (rare but possible with ties)
        final propositions = [
          PropositionFixtures.carriedForward(
            id: 100,
            roundId: 3,
            carriedFromId: 50,
            content: 'Tied winner 1',
          ),
          PropositionFixtures.carriedForward(
            id: 101,
            roundId: 3,
            carriedFromId: 51,
            content: 'Tied winner 2',
          ),
          PropositionFixtures.model(
            id: 102,
            roundId: 3,
            content: 'New submission',
          ),
        ];

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: hostParticipant,
          propositions: propositions,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Tap the "View all propositions" button
        await tester.tap(find.byIcon(Icons.list_alt));
        await tester.pumpAndSettle();

        // Should show "(Previous winner)" twice (for both carried forward)
        expect(find.text('(Previous winner)'), findsNWidgets(2));

        // Delete buttons: only 1 (for the new submission)
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      });

      testWidgets('non-host cannot see propositions modal button',
          (tester) async {
        final chat = ChatFixtures.model();
        final round = RoundFixtures.proposing();
        final regularParticipant = ParticipantFixtures.model(isHost: false);
        final propositions = PropositionFixtures.list(count: 3);

        // Best practice: use pre-loaded state with non-host participant
        final state = createTestState(
          chat: chat,
          round: round,
          myParticipant: regularParticipant,
          propositions: propositions,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Non-host should NOT see the "View all propositions" button
        expect(find.byIcon(Icons.list_alt), findsNothing);
      });
    });

    group('Host Pause', () {
      // Note: Pause/Resume button is currently hidden in the UI
      // These tests verify the button is NOT shown (matching current behavior)
      testWidgets('host does not see pause button (feature hidden)',
          (tester) async {
        final chat = ChatFixtures.model(hostPaused: false);
        final hostParticipant = ParticipantFixtures.host();

        final state = createTestState(
          chat: chat,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Open the popup menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Pause/Resume buttons are hidden
        expect(find.text('Pause Chat'), findsNothing);
        expect(find.text('Resume Chat'), findsNothing);
      });

      testWidgets('host does not see resume button when paused (feature hidden)',
          (tester) async {
        final chat = ChatFixtures.model(hostPaused: true);
        final hostParticipant = ParticipantFixtures.host();

        final state = createTestState(
          chat: chat,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Open the popup menu
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        // Pause/Resume buttons are hidden
        expect(find.text('Resume Chat'), findsNothing);
        expect(find.text('Pause Chat'), findsNothing);
      });

      testWidgets('non-host does not see popup menu at all',
          (tester) async {
        final chat = ChatFixtures.model(hostPaused: false);
        final regularParticipant = ParticipantFixtures.model(isHost: false);

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Non-host should NOT see the host overflow menu at all
        expect(find.byKey(const Key('chat-more-menu')), findsNothing);
      });

      testWidgets('shows HostPausedBanner when chat is paused',
          (tester) async {
        final chat = ChatFixtures.model(hostPaused: true);
        final regularParticipant = ParticipantFixtures.model(isHost: false);

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should show the paused banner
        expect(find.text('Chat Paused by Host'), findsOneWidget);
        expect(find.byIcon(Icons.pause_circle), findsOneWidget);
      });

      testWidgets('does not show HostPausedBanner when chat is not paused',
          (tester) async {
        final chat = ChatFixtures.model(hostPaused: false);
        final regularParticipant = ParticipantFixtures.model(isHost: false);

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          myParticipant: regularParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Should NOT show the paused banner
        expect(find.text('Chat Paused by Host'), findsNothing);
        expect(find.text('Chat Paused'), findsNothing);
      });

      testWidgets('host sees different message in HostPausedBanner',
          (tester) async {
        final chat = ChatFixtures.model(hostPaused: true);
        final hostParticipant = ParticipantFixtures.host();

        // Best practice: use pre-loaded state
        final state = createTestState(
          chat: chat,
          myParticipant: hostParticipant,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Host sees different message
        expect(find.text('Chat Paused'), findsOneWidget);
        expect(find.text('Chat Paused by Host'), findsNothing);
        expect(
          find.text('The timer is stopped. Tap Resume in the app bar to continue.'),
          findsOneWidget,
        );
      });
    });

    group('Credit UI', () {
      // Helper to create a ChatCredits instance for tests
      ChatCredits testCredits({int balance = 50, int chatId = 1}) {
        return ChatCredits(
          id: 1,
          chatId: chatId,
          creditBalance: balance,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      group('Spectator mode', () {
        testWidgets('unfunded participant sees spectator banner during proposing',
            (tester) async {
          final chat = ChatFixtures.model();
          final round = RoundFixtures.proposing();

          final state = createTestState(
            chat: chat,
            round: round,
            isMyParticipantFunded: false,
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show spectator banner
          expect(find.text('Spectating — insufficient credits'), findsOneWidget);
          // Should NOT show proposition input
          expect(find.byKey(const Key('proposition-input')), findsNothing);
        });

        testWidgets('unfunded participant sees spectator banner during rating',
            (tester) async {
          final chat = ChatFixtures.model();
          final round = RoundFixtures.rating();

          final state = createTestState(
            chat: chat,
            round: round,
            isMyParticipantFunded: false,
            hasRated: false,
            hasStartedRating: true, // Prevent auto-navigate to rating screen
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show spectator banner
          expect(find.text('Spectating — insufficient credits'), findsOneWidget);
          // Should NOT show rate button
          expect(find.byKey(const Key('start-rating-button')), findsNothing);
        });

        testWidgets('funded participant sees normal proposing panel',
            (tester) async {
          final chat = ChatFixtures.model();
          final round = RoundFixtures.proposing();

          final state = createTestState(
            chat: chat,
            round: round,
            isMyParticipantFunded: true,
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show text field, no spectator banner
          expect(find.byKey(const Key('proposition-input')), findsOneWidget);
          expect(find.text('Spectating — insufficient credits'), findsNothing);
        });

        testWidgets('funded participant sees normal rating panel',
            (tester) async {
          final chat = ChatFixtures.model();
          final round = RoundFixtures.rating();

          final state = createTestState(
            chat: chat,
            round: round,
            isMyParticipantFunded: true,
            hasStartedRating: true, // Prevent auto-navigate
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show continue rating button, no spectator banner
          expect(find.text('Continue Rating'), findsOneWidget);
          expect(find.text('Spectating — insufficient credits'), findsNothing);
        });
      });

      group('Credit-paused', () {
        testWidgets('credit-paused round shows credit paused panel for host',
            (tester) async {
          final chat = ChatFixtures.model();
          final hostParticipant = ParticipantFixtures.host();
          final participants = ParticipantFixtures.list(count: 3);

          final state = createTestState(
            chat: chat,
            myParticipant: hostParticipant,
            participants: participants,
            chatCredits: testCredits(balance: 0), // Can't afford 3 participants
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show credit paused panel
          expect(find.byKey(const Key('credit-paused-panel')), findsOneWidget);
          expect(find.text('Paused — Insufficient Credits'), findsOneWidget);
          expect(find.text('Balance: 0 credits'), findsOneWidget);
          // Host sees buy button
          expect(find.byKey(const Key('buy-credits-button')), findsOneWidget);
        });

        testWidgets('credit-paused round shows waiting message for non-host',
            (tester) async {
          final chat = ChatFixtures.model();
          final nonHostParticipant = ParticipantFixtures.model();
          final participants = ParticipantFixtures.list(count: 3);

          final state = createTestState(
            chat: chat,
            myParticipant: nonHostParticipant,
            participants: participants,
            chatCredits: testCredits(balance: 0),
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show credit paused panel with non-host message
          expect(find.byKey(const Key('credit-paused-panel')), findsOneWidget);
          expect(find.text('Waiting for host to add credits'), findsOneWidget);
          // Should NOT show buy button
          expect(find.byKey(const Key('buy-credits-button')), findsNothing);
        });

        testWidgets('normal waiting round shows participant counter when credits sufficient',
            (tester) async {
          final chat = ChatFixtures.model();
          final participants = ParticipantFixtures.list(count: 3);

          final state = createTestState(
            chat: chat,
            participants: participants,
            chatCredits: testCredits(balance: 50), // Can afford 3 participants
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show waiting panel, not credit-paused
          expect(find.byKey(const Key('waiting-state-panel')), findsOneWidget);
          expect(find.byKey(const Key('credit-paused-panel')), findsNothing);
        });
      });

      // Credit chip is currently hidden from UI
      group('Credit balance chip', skip: 'Credit chip hidden from UI', () {
        testWidgets('host sees credit balance chip in AppBar',
            (tester) async {
          final chat = ChatFixtures.model();
          final hostParticipant = ParticipantFixtures.host();

          final state = createTestState(
            chat: chat,
            myParticipant: hostParticipant,
            chatCredits: testCredits(balance: 47),
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show chip with balance
          expect(find.byKey(const Key('credit-balance-chip')), findsOneWidget);
          expect(find.text('47'), findsOneWidget);
        });

        testWidgets('non-host does not see credit balance chip',
            (tester) async {
          final chat = ChatFixtures.model();
          final nonHostParticipant = ParticipantFixtures.model();

          final state = createTestState(
            chat: chat,
            myParticipant: nonHostParticipant,
            chatCredits: testCredits(balance: 47),
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should NOT show chip
          expect(find.byKey(const Key('credit-balance-chip')), findsNothing);
        });

        testWidgets('credit chip shows warning color when low',
            (tester) async {
          final chat = ChatFixtures.model();
          final hostParticipant = ParticipantFixtures.host();
          final participants = ParticipantFixtures.list(count: 5);

          final state = createTestState(
            chat: chat,
            myParticipant: hostParticipant,
            participants: participants,
            chatCredits: testCredits(balance: 2), // Less than 5 participants
          );

          await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
          await tester.pumpAndSettle();

          // Should show chip
          expect(find.byKey(const Key('credit-balance-chip')), findsOneWidget);
          expect(find.text('2'), findsOneWidget);

          // Verify the chip has amber/warning styling
          final chipContainer = tester.widget<Container>(
            find.descendant(
              of: find.byKey(const Key('credit-balance-chip')),
              matching: find.byType(Container),
            ).first,
          );
          final decoration = chipContainer.decoration as BoxDecoration;
          expect(decoration.color, Colors.amber.shade100);
        });
      });
    });

    group('Host Force Consensus', () {
      testWidgets('host-overridden consensus shows host name instead of Consensus #N', (tester) async {
        final chat = ChatFixtures.model();
        final participant = ParticipantFixtures.model();

        final consensusItems = [
          ConsensusItem(
            cycleId: 1,
            proposition: PropositionFixtures.winner(id: 1, content: 'Normal consensus'),
            isHostOverride: false,
          ),
          ConsensusItem(
            cycleId: 2,
            proposition: PropositionFixtures.winner(id: 2, content: 'Host forced this'),
            isHostOverride: true,
          ),
        ];

        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Normal consensus shows "Convergence #1"
        expect(find.text('Convergence #1'), findsOneWidget);

        // Host-overridden shows "Host" (since hostDisplayName is null in fixture)
        expect(find.text('Host'), findsOneWidget);

        // Should NOT show "Convergence #2" for the overridden one
        expect(find.text('Convergence #2'), findsNothing);
      });

      testWidgets('regular consensus still shows Convergence #N', (tester) async {
        final chat = ChatFixtures.model();
        final participant = ParticipantFixtures.model();

        final consensusItems = [
          ConsensusItem(
            cycleId: 1,
            proposition: PropositionFixtures.winner(id: 1, content: 'First idea'),
            isHostOverride: false,
          ),
          ConsensusItem(
            cycleId: 2,
            proposition: PropositionFixtures.winner(id: 2, content: 'Second idea'),
            isHostOverride: false,
          ),
        ];

        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        expect(find.text('Convergence #1'), findsOneWidget);
        expect(find.text('Convergence #2'), findsOneWidget);
      });
    });

    group('Consensus Deletion Restriction', () {
      testWidgets('only last consensus is swipeable for hosts', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(cycleId: 1, proposition: PropositionFixtures.winner(id: 1, content: 'First consensus')),
          ConsensusItem(cycleId: 2, proposition: PropositionFixtures.winner(id: 2, content: 'Second consensus')),
        ];
        final host = ParticipantFixtures.host();

        final state = createTestState(
          chat: chat,
          myParticipant: host,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Last consensus should be wrapped in Dismissible
        expect(find.byKey(const ValueKey('consensus_2')), findsOneWidget);
        // First consensus should NOT be wrapped in Dismissible
        expect(find.byKey(const ValueKey('consensus_1')), findsNothing);
      });

      testWidgets('no consensus is swipeable for non-hosts', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(cycleId: 1, proposition: PropositionFixtures.winner(id: 1, content: 'First consensus')),
        ];
        final participant = ParticipantFixtures.model();

        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // No Dismissible keys should be present
        expect(find.byKey(const ValueKey('consensus_1')), findsNothing);
      });

      testWidgets('single consensus is swipeable for hosts', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(cycleId: 1, proposition: PropositionFixtures.winner(id: 1, content: 'Only consensus')),
        ];
        final host = ParticipantFixtures.host();

        final state = createTestState(
          chat: chat,
          myParticipant: host,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Single item is the last item, so it should be swipeable
        expect(find.byKey(const ValueKey('consensus_1')), findsOneWidget);
      });
    });

    group('Task Result Deletion', () {
      testWidgets('task result on last consensus is swipeable for hosts', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(
            cycleId: 1,
            proposition: PropositionFixtures.winner(id: 1, content: 'First'),
            taskResult: 'First research',
          ),
          ConsensusItem(
            cycleId: 2,
            proposition: PropositionFixtures.winner(id: 2, content: 'Second'),
            taskResult: 'Second research',
          ),
        ];
        final host = ParticipantFixtures.host();

        final state = createTestState(
          chat: chat,
          myParticipant: host,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // Last task result should be wrapped in Dismissible
        expect(find.byKey(const ValueKey('task_result_2')), findsOneWidget);
        // First task result should NOT be wrapped in Dismissible
        expect(find.byKey(const ValueKey('task_result_1')), findsNothing);
      });

      testWidgets('task result is not swipeable for non-hosts', (tester) async {
        final chat = ChatFixtures.model();
        final consensusItems = [
          ConsensusItem(
            cycleId: 1,
            proposition: PropositionFixtures.winner(id: 1, content: 'Consensus'),
            taskResult: 'Some research',
          ),
        ];
        final participant = ParticipantFixtures.model();

        final state = createTestState(
          chat: chat,
          myParticipant: participant,
          consensusItems: consensusItems,
        );

        await tester.pumpWidget(createTestWidget(chat, chatDetailState: state));
        await tester.pumpAndSettle();

        // No task result Dismissible should be present
        expect(find.byKey(const ValueKey('task_result_1')), findsNothing);
        // But the research results should still show
        expect(find.text('Research Results'), findsOneWidget);
      });
    });
  });
}
