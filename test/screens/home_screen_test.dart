import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/screens/home/home_screen.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/services/invite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixtures/fixtures.dart';
import '../mocks/mock_supabase_client.dart';

class MockChatService extends Mock implements ChatService {}

class MockParticipantService extends Mock implements ParticipantService {}

class MockAuthService extends Mock implements AuthService {}

class MockInviteService extends Mock implements InviteService {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockLanguageService extends Mock implements LanguageService {}

/// A mock notifier that immediately provides data without async loading
class MockMyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    implements MyChatsNotifier {
  MockMyChatsNotifier(List<Chat> chats, {List<JoinRequest> pendingRequests = const []})
      : super(AsyncData(MyChatsState(chats: chats, pendingRequests: pendingRequests)));

  @override
  Future<void> refresh() async {}

  @override
  void removeChat(int chatId) {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
        chats: current.chats.where((c) => c.id != chatId).toList(),
      ));
    }
  }

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

void main() {
  late MockChatService mockChatService;
  late MockParticipantService mockParticipantService;
  late MockAuthService mockAuthService;
  late MockInviteService mockInviteService;
  late MockSupabaseClient mockSupabase;
  late MockRealtimeChannel mockChannel;
  late MockSharedPreferences mockSharedPreferences;
  late MockLanguageService mockLanguageService;

  setUpAll(() {
    registerFallbackValue(PostgresChangeEvent.all);
    registerFallbackValue(PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: 1,
    ));
  });

  setUp(() {
    mockChatService = MockChatService();
    mockParticipantService = MockParticipantService();
    mockAuthService = MockAuthService();
    mockInviteService = MockInviteService();
    mockSupabase = MockSupabaseClient();
    mockChannel = MockRealtimeChannel();
    mockSharedPreferences = MockSharedPreferences();
    mockLanguageService = MockLanguageService();

    // Setup mock SharedPreferences behavior
    when(() => mockSharedPreferences.getString(any())).thenReturn(null);
    when(() => mockSharedPreferences.setString(any(), any()))
        .thenAnswer((_) async => true);

    // Setup mock LanguageService behavior
    when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');

    // Setup default auth behavior
    when(() => mockAuthService.currentUserId).thenReturn('test-user-id');
    when(() => mockAuthService.isSignedIn).thenReturn(true);
    when(() => mockAuthService.displayName).thenReturn('Test User');
    when(() => mockAuthService.hasDisplayName).thenReturn(true);
    when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => 'test-user-id');

    // Setup default channel behavior for Realtime
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

    // Setup default participant service behavior
    when(() => mockParticipantService.getMyPendingRequests())
        .thenAnswer((_) async => []);

    // Setup default chat service behavior
    when(() => mockChatService.getMyChats()).thenAnswer((_) async => []);
    when(() => mockChatService.getOfficialChat()).thenAnswer((_) async => null);
    when(() => mockChatService.getPublicChats(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => []);
  });

  Widget createTestWidget({
    List<Chat> chats = const [],
    List<JoinRequest> pendingRequests = const [],
    Chat? officialChat,
  }) {
    return ProviderScope(
      overrides: [
        chatServiceProvider.overrideWithValue(mockChatService),
        participantServiceProvider.overrideWithValue(mockParticipantService),
        authServiceProvider.overrideWithValue(mockAuthService),
        inviteServiceProvider.overrideWithValue(mockInviteService),
        supabaseProvider.overrideWithValue(mockSupabase),
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        languageServiceProvider.overrideWithValue(mockLanguageService),
        // Override myChatsProvider with pre-loaded state
        myChatsProvider.overrideWith(
          (ref) => MockMyChatsNotifier(chats, pendingRequests: pendingRequests),
        ),
        // Override officialChatProvider with immediate value
        officialChatProvider.overrideWith((ref) async => officialChat),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const HomeScreen(),
      ),
    );
  }

  group('HomeScreen', () {
    group('App Bar', () {
      testWidgets('displays app title', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('OneMind'), findsOneWidget);
      });

      // Hidden for MVP
      // testWidgets('displays Discover button', (tester) async {
      //   await tester.pumpWidget(createTestWidget());
      //   await tester.pumpAndSettle();

      //   // Explore icon appears in both app bar and empty state
      //   expect(find.byIcon(Icons.explore), findsAtLeastNWidgets(1));
      //   expect(find.byTooltip('Discover'), findsOneWidget);
      // });

      testWidgets('displays SpeedDial FAB', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // SpeedDial FAB should be visible
        expect(find.byKey(const Key('chat-speed-dial')), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('displays empty state when no chats', (tester) async {
        await tester.pumpWidget(createTestWidget(chats: []));
        await tester.pumpAndSettle();

        expect(find.text('No chats yet'), findsOneWidget);
        expect(find.byIcon(Icons.chat_bubble_outline), findsAtLeastNWidgets(1));
      });

      // Hidden for MVP
      // testWidgets('empty state shows Discover Public Chats button', (tester) async {
      //   await tester.pumpWidget(createTestWidget(chats: []));
      //   await tester.pumpAndSettle();

      //   expect(find.text('Discover Public Chats'), findsOneWidget);
      //   expect(find.byIcon(Icons.explore), findsAtLeastNWidgets(1));
      // });

      // Join with Code button removed from empty state - now in SpeedDial FAB

      testWidgets('empty state shows correct description', (tester) async {
        await tester.pumpWidget(createTestWidget(chats: []));
        await tester.pumpAndSettle();

        expect(
          find.text('Discover public chats, join with a code, or create your own'),
          findsOneWidget,
        );
      });
    });

    group('Navigation', () {
      // Hidden for MVP
      // testWidgets('Discover button navigates to Discover screen', (tester) async {
      //   await tester.pumpWidget(createTestWidget());
      //   await tester.pumpAndSettle();

      //   // Tap Discover button in app bar
      //   await tester.tap(find.byIcon(Icons.explore).first);
      //   await tester.pumpAndSettle();

      //   // Verify we navigated to Discover screen
      //   expect(find.text('Discover Chats'), findsOneWidget);
      // });

      // testWidgets('Discover Public Chats button in empty state navigates', (tester) async {
      //   await tester.pumpWidget(createTestWidget(chats: []));
      //   await tester.pumpAndSettle();

      //   // Tap Discover button in empty state
      //   await tester.tap(find.text('Discover Public Chats'));
      //   await tester.pumpAndSettle();

      //   // Verify we navigated to Discover screen
      //   expect(find.text('Discover Chats'), findsOneWidget);
      // });

      testWidgets('Join with Code opens via SpeedDial FAB', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Tap SpeedDial FAB to open it
        await tester.tap(find.byKey(const Key('chat-speed-dial')));
        await tester.pumpAndSettle();

        // Tap Join option
        await tester.tap(find.byKey(const Key('join-chat-fab')));
        await tester.pumpAndSettle();

        // Verify join dialog is shown
        expect(find.text('Join Chat'), findsOneWidget);
      });
    });

    group('Chat List', () {
      testWidgets('displays chats when available', (tester) async {
        final chat = ChatFixtures.model(id: 1, name: 'Test Chat');

        await tester.pumpWidget(createTestWidget(chats: [chat]));
        await tester.pumpAndSettle();

        expect(find.text('Test Chat'), findsOneWidget);
      });

      testWidgets('excludes official chat from Your Chats section', (tester) async {
        // Create an official chat and a regular chat
        final officialChat = Chat.fromJson(ChatFixtures.json(
          id: 1,
          name: 'Official OneMind Chat',
          isOfficial: true,
        ));
        final regularChat = ChatFixtures.model(id: 2, name: 'My Regular Chat');

        // Both chats are in the user's chat list
        await tester.pumpWidget(createTestWidget(
          chats: [officialChat, regularChat],
          officialChat: officialChat,
        ));
        await tester.pumpAndSettle();

        // Official chat should appear only once (in Official OneMind section)
        expect(find.text('Official OneMind Chat'), findsOneWidget);

        // Regular chat should appear in Your Chats section
        expect(find.text('My Regular Chat'), findsOneWidget);
      });

      testWidgets('shows empty state when only official chat exists', (tester) async {
        final officialChat = Chat.fromJson(ChatFixtures.json(
          id: 1,
          name: 'Official OneMind Chat',
          isOfficial: true,
        ));

        await tester.pumpWidget(createTestWidget(
          chats: [officialChat],
          officialChat: officialChat,
        ));
        await tester.pumpAndSettle();

        // Official chat should appear in its section
        expect(find.text('Official OneMind Chat'), findsOneWidget);

        // Should show empty state message in Your Chats since official is filtered
        // When no pending requests, shows "No chats yet" empty state
        expect(find.text('No chats yet'), findsOneWidget);
      });
    });

    group('Accessibility', () {
      // Hidden for MVP
      // testWidgets('Discover button has semantic label', (tester) async {
      //   await tester.pumpWidget(createTestWidget());
      //   await tester.pumpAndSettle();

      //   // Find the Semantics widget wrapping the Discover button
      //   final semantics = find.bySemanticsLabel('Discover public chats');
      //   expect(semantics, findsOneWidget);
      // });

      // Join button semantic label test removed - now part of SpeedDial FAB
    });
  });
}
