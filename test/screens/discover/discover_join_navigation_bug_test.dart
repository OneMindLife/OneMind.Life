import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/screens/action_picker/action_picker_screen.dart';
import 'package:onemind_app/screens/discover/discover_screen.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fixtures/chat_dashboard_info_fixtures.dart';
import '../../fixtures/chat_fixtures.dart';
import '../../fixtures/participant_fixtures.dart';
import '../../fixtures/public_chat_summary_fixtures.dart';
import '../../mocks/mock_services.dart';
import '../../mocks/mock_supabase_client.dart';

class _MockChatService extends Mock implements ChatService {}

class _MockParticipantService extends Mock implements ParticipantService {}

class _MockAuthService extends Mock implements AuthService {}

class _MockLanguageService extends Mock implements LanguageService {
  @override
  String getCurrentLanguage() => 'en';
}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockMyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    implements MyChatsNotifier {
  _MockMyChatsNotifier()
      : super(AsyncData(MyChatsState(
          dashboardChats: ChatDashboardInfoFixtures.fromChats(const []),
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

/// Stub Home page whose FAB mirrors the real `_openActionPicker` in
/// `lib/screens/home/home_screen.dart` — it pushes the action picker
/// through go_router so `context.go()` from a nested screen can clear
/// the entire stack.
class _StubHome extends StatelessWidget {
  const _StubHome({this.returnToChatId});
  final int? returnToChatId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Stub Home'),
            if (returnToChatId != null)
              Text(
                'returnToChatId=$returnToChatId',
                key: const Key('home-return-to-chat'),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/actions'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

void main() {
  late _MockChatService chatService;
  late _MockParticipantService participantService;
  late _MockAuthService authService;
  late _MockLanguageService languageService;
  late MockSupabaseClient supabase;
  late MockRealtimeChannel channel;

  setUpAll(() {
    registerFallbackValues();
  });

  setUp(() {
    chatService = _MockChatService();
    participantService = _MockParticipantService();
    authService = _MockAuthService();
    languageService = _MockLanguageService();
    supabase = MockSupabaseClient();
    channel = MockRealtimeChannel();

    when(() => supabase.channel(any())).thenReturn(channel);
    when(() => supabase.auth).thenReturn(_MockGoTrueClient());
    when(() => channel.onPostgresChanges(
          event: any(named: 'event'),
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          filter: any(named: 'filter'),
          callback: any(named: 'callback'),
        )).thenReturn(channel);
    when(() => channel.subscribe()).thenReturn(channel);
    when(() => channel.unsubscribe()).thenAnswer((_) async => 'ok');

    when(() => authService.currentUserId).thenReturn('test-user');
    when(() => authService.isSignedIn).thenReturn(true);
    when(() => authService.displayName).thenReturn('Tester');
    when(() => authService.hasDisplayName).thenReturn(true);

    final publicChat = PublicChatSummaryFixtures.model(
      id: 1,
      name: 'Friday Plans',
    );
    final fullChat = ChatFixtures.public(id: 1, name: 'Friday Plans');
    final participant = ParticipantFixtures.model(
      id: 1,
      chatId: 1,
      displayName: 'Tester',
    );

    when(() => chatService.getPublicChats(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          languageCode: any(named: 'languageCode'),
        )).thenAnswer((_) async => [publicChat]);
    when(() => chatService.getChatById(1))
        .thenAnswer((_) async => fullChat);
    when(() => participantService.joinChat(
          chatId: any(named: 'chatId'),
          displayName: any(named: 'displayName'),
          isHost: any(named: 'isHost'),
        )).thenAnswer((_) async => participant);
  });

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            final chatIdParam = state.uri.queryParameters['chat_id'];
            return _StubHome(
              returnToChatId:
                  chatIdParam != null ? int.tryParse(chatIdParam) : null,
            );
          },
        ),
        GoRoute(
          path: '/actions',
          builder: (context, state) => const ActionPickerScreen(),
        ),
        GoRoute(
          path: '/discover',
          builder: (context, state) => const DiscoverScreen(),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        chatServiceProvider.overrideWithValue(chatService),
        participantServiceProvider.overrideWithValue(participantService),
        authServiceProvider.overrideWithValue(authService),
        languageServiceProvider.overrideWithValue(languageService),
        supabaseProvider.overrideWithValue(supabase),
        myChatsProvider.overrideWith((ref) => _MockMyChatsNotifier()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
  }

  // Regression guard for the "FAB → Discover → tap chat lands on
  // 'What would you like to do?'" bug. When the action picker was pushed
  // via Navigator.push (root navigator) and Discover via context.push
  // (go_router), DiscoverScreen's `context.go('/?chat_id=N')` would only
  // reset go_router's stack — the action picker stayed stranded on top.
  // Routing the action picker through go_router (`/actions`) keeps the
  // whole stack under one navigator, so context.go clears everything.
  testWidgets(
    'tapping a chat in Discover lands on Home with chat_id, not ActionPicker',
    (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // 1. Tap FAB → context.push('/actions')
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(ActionPickerScreen), findsOneWidget,
          reason: 'ActionPicker should be visible after tapping FAB');

      // 2. Tap "Discover Chats" → context.push('/discover')
      await tester.tap(find.text('Discover Chats'));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoverScreen), findsOneWidget,
          reason: 'DiscoverScreen should be visible after tapping Discover');

      // 3. Tap the chat tile → joinChat → context.go('/?chat_id=1')
      await tester.tap(find.text('Friday Plans'));
      await tester.pumpAndSettle();

      verify(() => participantService.joinChat(
            chatId: 1,
            displayName: 'Tester',
            isHost: false,
          )).called(1);

      // ActionPicker must be gone — otherwise the user sees the
      // "What would you like to do?" screen instead of the joined chat.
      expect(find.byType(ActionPickerScreen), findsNothing,
          reason: 'ActionPicker must be cleared from the stack by context.go');
      expect(find.byType(DiscoverScreen), findsNothing,
          reason: 'Discover must also be cleared — user should be on Home');
      expect(find.byKey(const Key('home-return-to-chat')), findsOneWidget,
          reason: 'Home must receive chat_id=1 so it can auto-open the chat');
    },
  );
}
