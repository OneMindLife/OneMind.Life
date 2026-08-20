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

import 'package:onemind_app/screens/chat/chat_screen.dart';

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
    // ChatScreen.initState fires these when _handleReturnToChat navigates
    // into the chat; without the stubs the mount throws on the non-nullable
    // Future return types and fails the test.
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

    // Membership route guard (home_screen._handleReturnToChat): for non-public
    // chats it checks getMyParticipant and only navigates in for an ACTIVE
    // member. Default to an active membership so the existing navigation tests
    // exercise the "member returns to their chat" path; individual tests
    // override this to simulate a non-member.
    when(() => participantService.getMyParticipant(any()))
        .thenAnswer((_) async => ParticipantFixtures.model(status: ParticipantStatus.active));

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

  Widget buildHome({int? returnToChatId, bool instantOpen = false}) {
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
        home: HomeScreen(
            returnToChatId: returnToChatId, instantOpen: instantOpen),
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

  group('HomeScreen membership route guard', () {
    testWidgets(
        'ACTIVE member of a private chat is routed INTO the chat', (tester) async {
      final chat = ChatFixtures.model(
          id: 7, name: 'Private', accessMethod: 'code');
      when(() => chatService.getChatById(7)).thenAnswer((_) async => chat);
      when(() => participantService.getMyParticipant(7)).thenAnswer(
          (_) async => ParticipantFixtures.model(
              chatId: 7, status: ParticipantStatus.active));

      await tester.pumpWidget(buildHome(returnToChatId: 7));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      verify(() => participantService.getMyParticipant(7)).called(1);
      // A member lands inside the chat UI.
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets(
        'NON-member (left/kicked → still passes chats RLS) of a private chat '
        'is NOT dropped into the chat UI', (tester) async {
      // A user who LEFT keeps a participant row, so the `chats` SELECT policy
      // still returns the row and getChatById is non-null — but they are not
      // an ACTIVE member, so the guard must keep them out of the chat screen.
      final chat = ChatFixtures.model(
          id: 8, name: 'Private', accessMethod: 'code');
      when(() => chatService.getChatById(8)).thenAnswer((_) async => chat);
      when(() => participantService.getMyParticipant(8)).thenAnswer(
          (_) async => ParticipantFixtures.model(
              chatId: 8, status: ParticipantStatus.left));

      await tester.pumpWidget(buildHome(returnToChatId: 8));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      verify(() => participantService.getMyParticipant(8)).called(1);
      // The guard bounced them (it attempts context.go('/join/CODE'); under
      // the bare MaterialApp harness that no-ops) — the key invariant is that
      // no ChatScreen was ever pushed for a non-member.
      expect(find.byType(ChatScreen), findsNothing);
    });

    testWidgets(
        'PUBLIC chat renders for a non-member (joinable in place)',
        (tester) async {
      final chat = ChatFixtures.model(
          id: 9, name: 'Public', accessMethod: 'public');
      when(() => chatService.getChatById(9)).thenAnswer((_) async => chat);
      // No membership row at all.
      when(() => participantService.getMyParticipant(9))
          .thenAnswer((_) async => null);

      await tester.pumpWidget(buildHome(returnToChatId: 9));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Public chats short-circuit the guard: membership is never consulted
      // and the chat is allowed to render.
      verifyNever(() => participantService.getMyParticipant(9));
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });

  group('HomeScreen instantOpen (seamless URL → chat)', () {
    testWidgets(
        'veils Home behind a spinner until the chat pushes — no Home flash',
        (tester) async {
      final chat = ChatFixtures.model(
          id: 12, name: 'Official', accessMethod: 'public');
      when(() => chatService.getChatById(12)).thenAnswer((_) async => chat);

      await tester.pumpWidget(buildHome(returnToChatId: 12, instantOpen: true));

      // First frames: bare spinner, NO Home chrome (app bar title 'OneMind').
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('OneMind'), findsNothing);

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The chat screen is up; the veil never showed Home on the way in.
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('drops the veil and falls back to Home when the chat fails',
        (tester) async {
      when(() => chatService.getChatById(13)).thenAnswer((_) async => null);

      await tester.pumpWidget(buildHome(returnToChatId: 13, instantOpen: true));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // No chat to open — Home surfaces as the fallback instead of an
      // infinite spinner.
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('OneMind'), findsOneWidget);
    });

    testWidgets('instantOpen without a chat_id renders Home normally',
        (tester) async {
      await tester.pumpWidget(buildHome(instantOpen: true));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('OneMind'), findsOneWidget);
    });
  });
}
