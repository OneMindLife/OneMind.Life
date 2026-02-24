import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/join/join_dialog.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/invite_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:onemind_app/services/auth_service.dart';

import '../../fixtures/chat_fixtures.dart';

class MockChatService extends Mock implements ChatService {}

class MockInviteService extends Mock implements InviteService {}

class MockParticipantService extends Mock implements ParticipantService {}

class MockAuthService extends Mock implements AuthService {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockLanguageService extends Mock implements LanguageService {}

void main() {
  late MockChatService mockChatService;
  late MockInviteService mockInviteService;
  late MockParticipantService mockParticipantService;
  late MockAuthService mockAuthService;
  late MockSharedPreferences mockSharedPreferences;
  late MockLanguageService mockLanguageService;

  setUp(() {
    mockChatService = MockChatService();
    mockInviteService = MockInviteService();
    mockParticipantService = MockParticipantService();
    mockAuthService = MockAuthService();
    mockSharedPreferences = MockSharedPreferences();
    mockLanguageService = MockLanguageService();

    // Default auth service behavior
    when(() => mockAuthService.displayName).thenReturn('Test User');
    when(() => mockAuthService.hasDisplayName).thenReturn(true);
    when(() => mockAuthService.currentUserId).thenReturn('test-user-id');
    when(() => mockAuthService.isSignedIn).thenReturn(true);
    when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => 'test-user-id');
    when(() => mockAuthService.setDisplayName(any())).thenAnswer((_) async {});

    // Mock SharedPreferences behavior
    when(() => mockSharedPreferences.getString(any())).thenReturn(null);
    when(() => mockSharedPreferences.setString(any(), any()))
        .thenAnswer((_) async => true);

    // Mock LanguageService behavior
    when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');

    // Default participant service behavior - user is not a participant
    when(() => mockParticipantService.getMyParticipant(any()))
        .thenAnswer((_) async => null);
  });

  Widget createTestWidget({
    void Function(Chat)? onJoined,
  }) {
    return ProviderScope(
      overrides: [
        chatServiceProvider.overrideWithValue(mockChatService),
        inviteServiceProvider.overrideWithValue(mockInviteService),
        participantServiceProvider.overrideWithValue(mockParticipantService),
        authServiceProvider.overrideWithValue(mockAuthService),
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        languageServiceProvider.overrideWithValue(mockLanguageService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => JoinDialog(
                      onJoined: onJoined ?? (_) {},
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
  }

  group('JoinDialog', () {
    group('Initial State', () {
      testWidgets('displays dialog with title', (tester) async {
        await openDialog(tester);

        expect(find.text('Join Chat'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('displays code input instructions', (tester) async {
        await openDialog(tester);

        expect(find.text('Enter the 6-character invite code:'), findsOneWidget);
      });

      testWidgets('displays code text field', (tester) async {
        await openDialog(tester);

        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('displays Find Chat button', (tester) async {
        await openDialog(tester);

        expect(find.text('Find Chat'), findsOneWidget);
      });

      testWidgets('displays Cancel button', (tester) async {
        await openDialog(tester);

        expect(find.text('Cancel'), findsOneWidget);
      });

      testWidgets('does not display a name input field', (tester) async {
        await openDialog(tester);

        // The dialog should only have the invite code TextField, no name field.
        // Verify no display-name-field key exists.
        expect(find.byKey(const Key('display-name-field')), findsNothing);
        // Verify no "Your Name" or "Display Name" label is shown.
        expect(find.text('Your Name'), findsNothing);
        expect(find.text('Display Name'), findsNothing);
        // Only one TextField should exist (the invite code input).
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    group('Code Input', () {
      testWidgets('allows entering code', (tester) async {
        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        // Text appears in both EditableText and TextField, use findsWidgets
        expect(find.text('TEST01'), findsWidgets);
      });

      testWidgets('converts lowercase to uppercase', (tester) async {
        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'test01');
        // The UpperCaseTextFormatter should convert to uppercase
        // Text appears in both EditableText and TextField, use findsWidgets
        expect(find.text('TEST01'), findsWidgets);
      });

      testWidgets('limits input to 6 characters', (tester) async {
        await openDialog(tester);

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.maxLength, 6);
      });
    });

    group('Code Validation', () {
      testWidgets('shows error for code less than 6 characters',
          (tester) async {
        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'ABC');
        await tester.tap(find.text('Find Chat'));
        await tester.pump();

        expect(find.text('Please enter a 6-character code'), findsOneWidget);
      });
    });

    group('Chat Lookup', () {
      testWidgets('shows loading indicator while looking up', (tester) async {
        final completer = Completer<Chat?>();
        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) => completer.future);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete the future to clean up
        completer.complete(null);
        await tester.pump();
      });

      testWidgets('shows error when chat not found', (tester) async {
        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => null);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'NOTFND');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        expect(find.text('Chat not found'), findsOneWidget);
      });

      testWidgets('shows chat details when found', (tester) async {
        final chat = ChatFixtures.model(
          name: 'Test Discussion',
          initialMessage: 'What do you think?',
        );

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => false);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        expect(find.text('Test Discussion'), findsOneWidget);
        expect(find.text('What do you think?'), findsOneWidget);
      });
    });

    group('Joining Chat', () {
      testWidgets('shows Join button after chat found', (tester) async {
        final chat = ChatFixtures.model();

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => false);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        expect(find.text('Join'), findsOneWidget);
      });

      testWidgets('shows Request to Join for approval-required chats',
          (tester) async {
        final chat = ChatFixtures.requiresApproval();

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => false);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        expect(find.text('Request to Join'), findsOneWidget);
        expect(find.text('Host must approve each request'), findsOneWidget);
      });
    });

    group('Invite-Only Chats', () {
      testWidgets('shows invite requirement message', (tester) async {
        final chat = ChatFixtures.model();

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => true);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        expect(find.text('This chat requires an invite'), findsOneWidget);
        expect(find.text('Verify Email'), findsOneWidget);
      });

      testWidgets('shows email input for invite-only chats', (tester) async {
        final chat = ChatFixtures.model();

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => true);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        expect(find.text('Enter the email your invite was sent to:'),
            findsOneWidget);
      });
    });

    group('Cancel', () {
      testWidgets('closes dialog on cancel', (tester) async {
        await openDialog(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    group('Error Handling', () {
      testWidgets('shows error on lookup failure', (tester) async {
        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenThrow(Exception('Network error'));

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        expect(find.text('Failed to lookup chat'), findsOneWidget);
      });
    });

    group('Already a Participant', () {
      testWidgets('redirects to chat when user is already an active participant',
          (tester) async {
        final chat = ChatFixtures.model();
        final existingParticipant = Participant(
          id: 1,
          chatId: chat.id,
          userId: 'test-user-id',
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        );

        Chat? joinedChat;

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(chat.id))
            .thenAnswer((_) async => existingParticipant);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatServiceProvider.overrideWithValue(mockChatService),
              inviteServiceProvider.overrideWithValue(mockInviteService),
              participantServiceProvider.overrideWithValue(mockParticipantService),
              authServiceProvider.overrideWithValue(mockAuthService),
              sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
              languageServiceProvider.overrideWithValue(mockLanguageService),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => JoinDialog(
                            onJoined: (c) => joinedChat = c,
                          ),
                        );
                      },
                      child: const Text('Open Dialog'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        // Dialog should be closed
        expect(find.byType(AlertDialog), findsNothing);
        // onJoined should have been called with the chat
        expect(joinedChat, isNotNull);
        expect(joinedChat!.id, chat.id);
      });

      testWidgets('shows join form when user is not a participant',
          (tester) async {
        final chat = ChatFixtures.model();

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(chat.id))
            .thenAnswer((_) async => null);
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => false);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        // Dialog should still be open with join button
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Join'), findsOneWidget);
      });

      testWidgets('shows join form when user was kicked (not active)',
          (tester) async {
        final chat = ChatFixtures.model();
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

        when(() => mockChatService.getChatByCode(any(), languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chat);
        when(() => mockParticipantService.getMyParticipant(chat.id))
            .thenAnswer((_) async => kickedParticipant);
        when(() => mockInviteService.isInviteOnly(chat.id))
            .thenAnswer((_) async => false);

        await openDialog(tester);

        await tester.enterText(find.byType(TextField), 'TEST01');
        await tester.tap(find.text('Find Chat'));
        await tester.pumpAndSettle();

        // Dialog should still be open (kicked users can rejoin)
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Join'), findsOneWidget);
      });
    });
  });

  group('UpperCaseTextFormatter', () {
    test('converts text to uppercase', () {
      final formatter = UpperCaseTextFormatter();

      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(
          text: 'test01',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );

      expect(result.text, 'TEST01');
      expect(result.selection.baseOffset, 6);
    });

    test('preserves selection position', () {
      final formatter = UpperCaseTextFormatter();

      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: 'AB'),
        const TextEditingValue(
          text: 'ABc',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );

      expect(result.text, 'ABC');
      expect(result.selection.baseOffset, 3);
    });
  });
}
