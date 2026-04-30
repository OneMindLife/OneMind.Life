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

import '../../fixtures/chat_fixtures.dart';
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
  _FakeMyChatsNotifier()
      : super(AsyncData(MyChatsState(
          dashboardChats: const [],
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

/// Regression test for the push-notification routing bug:
///
/// When the user has chat A pushed on top of Home, then taps a
/// notification for chat B, the push handler does
/// `context.go('/?chat_id=B')`. go_router rebuilds HomeScreen with
/// `returnToChatId=B`. But `_handleReturnToChat()` is only called from
/// `initState` — it never re-runs when widget.returnToChatId changes
/// mid-session. Result: the URL says "open chat B" but chat A stays on
/// top and the user never navigates anywhere.
///
/// We verify the fix by checking whether `chatService.getChatById` is
/// called for the new chat after the widget is rebuilt with a new
/// returnToChatId. That's a tight, render-free signal of whether
/// _handleReturnToChat ran again.
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

    // Returning user — skip the auto-join-official-chat path entirely
    // so the only navigation we observe is from _handleReturnToChat.
    when(() => prefs.getBool('official_chat_auto_joined')).thenReturn(true);
    when(() => chatService.getOfficialChat()).thenAnswer((_) async => null);
    when(() => chatService.getMyChats()).thenAnswer((_) async => []);
    when(() => chatService.getPublicChats(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => []);
  });

  Widget buildHome({int? returnToChatId}) {
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
        myChatsProvider.overrideWith((ref) => _FakeMyChatsNotifier()),
        officialChatProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        // Pass returnToChatId via constructor — this mimics what the
        // router does when the URL becomes /?chat_id=N.
        home: HomeScreen(returnToChatId: returnToChatId),
      ),
    );
  }

  group('HomeScreen returnToChatId routing', () {
    testWidgets(
        'initial mount with returnToChatId calls chatService.getChatById',
        (tester) async {
      final chat1 = ChatFixtures.model(id: 1, name: 'Chat A');
      when(() => chatService.getChatById(1)).thenAnswer((_) async => chat1);

      await tester.pumpWidget(buildHome(returnToChatId: 1));
      // pump enough for the postFrameCallback + the awaited fetch
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      verify(() => chatService.getChatById(1)).called(1);
    });

    testWidgets(
        'BUG: rebuilding with a new returnToChatId mid-session does NOT '
        're-run _handleReturnToChat (push-notification routing bug)',
        (tester) async {
      final chat1 = ChatFixtures.model(id: 1, name: 'Chat A');
      final chat2 = ChatFixtures.model(id: 2, name: 'Chat B');
      when(() => chatService.getChatById(1)).thenAnswer((_) async => chat1);
      when(() => chatService.getChatById(2)).thenAnswer((_) async => chat2);

      // Initial mount: app opened with chat A
      await tester.pumpWidget(buildHome(returnToChatId: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      verify(() => chatService.getChatById(1)).called(1);

      // Now simulate a push-notification tap that updates the route to
      // /?chat_id=2 — go_router rebuilds HomeScreen with the new param.
      await tester.pumpWidget(buildHome(returnToChatId: 2));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // After the fix: chat 2 is fetched (and would be navigated to).
      // Pre-fix: this assertion fails — getChatById(2) was never called
      // because _handleReturnToChat only runs in initState.
      verify(() => chatService.getChatById(2)).called(1);
    });
  });
}
