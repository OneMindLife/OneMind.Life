import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/create/widgets/visibility_section.dart';

void main() {
  group('VisibilitySection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Visibility'), findsOneWidget);
    });

    testWidgets('displays helper text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Who can find and join this chat?'), findsOneWidget);
    });

    testWidgets('displays all access method options', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Anyone can discover and join'), findsOneWidget);
      expect(find.text('Invite Code'), findsOneWidget);
      expect(find.text('Share a 6-character code to join'), findsOneWidget);
      expect(find.text('Email Invite Only'), findsOneWidget);
      expect(find.text('Only invited email addresses can join'), findsOneWidget);
    });

    // Skip: Require authentication UI is disabled pending user auth implementation
    // See lib/screens/create/widgets/visibility_section.dart TODO comment
    testWidgets('displays require authentication switch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Require authentication'), findsOneWidget);
    }, skip: true); // Require authentication UI disabled - see visibility_section.dart TODO

    testWidgets('shows anonymous subtitle when auth not required',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Anonymous users allowed'), findsOneWidget);
    }, skip: true); // Require authentication UI disabled - see visibility_section.dart TODO

    testWidgets('shows sign in subtitle when auth required', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.code,
                inviteEmails: const [],
                requireAuth: true,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Users must sign in'), findsOneWidget);
    }, skip: true); // Require authentication UI disabled - see visibility_section.dart TODO

    testWidgets('hides require approval for public access', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Require approval'), findsNothing);
    });

    testWidgets('shows require approval for code access', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.code,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Require approval'), findsOneWidget);
    });

    testWidgets('shows require approval for invite only access', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.inviteOnly,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Require approval'), findsOneWidget);
    });

    testWidgets('shows email invite section for invite only', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.inviteOnly,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Invite by Email'), findsOneWidget);
    });

    testWidgets('hides email invite section for other access methods',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.code,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Invite by Email'), findsNothing);
    });

    testWidgets('calls onAccessMethodChanged when selecting method',
        (tester) async {
      AccessMethod? updatedMethod;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (v) => updatedMethod = v,
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Tap the "Invite Code" option
      await tester.tap(find.text('Invite Code'));
      await tester.pump();

      expect(updatedMethod, AccessMethod.code);
    });

    testWidgets('calls onRequireAuthChanged when toggling', (tester) async {
      bool? updatedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.public,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (v) => updatedValue = v,
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Tap the auth switch
      await tester.tap(find.byType(Switch).first);
      await tester.pump();

      expect(updatedValue, isTrue);
    }, skip: true); // Require authentication UI disabled - see visibility_section.dart TODO

    testWidgets('shows check icon for selected access method', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisibilitySection(
                accessMethod: AccessMethod.code,
                inviteEmails: const [],
                requireAuth: false,
                requireApproval: false,
                onAccessMethodChanged: (_) {},
                onEmailsChanged: (_) {},
                onRequireAuthChanged: (_) {},
                onRequireApprovalChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });
}
