import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/providers/notifiers/my_chats_notifier.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/home/all_chats_screen.dart';
import 'package:onemind_app/screens/home/home_screen.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/invite_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fixtures/chat_dashboard_info_fixtures.dart';
import '../../mocks/mock_supabase_client.dart';

class _MockChatService extends Mock implements ChatService {}
class _MockParticipantService extends Mock implements ParticipantService {}
class _MockAuthService extends Mock implements AuthService {}
class _MockInviteService extends Mock implements InviteService {}
class _MockSharedPreferences extends Mock implements SharedPreferences {}

class _MockLanguageService extends Mock implements LanguageService {
  @override
  String getCurrentLanguage() => 'en';
  @override
  Future<String> initializeLanguage() async => 'en';
  @override
  Future<bool> updateLanguage(String code) async => true;
}

class _TestLocaleNotifier extends LocaleNotifier {
  _TestLocaleNotifier() : super(_MockLanguageService());
}

/// Push-only observer that records which route names are pushed so tests
/// can assert navigation happened (AllChatsScreen uses MaterialPageRoute
/// with no name, so we match by route.settings.name OR page widget type).
class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

class _FakeMyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    implements MyChatsNotifier {
  _FakeMyChatsNotifier(List<ChatDashboardInfo> chats)
      : super(AsyncData(MyChatsState(
          dashboardChats: chats,
          pendingRequests: const [],
        )));
  @override
  Future<void> refresh() async {}
  @override
  void removeChat(int chatId) {}
  @override
  Future<void> cancelRequest(int requestId) async {}
  @override
  void addPendingRequest(JoinRequest request) {}
  @override
  Stream<Chat> get approvedChatStream => const Stream.empty();
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
  late _MockChatService chatService;
  late _MockParticipantService participantService;
  late _MockAuthService authService;
  late _MockInviteService inviteService;
  late MockSupabaseClient supabase;
  late MockRealtimeChannel channel;
  late _MockSharedPreferences prefs;
  late _RecordingObserver observer;

  setUpAll(() {
    registerFallbackValue(PostgresChangeEvent.all);
    registerFallbackValue(PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: 1,
    ));
  });

  setUp(() {
    chatService = _MockChatService();
    participantService = _MockParticipantService();
    authService = _MockAuthService();
    inviteService = _MockInviteService();
    supabase = MockSupabaseClient();
    channel = MockRealtimeChannel();
    prefs = _MockSharedPreferences();
    observer = _RecordingObserver();

    when(() => prefs.getString(any())).thenReturn(null);
    when(() => prefs.setString(any(), any())).thenAnswer((_) async => true);
    when(() => prefs.getBool(any())).thenReturn(null);

    when(() => authService.currentUserId).thenReturn('test-user-id');
    when(() => authService.isSignedIn).thenReturn(true);
    when(() => authService.displayName).thenReturn('Test User');
    when(() => authService.hasDisplayName).thenReturn(true);
    when(() => authService.ensureSignedIn())
        .thenAnswer((_) async => 'test-user-id');

    when(() => supabase.channel(any())).thenReturn(channel);
    when(() => channel.onPostgresChanges(
          event: any(named: 'event'),
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          filter: any(named: 'filter'),
          callback: any(named: 'callback'),
        )).thenReturn(channel);
    when(() => channel.subscribe()).thenReturn(channel);
    when(() => channel.unsubscribe()).thenAnswer((_) async => 'ok');

    when(() => participantService.getMyPendingRequests())
        .thenAnswer((_) async => []);

    when(() => chatService.getMyChats()).thenAnswer((_) async => []);
    when(() => chatService.getOfficialChat()).thenAnswer((_) async => null);
    when(() => chatService.getPublicChats(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => []);
  });

  Widget buildHome(List<ChatDashboardInfo> chats) {
    return ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) => _TestLocaleNotifier()),
        chatServiceProvider.overrideWithValue(chatService),
        participantServiceProvider.overrideWithValue(participantService),
        authServiceProvider.overrideWithValue(authService),
        inviteServiceProvider.overrideWithValue(inviteService),
        supabaseProvider.overrideWithValue(supabase),
        sharedPreferencesProvider.overrideWithValue(prefs),
        myChatsProvider.overrideWith(
          (ref) => _FakeMyChatsNotifier(chats),
        ),
        officialChatProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        navigatorObservers: [observer],
        home: const HomeScreen(),
      ),
    );
  }

  // Inline collapsible "Coming up" section. Shows ONLY wrappingUp chats
  // (active round, user has done their part, waiting for round to advance
  // — i.e., next time you'll act, this chat is where it'll happen).
  // Inactive chats (paused / between rounds) are intentionally excluded
  // from home — they remain reachable via "View all my chats" →
  // AllChatsScreen which lists everything.
  group('Home "Coming up" section', () {
    testWidgets('hidden when no wrapping-up chats', (tester) async {
      final nextUp = ChatDashboardInfoFixtures.proposingTimed(
        id: 1,
        name: 'Active',
        hasParticipated: false,
      );
      await tester.pumpWidget(buildHome([nextUp]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coming-up-section')), findsNothing);
    });

    testWidgets('shows count of wrapping-up chats', (tester) async {
      final chats = [
        ChatDashboardInfoFixtures.proposingTimed(
            id: 1, name: 'W1', hasParticipated: true),
        ChatDashboardInfoFixtures.ratingTimed(
            id: 2, name: 'W2', hasParticipated: true),
      ];
      await tester.pumpWidget(buildHome(chats));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coming-up-section')), findsOneWidget);
      expect(find.text('Coming up (2)'), findsOneWidget);
    });

    testWidgets('hidden when only inactive chats exist (no wrapping-up)',
        (tester) async {
      // Inactive chats (paused / waiting / idle) don't belong in
      // "Coming up" — surfacing them would misrepresent them as
      // actionable. Section should be hidden entirely.
      final chats = [
        ChatDashboardInfoFixtures.paused(id: 1, name: 'P'),
        ChatDashboardInfoFixtures.waiting(id: 2, name: 'W'),
        ChatDashboardInfoFixtures.idle(id: 3, name: 'I'),
      ];
      await tester.pumpWidget(buildHome(chats));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coming-up-section')), findsNothing);
      expect(find.textContaining('Coming up'), findsNothing);
    });

    testWidgets('inactive chats are excluded from the count',
        (tester) async {
      // 1 wrappingUp + 2 inactive → Coming up shows 1, not 3.
      final chats = [
        ChatDashboardInfoFixtures.proposingTimed(
            id: 1, name: 'W', hasParticipated: true), // wrappingUp
        ChatDashboardInfoFixtures.paused(id: 2, name: 'P'), // inactive
        ChatDashboardInfoFixtures.waiting(id: 3, name: 'WT'), // inactive
      ];
      await tester.pumpWidget(buildHome(chats));
      await tester.pumpAndSettle();

      expect(find.text('Coming up (1)'), findsOneWidget);
    });

    testWidgets('next-up chats do NOT count toward Coming up',
        (tester) async {
      final chats = [
        ChatDashboardInfoFixtures.proposingTimed(
            id: 1, name: 'NU1', hasParticipated: false),
        ChatDashboardInfoFixtures.ratingTimed(
            id: 2, name: 'NU2', hasParticipated: false),
        ChatDashboardInfoFixtures.proposingTimed(
            id: 3, name: 'W', hasParticipated: true),
      ];
      await tester.pumpWidget(buildHome(chats));
      await tester.pumpAndSettle();

      expect(find.text('Coming up (1)'), findsOneWidget);
    });

    testWidgets('tapping header expands inline (does NOT push AllChatsScreen)',
        (tester) async {
      final chats = [
        ChatDashboardInfoFixtures.proposingTimed(
            id: 1, name: 'NU', hasParticipated: false), // hero (nextUp)
        ChatDashboardInfoFixtures.proposingTimed(
            id: 2, name: 'CU', hasParticipated: true), // coming-up
      ];
      await tester.pumpWidget(buildHome(chats));
      await tester.pumpAndSettle();

      // Initially collapsed: coming-up chat card not visible
      expect(find.byKey(const Key('coming-up-chat-card-2')), findsNothing);

      await tester.tap(find.byKey(const Key('coming-up-section')));
      await tester.pumpAndSettle();

      // Now expanded: coming-up chat card + "View all my chats" link visible
      expect(find.byKey(const Key('coming-up-chat-card-2')), findsOneWidget);
      expect(find.byKey(const Key('coming-up-view-all')), findsOneWidget);
      // Did NOT navigate yet
      expect(find.byType(AllChatsScreen), findsNothing);
    });

    testWidgets('"View all my chats" pushes AllChatsScreen', (tester) async {
      // Even with only 2 chats total, "View all my chats" should be
      // available — gives users a reliable escape hatch to the full
      // searchable list of every chat they're in (including inactive,
      // which are hidden from home).
      final chats = [
        ChatDashboardInfoFixtures.proposingTimed(
            id: 1, name: 'NU', hasParticipated: false), // hero (nextUp)
        ChatDashboardInfoFixtures.proposingTimed(
            id: 2, name: 'CU', hasParticipated: true), // coming-up
      ];
      await tester.pumpWidget(buildHome(chats));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coming-up-section')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coming-up-view-all')), findsOneWidget);

      await tester.tap(find.byKey(const Key('coming-up-view-all')));
      await tester.pumpAndSettle();

      expect(find.byType(AllChatsScreen), findsOneWidget);
    });
  });
}
