import 'dart:async';

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
import 'package:onemind_app/screens/home/home_screen.dart';
import 'package:onemind_app/services/analytics_service.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/invite_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fixtures/chat_dashboard_info_fixtures.dart';
import '../../fixtures/chat_fixtures.dart';
import '../../fixtures/participant_fixtures.dart';
import '../../mocks/mock_supabase_client.dart';

class _MockChatService extends Mock implements ChatService {}

class _MockParticipantService extends Mock implements ParticipantService {}

class _MockAuthService extends Mock implements AuthService {}

class _MockInviteService extends Mock implements InviteService {}

class _MockSharedPreferences extends Mock implements SharedPreferences {}

class _MockAnalyticsService extends Mock implements AnalyticsService {}

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

/// Verifies the first-time auto-join into the official OneMind chat
/// does NOT show the "Looking for more chats" discovery empty state —
/// otherwise a fresh user would see it flash for a beat between landing
/// on Home and the auto-joined OneMind card appearing.
void main() {
  late _MockChatService chatService;
  late _MockParticipantService participantService;
  late _MockAuthService authService;
  late _MockInviteService inviteService;
  late MockSupabaseClient supabase;
  late MockRealtimeChannel channel;
  late _MockSharedPreferences prefs;
  late _MockAnalyticsService analytics;

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
    analytics = _MockAnalyticsService();

    when(() => analytics.observer).thenReturn(null);
    when(() => analytics.logHomeScreenViewed(
          isFirstVisit: any(named: 'isFirstVisit'),
        )).thenAnswer((_) async {});
    when(() => analytics.logOfficialChatAutoJoined(
          succeeded: any(named: 'succeeded'),
          chatId: any(named: 'chatId'),
        )).thenAnswer((_) async {});
    when(() => analytics.logOfficialChatAutoOpened(
          chatId: any(named: 'chatId'),
        )).thenAnswer((_) async {});
    // ChatScreen.initState fires these when an auto-navigate mounts it.
    when(() => analytics.logScreenView(screenName: any(named: 'screenName')))
        .thenAnswer((_) async {});
    when(() => analytics.logChatOpened(chatId: any(named: 'chatId')))
        .thenAnswer((_) async {});

    when(() => prefs.getString(any())).thenReturn(null);
    when(() => prefs.setString(any(), any())).thenAnswer((_) async => true);
    when(() => prefs.getBool(any())).thenReturn(null);
    when(() => prefs.setBool(any(), any())).thenAnswer((_) async => true);

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
    when(() => chatService.getPublicChats(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => []);
  });

  Widget buildHome({List<ChatDashboardInfo> initialChats = const []}) {
    return ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) => _TestLocaleNotifier()),
        chatServiceProvider.overrideWithValue(chatService),
        participantServiceProvider.overrideWithValue(participantService),
        authServiceProvider.overrideWithValue(authService),
        inviteServiceProvider.overrideWithValue(inviteService),
        analyticsServiceProvider.overrideWithValue(analytics),
        supabaseProvider.overrideWithValue(supabase),
        sharedPreferencesProvider.overrideWithValue(prefs),
        myChatsProvider.overrideWith((ref) => _FakeMyChatsNotifier(initialChats)),
        officialChatProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const HomeScreen(),
      ),
    );
  }

  group('Official auto-join retired', () {
    // The official-chat auto-join was retired (2026-05-30): the landing CTA now
    // sends new users to the /create quick-rank flow instead of dumping them into
    // the official chat. These tests guard that the auto-join NEVER fires.
    testWidgets(
        'first-time visitor: official chat is NOT auto-joined; discovery shows immediately',
        (tester) async {
      // First-time user path: hasAutoJoinedOfficial == false.
      when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(null);
      // If auto-join were still wired, this would be awaited and hold a spinner.
      final pending = Completer<Chat?>();
      when(() => chatService.getOfficialChat())
          .thenAnswer((_) => pending.future);

      await tester.pumpWidget(buildHome());
      await tester.pump();

      // Auto-join is retired → no getOfficialChat/join, no in-flight spinner,
      // and the discovery empty state renders immediately.
      verifyNever(() => chatService.getOfficialChat());
      verifyNever(
          () => participantService.joinPublicChat(chatId: any(named: 'chatId')));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('empty-state-panel')), findsOneWidget);

      pending.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'after auto-join completes: discovery card is shown (first-time user)',
        (tester) async {
      when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(null);
      when(() => chatService.getOfficialChat())
          .thenAnswer((_) async => null); // nothing to join, still completes

      await tester.pumpWidget(buildHome());
      await tester.pumpAndSettle();

      // Once the future resolves, the flag flips back off and the empty-
      // state discovery card renders as usual.
      expect(find.byKey(const Key('empty-state-panel')), findsOneWidget);
    });

    testWidgets(
        'returning user (already auto-joined): discovery card renders immediately',
        (tester) async {
      // hasAutoJoinedOfficial == true -> _ensureJoinedOfficialChat returns
      // early and never sets _isAutoJoiningOfficial true.
      when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(true);

      await tester.pumpWidget(buildHome());
      await tester.pump(); // single frame is enough — no async work happens.

      expect(find.byKey(const Key('empty-state-panel')), findsOneWidget);
      // And we never call getOfficialChat for this user.
      verifyNever(() => chatService.getOfficialChat());
    });
  });

  // ============================================================================
  // Hijack prevention for /join/CODE flow.
  //
  // Bug (intro'd 2026-04-29): a first-time visitor arriving at Home from a
  // /join/CODE link would get auto-redirected to the official OneMind chat
  // instead of staying with the chat they actually joined. This wrecks any
  // invite-based onboarding (live demos, custom-chat invites, etc.).
  //
  // Fix: only auto-navigate to the official chat when the user has no other
  // joined chats. If they came from /join/CODE, that chat is already in
  // their list and the auto-navigate is suppressed.
  // ============================================================================
  group('Hijack prevention for /join/CODE flow', () {
    testWidgets(
        'first-time visitor with no other chats: does NOT auto-join or auto-navigate (retired)',
        (tester) async {
      when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(null);
      final officialChat = ChatFixtures.model(id: 246, name: 'OneMind');
      when(() => chatService.getOfficialChat())
          .thenAnswer((_) async => officialChat);
      when(() => participantService.joinPublicChat(chatId: any(named: 'chatId')))
          .thenAnswer((_) async => ParticipantFixtures.model());

      await tester.pumpWidget(buildHome(initialChats: const []));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Retired: no auto-join, no auto-navigate, even for a fresh first-time user.
      verifyNever(() => chatService.getOfficialChat());
      verifyNever(
          () => participantService.joinPublicChat(chatId: any(named: 'chatId')));
      verifyNever(() => analytics.logOfficialChatAutoOpened(
            chatId: any(named: 'chatId'),
          ));
    });

    testWidgets(
        'first-time visitor who came from /join/CODE: does NOT auto-join the official chat',
        (tester) async {
      when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(null);
      final officialChat = ChatFixtures.model(id: 246, name: 'OneMind');
      when(() => chatService.getOfficialChat())
          .thenAnswer((_) async => officialChat);
      when(() => participantService.joinPublicChat(chatId: any(named: 'chatId')))
          .thenAnswer((_) async => ParticipantFixtures.model());

      final demoChat = ChatDashboardInfoFixtures.idle(
        id: 295,
        name: 'NCDD Higher Ed Exchange',
      );

      await tester.pumpWidget(buildHome(initialChats: [demoChat]));
      await tester.pumpAndSettle();

      // Retired: the official chat is no longer force-joined or auto-opened.
      verifyNever(() => participantService.joinPublicChat(chatId: 246));
      verifyNever(() => analytics.logOfficialChatAutoOpened(
            chatId: any(named: 'chatId'),
          ));
    });

    testWidgets(
        'first-time visitor with multiple other chats: does NOT auto-navigate to official',
        (tester) async {
      when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(null);
      final officialChat = ChatFixtures.model(id: 246, name: 'OneMind');
      when(() => chatService.getOfficialChat())
          .thenAnswer((_) async => officialChat);
      when(() => participantService.joinPublicChat(chatId: any(named: 'chatId')))
          .thenAnswer((_) async => ParticipantFixtures.model());

      final chatA = ChatDashboardInfoFixtures.idle(id: 100, name: 'Chat A');
      final chatB = ChatDashboardInfoFixtures.idle(id: 200, name: 'Chat B');

      await tester.pumpWidget(buildHome(initialChats: [chatA, chatB]));
      await tester.pumpAndSettle();

      verifyNever(() => analytics.logOfficialChatAutoOpened(
            chatId: any(named: 'chatId'),
          ));
    });

    testWidgets(
        'returning visitor (hasAutoJoinedOfficial=true): never invokes auto-navigate path',
        (tester) async {
      // Sanity that the existing early-return still holds end-to-end.
      when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(true);

      await tester.pumpWidget(buildHome(initialChats: const []));
      await tester.pumpAndSettle();

      verifyNever(() => chatService.getOfficialChat());
      verifyNever(() => analytics.logOfficialChatAutoOpened(
            chatId: any(named: 'chatId'),
          ));
    });
  });
}
