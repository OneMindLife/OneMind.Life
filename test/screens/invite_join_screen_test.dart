import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/join/invite_join_screen.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/invite_service.dart';
import 'package:onemind_app/services/participant_service.dart';

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

void main() {
  late MockAuthService mockAuthService;
  late MockChatService mockChatService;
  late MockInviteService mockInviteService;
  late MockParticipantService mockParticipantService;

  setUp(() {
    mockAuthService = MockAuthService();
    mockChatService = MockChatService();
    mockInviteService = MockInviteService();
    mockParticipantService = MockParticipantService();

    // Default stubs
    when(() => mockAuthService.displayName).thenReturn(null);
  });

  Widget createTestWidget(Widget child) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuthService),
        chatServiceProvider.overrideWithValue(mockChatService),
        inviteServiceProvider.overrideWithValue(mockInviteService),
        participantServiceProvider.overrideWithValue(mockParticipantService),
      ],
      child: MaterialApp(
        home: child,
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

      testWidgets('pre-fills name from auth service', (tester) async {
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

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.controller?.text, 'Pre-filled Name');
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
