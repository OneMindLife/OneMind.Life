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
}) {
  return Chat(
    id: id,
    name: name,
    initialMessage: initialMessage,
    accessMethod: accessMethod,
    requireAuth: false,
    requireApproval: requireApproval,
    isActive: true,
    isOfficial: false,
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

    // Default stubs
    when(() => mockAuthService.displayName).thenReturn(null);

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

        // Name field should be hidden when name is already set
        expect(find.byType(TextField), findsNothing);
      });

      testWidgets('does not display a name input field for valid token', (tester) async {
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

        // No display-name-field key should exist anywhere on the screen.
        expect(find.byKey(const Key('display-name-field')), findsNothing);
        // No "Your Name" or "Display Name" label should be shown.
        expect(find.text('Your Name'), findsNothing);
        expect(find.text('Display Name'), findsNothing);
        // No TextFormField should be used for name input.
        expect(find.byType(TextFormField), findsNothing);
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
        when(() => mockInviteService.isInviteOnly(1))
            .thenAnswer((_) async => true);

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
        when(() => mockInviteService.isInviteOnly(1))
            .thenAnswer((_) async => false);

        await tester.pumpWidget(createTestWidget(
          const InviteJoinScreen(code: 'PUBLIC'),
        ));
        await tester.pumpAndSettle();

        expect(find.text("You're invited to join"), findsOneWidget);
        expect(find.text('Public Chat'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Join Chat'), findsOneWidget);
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
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => false);

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
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => false);

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
        when(() => mockInviteService.isInviteOnly(1))
            .thenAnswer((_) async => false);
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
