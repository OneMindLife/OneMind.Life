import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/providers/notifiers/my_chats_notifier.dart';
import 'package:onemind_app/screens/join/invite_join_screen.dart';
import 'package:onemind_app/services/analytics_service.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/invite_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:onemind_app/services/personal_code_service.dart';
import 'package:onemind_app/services/tutorial_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_analytics/observer.dart';

/// Helper function to create a test Chat with all required fields
Chat _createTestChat({
  required int id,
  required String name,
  required String initialMessage,
  required AccessMethod accessMethod,
  required bool requireApproval,
  String? inviteCode,
  int? maxCycles,
  bool isOfficial = false,
}) {
  return Chat(
    id: id,
    name: name,
    initialMessage: initialMessage,
    accessMethod: accessMethod,
    requireAuth: false,
    requireApproval: requireApproval,
    isActive: true,
    isOfficial: isOfficial,
    startMode: StartMode.manual,
    proposingDurationSeconds: 300,
    ratingDurationSeconds: 300,
    proposingMinimum: 3,
    ratingMinimum: 2,
    enableAiParticipant: false,
    confirmationRoundsRequired: 2,
    showPreviousResults: true,
    propositionsPerUser: 1,
    createdAt: DateTime.now(),
    inviteCode: inviteCode,
    maxCycles: maxCycles,
  );
}

// Mock classes
class MockAuthService extends Mock implements AuthService {}
class MockChatService extends Mock implements ChatService {}
class MockInviteService extends Mock implements InviteService {}
class MockParticipantService extends Mock implements ParticipantService {}
class MockPersonalCodeService extends Mock implements PersonalCodeService {}
class MockTutorialService extends Mock implements TutorialService {}
class MockAnalyticsService extends Mock implements AnalyticsService {
  @override
  FirebaseAnalyticsObserver? get observer => null;
}
class MockSharedPreferences extends Mock implements SharedPreferences {}

/// Mock MyChatsNotifier that avoids Supabase dependencies
class MockMyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    implements MyChatsNotifier {
  MockMyChatsNotifier()
      : super(const AsyncData(MyChatsState()));

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

/// Key used to identify the home page in navigation tests
const _homePageKey = Key('home-page-placeholder');

/// Key prefix used to identify the chat_id query param surfaced by the home
/// placeholder, e.g. `Key('home-chat-id-1')` when navigated to `/?chat_id=1`.
String _homeChatIdKeyValue(int chatId) => 'home-chat-id-$chatId';

void main() {
  late MockAuthService mockAuthService;
  late MockChatService mockChatService;
  late MockInviteService mockInviteService;
  late MockParticipantService mockParticipantService;
  late MockPersonalCodeService mockPersonalCodeService;
  late MockTutorialService mockTutorialService;
  late MockAnalyticsService mockAnalyticsService;
  late MockSharedPreferences mockSharedPreferences;
  late MockMyChatsNotifier mockMyChatsNotifier;

  setUp(() {
    mockAuthService = MockAuthService();
    mockChatService = MockChatService();
    mockInviteService = MockInviteService();
    mockParticipantService = MockParticipantService();
    mockPersonalCodeService = MockPersonalCodeService();
    mockTutorialService = MockTutorialService();
    mockAnalyticsService = MockAnalyticsService();
    mockSharedPreferences = MockSharedPreferences();
    mockMyChatsNotifier = MockMyChatsNotifier();

    // Default stubs — a fresh visitor: no display name yet (names are never
    // auto-generated; the join form's name field is the gate).
    when(() => mockAuthService.displayName).thenReturn(null);
    // hasDisplayName derives from whatever displayName is stubbed to, so
    // per-test displayName overrides stay consistent automatically.
    when(() => mockAuthService.hasDisplayName).thenAnswer((_) {
      final n = mockAuthService.displayName;
      return n != null && n.isNotEmpty;
    });
    when(() => mockAuthService.ensureSignedIn())
        .thenAnswer((_) async => 'test-user-id');
    when(() => mockAuthService.setDisplayName(any()))
        .thenAnswer((_) async {});

    // Default participant service behavior - user is not a participant
    when(() => mockParticipantService.getMyParticipant(any()))
        .thenAnswer((_) async => null);

    // Default tutorial service stubs
    when(() => mockTutorialService.markTutorialComplete())
        .thenAnswer((_) async {});
    when(() => mockTutorialService.markHomeTourComplete())
        .thenAnswer((_) async {});
    when(() => mockTutorialService.hasCompletedTutorial).thenReturn(false);
    when(() => mockTutorialService.hasCompletedHomeTour).thenReturn(false);

    // Default analytics stub
    when(() => mockAnalyticsService.logChatJoined(
          chatId: any(named: 'chatId'),
          joinMethod: any(named: 'joinMethod'),
        )).thenAnswer((_) async {});

    // Default shared preferences stubs
    when(() => mockSharedPreferences.getBool(any())).thenReturn(true);
  });

  /// Creates a test widget wrapped in MaterialApp (without GoRouter).
  /// Suitable for testing UI rendering, form display, error states.
  Widget createTestWidget(Widget child) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuthService),
        chatServiceProvider.overrideWithValue(mockChatService),
        inviteServiceProvider.overrideWithValue(mockInviteService),
        participantServiceProvider.overrideWithValue(mockParticipantService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: child,
      ),
    );
  }

  /// Creates a test widget wrapped in GoRouter-backed MaterialApp.
  /// This allows verifying that context.go('/') navigates to the home route.
  /// [initialRoute] determines which invite route to start on.
  Widget createGoRouterTestWidget({
    String? token,
    String? code,
  }) {
    final router = GoRouter(
      initialLocation: token != null
          ? '/join/invite?token=$token'
          : '/join/${code ?? 'TEST'}',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            final chatIdParam = state.uri.queryParameters['chat_id'];
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Home Page', key: _homePageKey),
                    if (chatIdParam != null)
                      Text(
                        'open chat $chatIdParam',
                        key: Key('home-chat-id-$chatIdParam'),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        // Post-join navigation targets /home?chat_id=N (the '/' route is the
        // marketing landing page, which ignores chat_id). Mirror the home
        // placeholder here so the chat_id auto-open intent is observable.
        GoRoute(
          path: '/home',
          builder: (context, state) {
            final chatIdParam = state.uri.queryParameters['chat_id'];
            final instant = state.uri.queryParameters['instant'] == '1';
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Home Page', key: _homePageKey),
                    if (chatIdParam != null)
                      Text(
                        'open chat $chatIdParam',
                        key: Key('home-chat-id-$chatIdParam'),
                      ),
                    if (instant)
                      const Text('instant', key: Key('home-instant')),
                  ],
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/join/invite',
          builder: (context, state) => InviteJoinScreen(
            token: state.uri.queryParameters['token'],
          ),
        ),
        GoRoute(
          path: '/join/:code',
          builder: (context, state) => InviteJoinScreen(
            code: state.pathParameters['code'],
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuthService),
        chatServiceProvider.overrideWithValue(mockChatService),
        inviteServiceProvider.overrideWithValue(mockInviteService),
        participantServiceProvider.overrideWithValue(mockParticipantService),
        personalCodeServiceProvider.overrideWithValue(mockPersonalCodeService),
        tutorialServiceProvider.overrideWithValue(mockTutorialService),
        analyticsServiceProvider.overrideWithValue(mockAnalyticsService),
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        hasCompletedTutorialProvider.overrideWithValue(true),
        hasCompletedHomeTourProvider.overrideWithValue(true),
        myChatsProvider.overrideWith((ref) => mockMyChatsNotifier),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
  }

  group('InviteJoinScreen', () {
    group('with token', () {
      testWidgets('shows error for invalid token', (tester) async {
        when(() => mockInviteService.validateInviteToken('invalid-token'))
            .thenAnswer((_) async => null);

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(token: 'invalid-token'),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Invalid Invite'), findsOneWidget);
        expect(find.text('This invite link is invalid or has expired'),
            findsOneWidget);
        expect(find.text('Go Home'), findsOneWidget);
      });

      testWidgets('shows chat info for valid token', (tester) async {
        when(() => mockInviteService.validateInviteToken('valid-token'))
            .thenAnswer((_) async => InviteTokenResult(
                  isValid: true,
                  chatId: 1,
                  chatName: 'Test Chat',
                  chatInitialMessage: 'Welcome to the test chat',
                  accessMethod: 'invite_only',
                  requireApproval: false,
                  email: 'test@example.com',
                ));

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(token: 'valid-token'),
        ));
        await tester.pumpAndSettle();

        expect(find.text("You're invited to join"), findsOneWidget);
        expect(find.text('Test Chat'), findsOneWidget);
        expect(find.text('Welcome to the test chat'), findsOneWidget);
      });

      testWidgets('shows approval notice for require_approval chat', (tester) async {
        when(() => mockInviteService.validateInviteToken('approval-token'))
            .thenAnswer((_) async => InviteTokenResult(
                  isValid: true,
                  chatId: 1,
                  chatName: 'Approval Chat',
                  chatInitialMessage: 'Requires approval',
                  accessMethod: 'invite_only',
                  requireApproval: true,
                  email: 'test@example.com',
                ));

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(token: 'approval-token'),
        ));
        await tester.pumpAndSettle();

        expect(find.text('This chat requires host approval to join.'),
            findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Request to Join'), findsOneWidget);
      });

      testWidgets('hides name field when name already set in auth service', (tester) async {
        when(() => mockAuthService.displayName).thenReturn('Pre-filled Name');
        when(() => mockInviteService.validateInviteToken('valid-token'))
            .thenAnswer((_) async => InviteTokenResult(
                  isValid: true,
                  chatId: 1,
                  chatName: 'Test Chat',
                  chatInitialMessage: 'Welcome',
                  accessMethod: 'invite_only',
                  requireApproval: false,
                  email: 'test@example.com',
                ));

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(token: 'valid-token'),
        ));
        await tester.pumpAndSettle();

        // Named user: no name field — a "Joining as X" line with edit pencil.
        expect(find.byKey(const Key('name-section-field')), findsNothing);
        expect(find.text('Joining as Pre-filled Name'), findsOneWidget);
        expect(find.byKey(const Key('name-section-edit')), findsOneWidget);
      });

      testWidgets(
          'shows the name field and gates Join on it when the user has no name',
          (tester) async {
        when(() => mockAuthService.displayName).thenReturn(null);
        when(() => mockInviteService.validateInviteToken('valid-token'))
            .thenAnswer((_) async => InviteTokenResult(
                  isValid: true,
                  chatId: 1,
                  chatName: 'Test Chat',
                  chatInitialMessage: 'Welcome',
                  accessMethod: 'invite_only',
                  requireApproval: false,
                  email: 'test@example.com',
                ));

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(token: 'valid-token'),
        ));
        await tester.pumpAndSettle();

        // Nameless user: the inline name gate is shown...
        expect(find.byKey(const Key('name-section-field')), findsOneWidget);
        // ...and Join stays disabled until a name is typed.
        final joinButton = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Join Chat'));
        expect(joinButton.onPressed, isNull);

        await tester.enterText(
            find.byKey(const Key('name-section-field')), 'Typed Name');
        await tester.pump();
        final enabledButton = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Join Chat'));
        expect(enabledButton.onPressed, isNotNull);
      });
    });

    group('with code', () {
      testWidgets('shows error for non-existent chat code', (tester) async {
        when(() => mockChatService.getChatByCode('ABCDEF'))
            .thenAnswer((_) async => null);

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(code: 'ABCDEF'),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Invalid Invite'), findsOneWidget);
        expect(find.text('Chat not found'), findsOneWidget);
      });

      testWidgets('shows error for invite-only chat accessed via code',
          (tester) async {
        final chat = _createTestChat(
          id: 1,
          name: 'Invite Only Chat',
          initialMessage: 'Test',
          accessMethod: AccessMethod.inviteOnly,
          requireApproval: false,
          inviteCode: 'ABCDEF',
        );
        when(() => mockChatService.getChatByCode('ABCDEF'))
            .thenAnswer((_) async => chat);

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(code: 'ABCDEF'),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Invalid Invite'), findsOneWidget);
        expect(
            find.textContaining('This chat requires an email invite'),
            findsOneWidget);
      });

      testWidgets('shows chat info for public chat code', (tester) async {
        final chat = _createTestChat(
          id: 1,
          name: 'Public Chat',
          initialMessage: 'Welcome to public chat',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'PUBLIC',
        );
        when(() => mockChatService.getChatByCode('PUBLIC'))
            .thenAnswer((_) async => chat);

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(code: 'PUBLIC'),
        ));
        await tester.pumpAndSettle();

        expect(find.text("You're invited to join"), findsOneWidget);
        expect(find.text('Public Chat'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsOneWidget);
      });
    });

    group('quick-chat auto-join (maxCycles == 1)', () {
      testWidgets(
          'quick chat code link auto-joins on arrival — no confirmation screen',
          (tester) async {
        final chat = _createTestChat(
          id: 7,
          name: 'Quick Decision',
          initialMessage: 'Where should we eat?',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'QUICK1',
          maxCycles: 1,
        );
        final participant = Participant(
          id: 70,
          chatId: 7,
          userId: 'test-user-id',
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        );

        when(() => mockAuthService.displayName).thenReturn('Test User');
        when(() => mockChatService.getChatByCode('QUICK1'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(7))
            .thenAnswer((_) async => null);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => participant);

        await tester.pumpWidget(createGoRouterTestWidget(code: 'QUICK1'));
        await tester.pumpAndSettle();

        // The confirmation screen must NOT be shown — the link is the intent.
        expect(find.text("You're invited to join"), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsNothing);

        // It should have auto-joined and landed on home with the chat_id
        // auto-open intent.
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(7))), findsOneWidget);
        verify(() => mockParticipantService.joinChat(
              chatId: 7,
              displayName: 'Test User',
              isHost: false,
            )).called(1);
      });

      testWidgets(
          'incognito visitor (no display name) gets the name gate, then joins',
          (tester) async {
        // A fresh tab landing straight on /join/CODE has no display name.
        // Names are never auto-generated, so instead of silently joining as
        // "Brave Fox" the quick chat falls through to the manual screen whose
        // name field is the only thing between the link and the chat.
        final chat = _createTestChat(
          id: 9,
          name: 'Incognito Quick',
          initialMessage: 'No session yet',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'INCOG1',
          maxCycles: 1,
        );
        final participant = Participant(
          id: 90,
          chatId: 9,
          userId: 'test-user-id',
          displayName: 'Typed Name',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        );

        // displayName stays NULL (the default stub) — the incognito case.
        when(() => mockChatService.getChatByCode('INCOG1'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(9))
            .thenAnswer((_) async => null);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => participant);

        await tester.pumpWidget(createGoRouterTestWidget(code: 'INCOG1'));
        await tester.pumpAndSettle();

        // NOT auto-joined: the manual screen with the name gate is shown.
        expect(find.byKey(const Key('name-section-field')), findsOneWidget);
        final joinButton = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Join Chat'));
        expect(joinButton.onPressed, isNull);

        // Typing a name enables Join; tapping it saves the name and joins.
        await tester.enterText(
            find.byKey(const Key('name-section-field')), 'Typed Name');
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Join Chat'));
        await tester.pumpAndSettle();

        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(9))), findsOneWidget);
        verify(() => mockAuthService.setDisplayName('Typed Name')).called(1);
        verify(() => mockParticipantService.joinChat(
              chatId: 9,
              displayName: 'Typed Name',
              isHost: false,
            )).called(1);
      });

      testWidgets(
          'quick chat that requires approval does NOT auto-join (shows screen)',
          (tester) async {
        final chat = _createTestChat(
          id: 8,
          name: 'Quick But Gated',
          initialMessage: 'Approval needed',
          accessMethod: AccessMethod.code,
          requireApproval: true,
          inviteCode: 'QGATE1',
          maxCycles: 1,
        );

        when(() => mockAuthService.displayName).thenReturn('Test User');
        when(() => mockChatService.getChatByCode('QGATE1'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(8))
            .thenAnswer((_) async => null);

        await tester.pumpWidget(createGoRouterTestWidget(code: 'QGATE1'));
        await tester.pumpAndSettle();

        // Approval gating wins over the quick-chat auto-join: the user must
        // still take an explicit action (the host has to approve).
        expect(find.byKey(_homePageKey), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Request to Join'),
            findsOneWidget);
        verifyNever(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            ));
      });
    });

    group('official chat auto-join (zero-friction GLOBAL front door)', () {
      Chat officialChat() => _createTestChat(
            id: 1260,
            name: 'OneMind Official Chat',
            initialMessage: '',
            accessMethod: AccessMethod.code,
            requireApproval: false,
            inviteCode: 'GLOBAL',
            isOfficial: true,
          );

      Participant officialParticipant(String name) => Participant(
            id: 991,
            chatId: 1260,
            userId: 'test-user-id',
            displayName: name,
            isHost: false,
            isAuthenticated: true,
            status: ParticipantStatus.active,
            createdAt: DateTime.now(),
          );

      testWidgets(
          'fresh visitor: NO name gate — random guest name assigned, straight in',
          (tester) async {
        // displayName stays NULL (the fresh-visitor default), but the mock
        // must store what setDisplayName saves — the join path reads it back.
        when(() => mockAuthService.setDisplayName(any()))
            .thenAnswer((inv) async {
          final n = inv.positionalArguments.first as String;
          when(() => mockAuthService.displayName).thenReturn(n);
        });
        when(() => mockChatService.getChatByCode('GLOBAL'))
            .thenAnswer((_) async => officialChat());
        when(() => mockParticipantService.getMyParticipant(1260))
            .thenAnswer((_) async => null);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer(
            (inv) async => officialParticipant(
                inv.namedArguments[#displayName] as String));

        await tester.pumpWidget(createGoRouterTestWidget(code: 'GLOBAL'));
        await tester.pump();
        // While resolving: bare spinner, no "Join Chat" chrome.
        expect(find.text('Join Chat'), findsNothing);
        await tester.pumpAndSettle();

        // No confirmation screen, no name field, no Join button.
        expect(find.text("You're invited to join"), findsNothing);
        expect(find.byKey(const Key('name-section-field')), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsNothing);

        // Straight into the chat with a generated guest name — and the hop
        // carries instant=1 so Home stays veiled until the chat pushes.
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(1260))), findsOneWidget);
        expect(find.byKey(const Key('home-instant')), findsOneWidget);
        final savedName = verify(
                () => mockAuthService.setDisplayName(captureAny()))
            .captured
            .single as String;
        expect(RegExp(r'^Guest \d{4}$').hasMatch(savedName), isTrue,
            reason: 'random guest name, got "$savedName"');
        verify(() => mockParticipantService.joinChat(
              chatId: 1260,
              displayName: savedName,
              isHost: false,
            )).called(1);
      });

      testWidgets('named user: auto-joins with their own name, no screen',
          (tester) async {
        when(() => mockAuthService.displayName).thenReturn('Joel');
        when(() => mockChatService.getChatByCode('GLOBAL'))
            .thenAnswer((_) async => officialChat());
        when(() => mockParticipantService.getMyParticipant(1260))
            .thenAnswer((_) async => null);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => officialParticipant('Joel'));

        await tester.pumpWidget(createGoRouterTestWidget(code: 'GLOBAL'));
        await tester.pumpAndSettle();

        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(1260))), findsOneWidget);
        // Their existing name is untouched — no random overwrite.
        verifyNever(() => mockAuthService.setDisplayName(any()));
        verify(() => mockParticipantService.joinChat(
              chatId: 1260,
              displayName: 'Joel',
              isHost: false,
            )).called(1);
      });

      testWidgets('returning member: re-entry redirect carries instant=1',
          (tester) async {
        when(() => mockAuthService.displayName).thenReturn('Joel');
        when(() => mockChatService.getChatByCode('GLOBAL'))
            .thenAnswer((_) async => officialChat());
        when(() => mockParticipantService.getMyParticipant(1260))
            .thenAnswer((_) async => officialParticipant('Joel'));

        await tester.pumpWidget(createGoRouterTestWidget(code: 'GLOBAL'));
        await tester.pumpAndSettle();

        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(1260))), findsOneWidget);
        expect(find.byKey(const Key('home-instant')), findsOneWidget);
        verifyNever(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            ));
      });

      testWidgets('non-official chat still gets the name gate', (tester) async {
        // Guard: the bypass is scoped to is_official — a regular public chat
        // keeps the typed-name requirement (D-display-name-gate).
        final chat = _createTestChat(
          id: 55,
          name: 'Regular Public',
          initialMessage: 'hello',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'REG555',
        );
        when(() => mockChatService.getChatByCode('REG555'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(55))
            .thenAnswer((_) async => null);

        await tester.pumpWidget(createGoRouterTestWidget(code: 'REG555'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('name-section-field')), findsOneWidget);
        verifyNever(() => mockAuthService.setDisplayName(any()));
        verifyNever(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            ));
      });
    });

    group('without token or code', () {
      testWidgets('shows error when no parameters provided', (tester) async {
        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Invalid Invite'), findsOneWidget);
        expect(find.text('No invite token or code provided'), findsOneWidget);
      });
    });

    group('already a participant', () {
      testWidgets('shows join form when user is not a participant (code)',
          (tester) async {
        final chat = _createTestChat(
          id: 1,
          name: 'New Chat',
          initialMessage: 'Not a member yet',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'NEWCHT',
        );

        when(() => mockChatService.getChatByCode('NEWCHT'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(chat.id))
            .thenAnswer((_) async => null);

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(code: 'NEWCHT'),
        ));
        await tester.pumpAndSettle();

        // Join form should be shown
        expect(find.text("You're invited to join"), findsOneWidget);
        expect(find.text('New Chat'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsOneWidget);
      });

      testWidgets('shows join form when user was kicked (not active)',
          (tester) async {
        final chat = _createTestChat(
          id: 1,
          name: 'Kicked Chat',
          initialMessage: 'Was kicked',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'KICKED',
        );
        final kickedParticipant = Participant(
          id: 1,
          chatId: chat.id,
          userId: 'test-user-id',
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.kicked,
          createdAt: DateTime.now(),
        );

        when(() => mockChatService.getChatByCode('KICKED'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(chat.id))
            .thenAnswer((_) async => kickedParticipant);

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(code: 'KICKED'),
        ));
        await tester.pumpAndSettle();

        // Join form should be shown (kicked users can rejoin)
        expect(find.text("You're invited to join"), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsOneWidget);
      });

      testWidgets('navigates to home when already active participant (token)',
          (tester) async {
        final activeParticipant = Participant(
          id: 1,
          chatId: 1,
          userId: 'test-user-id',
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        );

        when(() => mockInviteService.validateInviteToken('active-token'))
            .thenAnswer((_) async => InviteTokenResult(
                  isValid: true,
                  chatId: 1,
                  chatName: 'Already Joined Chat',
                  chatInitialMessage: 'Already here',
                  accessMethod: 'invite_only',
                  requireApproval: false,
                  email: 'test@example.com',
                ));
        when(() => mockParticipantService.getMyParticipant(1))
            .thenAnswer((_) async => activeParticipant);

        await tester.pumpWidget(createGoRouterTestWidget(
          token: 'active-token',
        ));
        await tester.pumpAndSettle();

        // Should navigate to home, not show the join form
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.text('Home Page'), findsOneWidget);
        // D37 re-entry fix: an already-joined member re-clicking the invite must
        // REOPEN the chat (chat_id in the URL), not get dumped on the marketing
        // landing. The old `go('/')` had no chat_id → this would fail.
        expect(find.byKey(const Key('home-chat-id-1')), findsOneWidget);
      });

      testWidgets('navigates to home when already active participant (code)',
          (tester) async {
        final chat = _createTestChat(
          id: 1,
          name: 'Already Joined Chat',
          initialMessage: 'Already here',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'ACTIV1',
        );
        final activeParticipant = Participant(
          id: 1,
          chatId: 1,
          userId: 'test-user-id',
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        );

        when(() => mockChatService.getChatByCode('ACTIV1'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(1))
            .thenAnswer((_) async => activeParticipant);

        await tester.pumpWidget(createGoRouterTestWidget(
          code: 'ACTIV1',
        ));
        await tester.pumpAndSettle();

        // Should navigate to home, not show the join form
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.text('Home Page'), findsOneWidget);
        // D37 re-entry fix: an already-joined member re-clicking the invite must
        // REOPEN the chat (chat_id in the URL), not get dumped on the marketing
        // landing. The old `go('/')` had no chat_id → this would fail.
        expect(find.byKey(const Key('home-chat-id-1')), findsOneWidget);
      });
    });

    group('post-join navigation to home', () {
      testWidgets('direct join navigates to home with chat_id auto-open intent',
          (tester) async {
        final chat = _createTestChat(
          id: 1,
          name: 'Direct Join Chat',
          initialMessage: 'Welcome',
          accessMethod: AccessMethod.code,
          requireApproval: false,
          inviteCode: 'DIRJN1',
        );
        final participant = Participant(
          id: 10,
          chatId: 1,
          userId: 'test-user-id',
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        );

        when(() => mockAuthService.displayName).thenReturn('Test User');
        when(() => mockChatService.getChatByCode('DIRJN1'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(1))
            .thenAnswer((_) async => null);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => participant);

        await tester.pumpWidget(createGoRouterTestWidget(
          code: 'DIRJN1',
        ));
        await tester.pumpAndSettle();

        // Should show join form first
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsOneWidget);

        // Tap the join button
        await tester.tap(find.widgetWithText(FilledButton, 'Join Chat'));
        await tester.pumpAndSettle();

        // Should navigate to home with the auto-open chat_id query param so
        // HomeScreen._handleReturnToChat opens the chat the user just joined.
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(1))), findsOneWidget);
      });

      testWidgets('request-to-join (approval required) navigates to home without chat_id',
          (tester) async {
        final joinRequest = JoinRequest(
          id: 1,
          chatId: 1,
          userId: 'test-user-id',
          displayName: 'Test User',
          isAuthenticated: true,
          status: JoinRequestStatus.pending,
          createdAt: DateTime.now(),
        );

        when(() => mockAuthService.displayName).thenReturn('Test User');
        when(() => mockInviteService.validateInviteToken('approval-token'))
            .thenAnswer((_) async => InviteTokenResult(
                  isValid: true,
                  chatId: 1,
                  chatName: 'Approval Chat',
                  chatInitialMessage: 'Needs approval',
                  accessMethod: 'invite_only',
                  requireApproval: true,
                  email: 'test@example.com',
                ));
        when(() => mockParticipantService.getMyParticipant(1))
            .thenAnswer((_) async => null);
        when(() => mockParticipantService.requestToJoin(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
            )).thenAnswer((_) async => joinRequest);

        await tester.pumpWidget(createGoRouterTestWidget(
          token: 'approval-token',
        ));
        await tester.pumpAndSettle();

        // Should show the approval notice and request button
        expect(find.widgetWithText(FilledButton, 'Request to Join'),
            findsOneWidget);

        // Tap request to join
        await tester.tap(find.widgetWithText(FilledButton, 'Request to Join'));
        await tester.pumpAndSettle();

        // Approval-required path: user is NOT yet a participant (only a
        // pending request). Must NOT auto-open the chat — they should land
        // on Home where they can see the pending request status.
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(1))), findsNothing);
      });

      testWidgets('personal code join navigates to home with chat_id auto-open intent',
          (tester) async {
        final chat = _createTestChat(
          id: 1,
          name: 'Personal Code Chat',
          initialMessage: 'Personal code',
          accessMethod: AccessMethod.personalCode,
          requireApproval: false,
          inviteCode: 'PERS01',
        );

        when(() => mockAuthService.displayName).thenReturn('Test User');
        when(() => mockChatService.getChatByCode('PERS01'))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(1))
            .thenAnswer((_) async => null);
        when(() => mockPersonalCodeService.redeemCode(
              code: any(named: 'code'),
              displayName: any(named: 'displayName'),
            )).thenAnswer((_) async => {'chat_id': 1, 'participant_id': 10});

        await tester.pumpWidget(createGoRouterTestWidget(
          code: 'PERS01',
        ));
        await tester.pumpAndSettle();

        // Should show join form (personal code chats still show the join button)
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsOneWidget);

        // Tap join
        await tester.tap(find.widgetWithText(FilledButton, 'Join Chat'));
        await tester.pumpAndSettle();

        // Should navigate to home with the auto-open chat_id query param.
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(1))), findsOneWidget);

        // Verify analytics logged with personal_code method
        verify(() => mockAnalyticsService.logChatJoined(
              chatId: '1',
              joinMethod: 'personal_code',
            )).called(1);
      });

      testWidgets('token-based direct join navigates to home with chat_id auto-open intent',
          (tester) async {
        final participant = Participant(
          id: 10,
          chatId: 1,
          userId: 'test-user-id',
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        );

        when(() => mockAuthService.displayName).thenReturn('Test User');
        when(() => mockInviteService.validateInviteToken('join-token'))
            .thenAnswer((_) async => InviteTokenResult(
                  isValid: true,
                  chatId: 1,
                  chatName: 'Token Join Chat',
                  chatInitialMessage: 'Welcome',
                  accessMethod: 'invite_only',
                  requireApproval: false,
                  email: 'test@example.com',
                ));
        when(() => mockParticipantService.getMyParticipant(1))
            .thenAnswer((_) async => null);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => participant);
        when(() => mockInviteService.acceptInvite(
              inviteToken: any(named: 'inviteToken'),
              participantId: any(named: 'participantId'),
            )).thenAnswer((_) async => true);

        await tester.pumpWidget(createGoRouterTestWidget(
          token: 'join-token',
        ));
        await tester.pumpAndSettle();

        // Should show the join form
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsOneWidget);

        // Tap join
        await tester.tap(find.widgetWithText(FilledButton, 'Join Chat'));
        await tester.pumpAndSettle();

        // Should navigate to home with the auto-open chat_id query param.
        expect(find.byKey(_homePageKey), findsOneWidget);
        expect(find.byKey(Key(_homeChatIdKeyValue(1))), findsOneWidget);

        // Verify invite was accepted
        verify(() => mockInviteService.acceptInvite(
              inviteToken: 'join-token',
              participantId: 10,
            )).called(1);


        // Verify analytics logged with deep_link method
        verify(() => mockAnalyticsService.logChatJoined(
              chatId: '1',
              joinMethod: 'deep_link',
            )).called(1);
      });
    });
  });

  group('InviteTokenResult', () {
    test('constructs with all required fields', () {
      final result = InviteTokenResult(
        isValid: true,
        chatId: 123,
        chatName: 'Test Chat',
        chatInitialMessage: 'Welcome',
        accessMethod: 'invite_only',
        requireApproval: false,
        email: 'test@example.com',
      );

      expect(result.isValid, true);
      expect(result.chatId, 123);
      expect(result.chatName, 'Test Chat');
      expect(result.chatInitialMessage, 'Welcome');
      expect(result.accessMethod, 'invite_only');
      expect(result.requireApproval, false);
      expect(result.email, 'test@example.com');
    });

    test('accessMethod can be invite_only or code', () {
      final inviteOnly = InviteTokenResult(
        isValid: true,
        chatId: 1,
        chatName: 'Test',
        chatInitialMessage: 'Welcome',
        accessMethod: 'invite_only',
        requireApproval: false,
        email: 'test@example.com',
      );

      final codeAccess = InviteTokenResult(
        isValid: true,
        chatId: 2,
        chatName: 'Test 2',
        chatInitialMessage: 'Welcome 2',
        accessMethod: 'code',
        requireApproval: false,
        email: 'test2@example.com',
      );

      expect(inviteOnly.accessMethod, 'invite_only');
      expect(codeAccess.accessMethod, 'code');
    });
  });
}
