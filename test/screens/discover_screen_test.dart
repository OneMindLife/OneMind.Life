import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/public_chat_summary.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/discover/discover_screen.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixtures/public_chat_summary_fixtures.dart';
import '../fixtures/chat_fixtures.dart';
import '../fixtures/participant_fixtures.dart';
import '../mocks/mock_services.dart';
import '../mocks/mock_supabase_client.dart';

class MockChatService extends Mock implements ChatService {}

class MockParticipantService extends Mock implements ParticipantService {}

class MockAuthService extends Mock implements AuthService {}

class MockLanguageService extends Mock implements LanguageService {}

/// Prevents real Supabase initialization in tests
class MockGoTrueClientLocal extends Mock implements GoTrueClient {}

void main() {
  late MockChatService mockChatService;
  late MockParticipantService mockParticipantService;
  late MockAuthService mockAuthService;
  late MockLanguageService mockLanguageService;
  late MockSupabaseClient mockSupabase;
  late MockRealtimeChannel mockChannel;

  setUpAll(() {
    registerFallbackValues();
  });

  setUp(() {
    mockChatService = MockChatService();
    mockParticipantService = MockParticipantService();
    mockAuthService = MockAuthService();
    mockLanguageService = MockLanguageService();
    mockSupabase = MockSupabaseClient();
    mockChannel = MockRealtimeChannel();

    // Setup Supabase channel mocking for realtime subscriptions
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

    // Default auth service behavior
    when(() => mockAuthService.currentUserId).thenReturn('test-user-id');
    when(() => mockAuthService.isSignedIn).thenReturn(true);
    when(() => mockAuthService.displayName).thenReturn('Test User');
    when(() => mockAuthService.hasDisplayName).thenReturn(true);
    when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => 'test-user-id');
    when(() => mockAuthService.setDisplayName(any())).thenAnswer((_) async {});

    // Default language service behavior
    when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');
  });

  Widget createTestWidget() {
    return ProviderScope(
      overrides: [
        chatServiceProvider.overrideWithValue(mockChatService),
        participantServiceProvider.overrideWithValue(mockParticipantService),
        authServiceProvider.overrideWithValue(mockAuthService),
        languageServiceProvider.overrideWithValue(mockLanguageService),
        supabaseProvider.overrideWithValue(mockSupabase),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const DiscoverScreen(),
      ),
    );
  }

  group('DiscoverScreen', () {
    group('UI Elements', () {
      testWidgets('displays app bar with title', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Discover Chats'), findsOneWidget);
      });

      testWidgets('displays search bar', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.search), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('displays search hint text', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Search public chats...'), findsOneWidget);
      });
    });

    group('Loading State', () {
      testWidgets('shows loading indicator initially', (tester) async {
        // Use a completer to control when the future completes
        final completer = Completer<List<PublicChatSummary>>();
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) => completer.future);

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete the future to allow test to finish cleanly
        completer.complete([]);
        await tester.pumpAndSettle();
      });
    });

    group('Empty State', () {
      testWidgets('displays empty state when no public chats', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('No public chats available'), findsOneWidget);
        expect(find.text('Be the first to create one!'), findsOneWidget);
        expect(find.byIcon(Icons.public_off), findsOneWidget);
      });

      testWidgets('displays search empty state when no search results', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);
        when(() => mockChatService.searchPublicChats(
              any(),
              limit: any(named: 'limit'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Enter search query
        await tester.enterText(find.byType(TextField), 'nonexistent');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.textContaining('No chats found for'), findsOneWidget);
      });
    });

    group('Chat List', () {
      testWidgets('displays list of public chats', (tester) async {
        final chats = PublicChatSummaryFixtures.list(count: 3);
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => chats);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Public Chat 1'), findsOneWidget);
        expect(find.text('Public Chat 2'), findsOneWidget);
        expect(find.text('Public Chat 3'), findsOneWidget);
      });

      testWidgets('displays participant count for each chat', (tester) async {
        final chats = [
          PublicChatSummaryFixtures.model(
            id: 1,
            name: 'Chat One',
            participantCount: 5,
          ),
        ];
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => chats);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('5 participants'), findsOneWidget);
      });

      testWidgets('displays singular participant text for 1 participant', (tester) async {
        final chats = [
          PublicChatSummaryFixtures.model(
            id: 1,
            name: 'Solo Chat',
            participantCount: 1,
          ),
        ];
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => chats);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('1 participant'), findsOneWidget);
      });

      testWidgets('displays description when available', (tester) async {
        final chats = [
          PublicChatSummaryFixtures.model(
            id: 1,
            name: 'Descriptive Chat',
            description: 'This is a detailed description',
          ),
        ];
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => chats);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('This is a detailed description'), findsOneWidget);
      });

      testWidgets('displays initial message', (tester) async {
        final chats = [
          PublicChatSummaryFixtures.model(
            id: 1,
            name: 'Message Chat',
            initialMessage: 'What is the meaning of life?',
          ),
        ];
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => chats);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('What is the meaning of life?'), findsOneWidget);
      });

      testWidgets('displays Join button for each chat', (tester) async {
        final chats = PublicChatSummaryFixtures.list(count: 2);
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => chats);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Join'), findsNWidgets(2));
      });

      testWidgets('displays public icon for each chat', (tester) async {
        final chats = [PublicChatSummaryFixtures.model()];
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => chats);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.public), findsOneWidget);
      });
    });

    group('Search', () {
      testWidgets('calls searchPublicChats when search submitted', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);
        when(() => mockChatService.searchPublicChats(
              'test query',
              limit: any(named: 'limit'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'test query');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        verify(() => mockChatService.searchPublicChats(
              'test query',
              limit: any(named: 'limit'),
              languageCode: any(named: 'languageCode'),
            )).called(1);
      });

      testWidgets('shows clear button when search has text', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // No clear button initially
        expect(find.byIcon(Icons.clear), findsNothing);

        // Enter text
        await tester.enterText(find.byType(TextField), 'search text');
        await tester.pump();

        // Clear button should appear
        expect(find.byIcon(Icons.clear), findsOneWidget);
      });

      testWidgets('clear button resets search', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Enter text
        await tester.enterText(find.byType(TextField), 'search text');
        await tester.pump();

        // Tap clear
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();

        // Verify getPublicChats was called again (to reload)
        verify(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).called(greaterThan(1));
      });
    });

    group('Error State', () {
      testWidgets('displays error message on failure', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenThrow(Exception('Network error'));

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      });

      testWidgets('retry button reloads chats', (tester) async {
        int callCount = 0;
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw Exception('Network error');
          }
          return [];
        });

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Verify error state
        expect(find.text('Retry'), findsOneWidget);

        // Tap retry
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        // Verify reload was attempted
        expect(callCount, 2);
      });
    });

    group('Pull to Refresh', () {
      testWidgets('can pull to refresh the list', (tester) async {
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => PublicChatSummaryFixtures.list(count: 2));

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Pull down to refresh
        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pumpAndSettle();

        // Verify getPublicChats was called again
        verify(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).called(greaterThan(1));
      });
    });

    group('Join Flow - Display Name Logic', () {
      late MockSupabaseClient mockSupabaseClient;
      late MockRealtimeChannel mockChannelLocal;

      setUp(() {
        mockSupabaseClient = MockSupabaseClient();
        mockChannelLocal = MockRealtimeChannel();

        // Setup channel mocking for realtime subscriptions
        when(() => mockSupabaseClient.channel(any())).thenReturn(mockChannelLocal);
        when(() => mockChannelLocal.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenReturn(mockChannelLocal);
        when(() => mockChannelLocal.subscribe()).thenReturn(mockChannelLocal);
        when(() => mockChannelLocal.unsubscribe()).thenAnswer((_) async => 'ok');

        // Prevent Supabase from trying to make real network calls
        when(() => mockSupabaseClient.auth).thenReturn(MockGoTrueClientLocal());
      });

      Widget createJoinTestWidget() {
        return ProviderScope(
          overrides: [
            // Override Supabase providers to prevent real network calls
            supabaseProvider.overrideWithValue(mockSupabaseClient),
            // Override service providers with mocks
            chatServiceProvider.overrideWithValue(mockChatService),
            participantServiceProvider.overrideWithValue(mockParticipantService),
            authServiceProvider.overrideWithValue(mockAuthService),
            languageServiceProvider.overrideWithValue(mockLanguageService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const DiscoverScreen(),
          ),
        );
      }

      testWidgets('uses stored display name when available', (tester) async {
        // Setup: Public chat with stored display name
        final publicChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Test Public Chat',
        );
        final fullChat = ChatFixtures.public(id: 1, name: 'Test Public Chat');
        final participant = ParticipantFixtures.model(
          id: 1,
          chatId: 1,
          displayName: 'Stored Name',
        );

        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [publicChat]);
        when(() => mockChatService.getChatById(1)).thenAnswer((_) async => fullChat);
        when(() => mockAuthService.displayName).thenReturn('Stored Name');
        when(() => mockAuthService.hasDisplayName).thenReturn(true);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => participant);

        await tester.pumpWidget(createJoinTestWidget());
        await tester.pumpAndSettle();

        // Tap Join button
        await tester.tap(find.text('Join'));
        // Use pump() with duration to allow async operations without waiting for navigation
        await tester.pump(const Duration(milliseconds: 500));

        // Verify joinChat was called with stored name, no prompt dialog
        verify(() => mockParticipantService.joinChat(
              chatId: 1,
              displayName: 'Stored Name',
              isHost: false,
            )).called(1);
      });

      testWidgets('allows Anonymous for official OneMind chat without prompting', (tester) async {
        // Setup: Official OneMind chat with no stored name
        // Note: PublicChatSummary doesn't have isOfficial; we get it from the full Chat
        final officialChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'OneMind',
        );
        final fullChat = ChatFixtures.official();
        final participant = ParticipantFixtures.model(
          id: 1,
          chatId: 1,
          displayName: 'Anonymous',
        );

        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [officialChat]);
        when(() => mockChatService.getChatById(1)).thenAnswer((_) async => fullChat);
        when(() => mockAuthService.displayName).thenReturn(null);
        when(() => mockAuthService.hasDisplayName).thenReturn(false);
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => participant);

        await tester.pumpWidget(createJoinTestWidget());
        await tester.pumpAndSettle();

        // Tap Join button
        await tester.tap(find.text('Join'));
        // Use pump() with duration to allow async operations without waiting for navigation
        await tester.pump(const Duration(milliseconds: 500));

        // Verify joinChat was called with 'Anonymous', no prompt dialog shown
        verify(() => mockParticipantService.joinChat(
              chatId: 1,
              displayName: 'Anonymous',
              isHost: false,
            )).called(1);

        // Verify no name prompt dialog appeared
        expect(find.text('Enter Your Name'), findsNothing);
      });

      testWidgets('prompts for name when joining non-official public chat without stored name', (tester) async {
        // Setup: Non-official public chat with no stored name
        final publicChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Community Chat',
        );
        final fullChat = ChatFixtures.public(id: 1, name: 'Community Chat');

        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [publicChat]);
        when(() => mockChatService.getChatById(1)).thenAnswer((_) async => fullChat);
        when(() => mockAuthService.displayName).thenReturn(null);
        when(() => mockAuthService.hasDisplayName).thenReturn(false);

        await tester.pumpWidget(createJoinTestWidget());
        await tester.pumpAndSettle();

        // Tap Join button
        await tester.tap(find.text('Join'));
        await tester.pumpAndSettle();

        // Verify name prompt dialog appears
        expect(find.text('Enter Your Name'), findsOneWidget);
        expect(find.text('Your display name'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      });

      testWidgets('canceling name prompt cancels join', (tester) async {
        // Setup: Non-official public chat with no stored name
        final publicChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Community Chat',
        );
        final fullChat = ChatFixtures.public(id: 1, name: 'Community Chat');

        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [publicChat]);
        when(() => mockChatService.getChatById(1)).thenAnswer((_) async => fullChat);
        when(() => mockAuthService.displayName).thenReturn(null);
        when(() => mockAuthService.hasDisplayName).thenReturn(false);

        await tester.pumpWidget(createJoinTestWidget());
        await tester.pumpAndSettle();

        // Tap Join button
        await tester.tap(find.text('Join'));
        await tester.pumpAndSettle();

        // Verify dialog appears
        expect(find.text('Enter Your Name'), findsOneWidget);

        // Tap Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Verify joinChat was never called
        verifyNever(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            ));
      });

      testWidgets('entering name in prompt joins with that name and saves it', (tester) async {
        // Setup: Non-official public chat with no stored name
        final publicChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Community Chat',
        );
        final fullChat = ChatFixtures.public(id: 1, name: 'Community Chat');
        final participant = ParticipantFixtures.model(
          id: 1,
          chatId: 1,
          displayName: 'New User',
        );

        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [publicChat]);
        when(() => mockChatService.getChatById(1)).thenAnswer((_) async => fullChat);
        when(() => mockAuthService.displayName).thenReturn(null);
        when(() => mockAuthService.hasDisplayName).thenReturn(false);
        when(() => mockAuthService.setDisplayName(any())).thenAnswer((_) async {});
        when(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            )).thenAnswer((_) async => participant);

        await tester.pumpWidget(createJoinTestWidget());
        await tester.pumpAndSettle();

        // Tap Join button
        await tester.tap(find.text('Join'));
        await tester.pumpAndSettle();

        // Enter name in dialog
        await tester.enterText(find.byType(TextField).last, 'New User');
        await tester.pump();

        // Tap Join button in dialog
        await tester.tap(find.widgetWithText(ElevatedButton, 'Join'));
        // Use pump() with duration to allow async operations without waiting for navigation
        await tester.pump(const Duration(milliseconds: 500));

        // Verify setDisplayName was called to save the name
        verify(() => mockAuthService.setDisplayName('New User')).called(1);

        // Verify joinChat was called with the entered name
        verify(() => mockParticipantService.joinChat(
              chatId: 1,
              displayName: 'New User',
              isHost: false,
            )).called(1);
      });

      testWidgets('empty name in prompt does not join', (tester) async {
        // Setup: Non-official public chat with no stored name
        final publicChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Community Chat',
        );
        final fullChat = ChatFixtures.public(id: 1, name: 'Community Chat');

        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [publicChat]);
        when(() => mockChatService.getChatById(1)).thenAnswer((_) async => fullChat);
        when(() => mockAuthService.displayName).thenReturn(null);
        when(() => mockAuthService.hasDisplayName).thenReturn(false);

        await tester.pumpWidget(createJoinTestWidget());
        await tester.pumpAndSettle();

        // Tap Join button
        await tester.tap(find.text('Join'));
        await tester.pumpAndSettle();

        // Leave name field empty and tap Join
        await tester.tap(find.widgetWithText(ElevatedButton, 'Join'));
        await tester.pumpAndSettle();

        // Dialog should still be open (empty name not accepted)
        expect(find.text('Enter Your Name'), findsOneWidget);

        // Verify joinChat was never called
        verifyNever(() => mockParticipantService.joinChat(
              chatId: any(named: 'chatId'),
              displayName: any(named: 'displayName'),
              isHost: any(named: 'isHost'),
            ));
      });
    });

    group('Translation Support', () {
      testWidgets('displays translated name when available', (tester) async {
        final translatedChat = PublicChatSummaryFixtures.withSpanishTranslation(
          id: 1,
          name: 'Original Name',
        );
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [translatedChat]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should display translated name
        expect(find.text('Chat de Prueba'), findsOneWidget);
        // Original name should not be visible (since translation is available)
        expect(find.text('Original Name'), findsNothing);
      });

      testWidgets('displays translated description when available', (tester) async {
        final translatedChat = PublicChatSummaryFixtures.withSpanishTranslation(
          id: 1,
          name: 'Test Chat',
          description: 'Original Description',
        );
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [translatedChat]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should display translated description
        expect(find.text('Descripcion de Prueba'), findsOneWidget);
      });

      testWidgets('displays translated initial message when available', (tester) async {
        final translatedChat = PublicChatSummaryFixtures.withSpanishTranslation(
          id: 1,
          name: 'Test Chat',
          initialMessage: 'What should we discuss?',
        );
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [translatedChat]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should display translated initial message
        expect(find.text('Que deberiamos discutir?'), findsOneWidget);
      });

      testWidgets('falls back to original name when no translation', (tester) async {
        final untranslatedChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Original Name Only',
        );
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [untranslatedChat]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should display original name
        expect(find.text('Original Name Only'), findsOneWidget);
      });

      testWidgets('falls back to original description when no translation', (tester) async {
        final untranslatedChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Chat',
          description: 'Original Description Only',
        );
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [untranslatedChat]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should display original description
        expect(find.text('Original Description Only'), findsOneWidget);
      });

      testWidgets('falls back to original initial message when no translation', (tester) async {
        final untranslatedChat = PublicChatSummaryFixtures.model(
          id: 1,
          name: 'Chat',
          initialMessage: 'Original Message Only',
        );
        when(() => mockChatService.getPublicChats(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              languageCode: any(named: 'languageCode'),
            )).thenAnswer((_) async => [untranslatedChat]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Should display original initial message
        expect(find.text('Original Message Only'), findsOneWidget);
      });
    });
  });
}
