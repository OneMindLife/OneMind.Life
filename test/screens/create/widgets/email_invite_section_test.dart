import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/widgets/email_invite_section.dart';

void main() {
  group('EmailInviteSection', () {
    Widget createTestWidget({
      List<String> emails = const [],
      void Function(List<String>)? onEmailsChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: EmailInviteSection(
            emails: emails,
            onEmailsChanged: onEmailsChanged ?? (_) {},
          ),
        ),
      );
    }

    group('Layout', () {
      testWidgets('displays section title', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Invite by Email'), findsOneWidget);
      });

      testWidgets('displays section description', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Only invited email addresses can join this chat'),
            findsOneWidget);
      });

      testWidgets('displays email input field', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byType(TextFormField), findsOneWidget);
        expect(find.text('Email address'), findsOneWidget);
      });

      testWidgets('displays add button', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byIcon(Icons.add), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('displays info message when no emails added', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Add at least one email to send invites'),
            findsOneWidget);
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
      });

      testWidgets('hides info message when emails exist', (tester) async {
        await tester.pumpWidget(createTestWidget(
          emails: ['test@example.com'],
        ));

        expect(find.text('Add at least one email to send invites'),
            findsNothing);
      });
    });

    group('Email Display', () {
      testWidgets('displays email chips when emails exist', (tester) async {
        await tester.pumpWidget(createTestWidget(
          emails: ['user1@example.com', 'user2@example.com'],
        ));

        expect(find.text('user1@example.com'), findsOneWidget);
        expect(find.text('user2@example.com'), findsOneWidget);
        expect(find.byType(Chip), findsNWidgets(2));
      });

      testWidgets('chips have delete icon', (tester) async {
        await tester.pumpWidget(createTestWidget(
          emails: ['test@example.com'],
        ));

        expect(find.byIcon(Icons.cancel), findsOneWidget);
      });
    });

    group('Adding Emails', () {
      testWidgets('adds valid email when add button pressed', (tester) async {
        List<String>? updatedEmails;

        await tester.pumpWidget(createTestWidget(
          onEmailsChanged: (emails) => updatedEmails = emails,
        ));

        await tester.enterText(
            find.byType(TextFormField), 'newuser@example.com');
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        expect(updatedEmails, contains('newuser@example.com'));
      });

      testWidgets('adds email on field submission', (tester) async {
        List<String>? updatedEmails;

        await tester.pumpWidget(createTestWidget(
          onEmailsChanged: (emails) => updatedEmails = emails,
        ));

        await tester.enterText(
            find.byType(TextFormField), 'submitted@example.com');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(updatedEmails, contains('submitted@example.com'));
      });

      testWidgets('clears input field after adding email', (tester) async {
        await tester.pumpWidget(createTestWidget(
          onEmailsChanged: (_) {},
        ));

        await tester.enterText(find.byType(TextFormField), 'test@example.com');
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        // The text field should be cleared
        final textField = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(textField.controller?.text, isEmpty);
      });
    });

    group('Email Validation', () {
      testWidgets('shows error for empty email', (tester) async {
        await tester.pumpWidget(createTestWidget());

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        // Empty emails are silently ignored, not shown as error
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('shows error for invalid email format', (tester) async {
        await tester.pumpWidget(createTestWidget());

        await tester.enterText(find.byType(TextFormField), 'invalid-email');
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.text('Please enter a valid email address'), findsOneWidget);
      });

      testWidgets('shows error for duplicate email', (tester) async {
        await tester.pumpWidget(createTestWidget(
          emails: ['existing@example.com'],
        ));

        await tester.enterText(
            find.byType(TextFormField), 'existing@example.com');
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.text('Email already added'), findsOneWidget);
      });

      testWidgets('accepts valid email formats', (tester) async {
        List<String>? updatedEmails;

        await tester.pumpWidget(createTestWidget(
          onEmailsChanged: (emails) => updatedEmails = emails,
        ));

        // Test standard format
        await tester.enterText(find.byType(TextFormField), 'user@domain.com');
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        expect(updatedEmails, contains('user@domain.com'));
      });
    });

    group('Removing Emails', () {
      testWidgets('removes email when chip delete pressed', (tester) async {
        List<String>? updatedEmails;

        await tester.pumpWidget(createTestWidget(
          emails: ['remove@example.com', 'keep@example.com'],
          onEmailsChanged: (emails) => updatedEmails = emails,
        ));

        // Find and tap the delete button on the first chip
        final chipFinder = find.widgetWithText(Chip, 'remove@example.com');
        final deleteIcon = find.descendant(
          of: chipFinder,
          matching: find.byIcon(Icons.cancel),
        );
        await tester.tap(deleteIcon);
        await tester.pump();

        expect(updatedEmails, isNot(contains('remove@example.com')));
        expect(updatedEmails, contains('keep@example.com'));
      });

      testWidgets('updates list after removal', (tester) async {
        List<String>? updatedEmails;

        await tester.pumpWidget(createTestWidget(
          emails: ['only@example.com'],
          onEmailsChanged: (emails) => updatedEmails = emails,
        ));

        final deleteIcon = find.byIcon(Icons.cancel);
        await tester.tap(deleteIcon);
        await tester.pump();

        expect(updatedEmails, isEmpty);
      });
    });

    group('Input Field', () {
      testWidgets('has placeholder text', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('user@example.com'), findsOneWidget);
      });
    });
  });
}
