import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/create/create_chat_screen.dart';
import 'package:onemind_app/screens/join/join_dialog.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/invite_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthService extends Mock implements AuthService {}
class MockChatService extends Mock implements ChatService {}
class MockParticipantService extends Mock implements ParticipantService {}
class MockInviteService extends Mock implements InviteService {}
class MockSharedPreferences extends Mock implements SharedPreferences {}
class MockLanguageService extends Mock implements LanguageService {}

void main() {
  late MockAuthService mockAuthService;
  late MockChatService mockChatService;
  late MockParticipantService mockParticipantService;
  late MockInviteService mockInviteService;
  late MockSharedPreferences mockSharedPreferences;
  late MockLanguageService mockLanguageService;

  setUp(() {
    mockAuthService = MockAuthService();
    mockChatService = MockChatService();
    mockParticipantService = MockParticipantService();
    mockInviteService = MockInviteService();
    mockSharedPreferences = MockSharedPreferences();
    mockLanguageService = MockLanguageService();

    // Setup default auth behavior
    when(() => mockAuthService.currentUserId).thenReturn('test-user-id');
    when(() => mockAuthService.isSignedIn).thenReturn(true);
    when(() => mockAuthService.displayName).thenReturn('Test User');
    when(() => mockAuthService.hasDisplayName).thenReturn(true);
    when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => 'test-user-id');

    // Mock SharedPreferences behavior
    when(() => mockSharedPreferences.getString(any())).thenReturn(null);
    when(() => mockSharedPreferences.setString(any(), any()))
        .thenAnswer((_) async => true);

    // Mock LanguageService behavior
    when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');
  });

  group('CreateChatScreen', () {
    testWidgets('displays title and basic info section', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(mockAuthService),
            chatServiceProvider.overrideWithValue(mockChatService),
            participantServiceProvider.overrideWithValue(mockParticipantService),
          ],
          child: const MaterialApp(
            home: CreateChatScreen(),
          ),
        ),
      );

      // Check that the title is displayed
      expect(find.text('Create Chat'), findsOneWidget);

      // Check that basic info section is present
      expect(find.text('Basic Info'), findsOneWidget);

      // Check that required fields are present
      expect(find.text('Chat Name *'), findsOneWidget);
      expect(find.text('Initial Message *'), findsOneWidget);
    });

    testWidgets('displays access method selector', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(mockAuthService),
            chatServiceProvider.overrideWithValue(mockChatService),
            participantServiceProvider.overrideWithValue(mockParticipantService),
          ],
          child: const MaterialApp(
            home: CreateChatScreen(),
          ),
        ),
      );

      // Check that access method options are present (public is default)
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Invite Code'), findsOneWidget);
      expect(find.text('Email Invite Only'), findsOneWidget);
    });
  });

  group('JoinDialog', () {
    testWidgets('displays invite code prompt', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(mockAuthService),
            chatServiceProvider.overrideWithValue(mockChatService),
            participantServiceProvider.overrideWithValue(mockParticipantService),
            inviteServiceProvider.overrideWithValue(mockInviteService),
            sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
            languageServiceProvider.overrideWithValue(mockLanguageService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: JoinDialog(
                onJoined: (_) {},
              ),
            ),
          ),
        ),
      );

      // Allow async operations to complete
      await tester.pumpAndSettle();

      // Check that the dialog title is displayed
      expect(find.text('Join Chat'), findsOneWidget);

      // Check that the prompt is present
      expect(find.text('Enter the 6-character invite code:'), findsOneWidget);
    });

    testWidgets('displays buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(mockAuthService),
            chatServiceProvider.overrideWithValue(mockChatService),
            participantServiceProvider.overrideWithValue(mockParticipantService),
            inviteServiceProvider.overrideWithValue(mockInviteService),
            sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
            languageServiceProvider.overrideWithValue(mockLanguageService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: JoinDialog(
                onJoined: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check that buttons are present
      expect(find.text('Find Chat'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('validates short code', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(mockAuthService),
            chatServiceProvider.overrideWithValue(mockChatService),
            participantServiceProvider.overrideWithValue(mockParticipantService),
            inviteServiceProvider.overrideWithValue(mockInviteService),
            sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
            languageServiceProvider.overrideWithValue(mockLanguageService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: JoinDialog(
                onJoined: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter a short code
      await tester.enterText(find.byType(TextField), 'ABC');

      // Find and tap the Find Chat button
      final findButton = find.text('Find Chat');
      await tester.tap(findButton);
      await tester.pump();

      // Check for validation error
      expect(find.text('Please enter a 6-character code'), findsOneWidget);
    });

    testWidgets('converts code to uppercase', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(mockAuthService),
            chatServiceProvider.overrideWithValue(mockChatService),
            participantServiceProvider.overrideWithValue(mockParticipantService),
            inviteServiceProvider.overrideWithValue(mockInviteService),
            sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
            languageServiceProvider.overrideWithValue(mockLanguageService),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: JoinDialog(
                onJoined: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter lowercase text
      await tester.enterText(find.byType(TextField), 'abcdef');
      await tester.pump();

      // Check that the text is converted to uppercase
      expect(find.text('ABCDEF'), findsOneWidget);
    });
  });
}
