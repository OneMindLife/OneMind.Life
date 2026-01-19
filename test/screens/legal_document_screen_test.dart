import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/legal/legal_document_screen.dart';

void main() {
  group('LegalDocumentScreen', () {
    group('Privacy Policy', () {
      testWidgets('displays Privacy Policy title', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.privacyPolicy(),
          ),
        );

        expect(find.text('Privacy Policy'), findsAtLeastNWidgets(1));
      });

      testWidgets('displays last updated date', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.privacyPolicy(),
          ),
        );

        expect(find.textContaining('Last updated:'), findsOneWidget);
      });

      testWidgets('displays Information We Collect section', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.privacyPolicy(),
          ),
        );

        expect(find.text('1. Information We Collect'), findsOneWidget);
      });

      testWidgets('displays How We Use Your Information section',
          (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.privacyPolicy(),
          ),
        );

        expect(find.text('2. How We Use Your Information'), findsOneWidget);
      });

      testWidgets('displays Contact Us section', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.privacyPolicy(),
          ),
        );

        // Scroll to bottom to find Contact Us section
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
        await tester.pumpAndSettle();

        expect(find.text('8. Contact Us'), findsOneWidget);
      });

      testWidgets('is scrollable', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.privacyPolicy(),
          ),
        );

        expect(find.byType(SingleChildScrollView), findsOneWidget);
      });
    });

    group('Terms of Service', () {
      testWidgets('displays Terms of Service title', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.termsOfService(),
          ),
        );

        expect(find.text('Terms of Service'), findsAtLeastNWidgets(1));
      });

      testWidgets('displays last updated date', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.termsOfService(),
          ),
        );

        expect(find.textContaining('Last updated:'), findsOneWidget);
      });

      testWidgets('displays Acceptance of Terms section', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.termsOfService(),
          ),
        );

        expect(find.text('1. Acceptance of Terms'), findsOneWidget);
      });

      testWidgets('displays Use of Services section', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.termsOfService(),
          ),
        );

        expect(find.text('2. Use of Services'), findsOneWidget);
      });

      testWidgets('displays Credits and Payments section', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.termsOfService(),
          ),
        );

        // Scroll to find the section
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();

        expect(find.text('4. Credits and Payments'), findsOneWidget);
      });

      testWidgets('displays Contact section', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen.termsOfService(),
          ),
        );

        // Scroll to bottom
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
        await tester.pumpAndSettle();

        expect(find.text('11. Contact'), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('has back button in app bar', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen.privacyPolicy(),
                    ),
                  ),
                  child: const Text('Go'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();

        expect(find.byType(BackButton), findsOneWidget);
      });
    });

    group('LegalDocumentType enum', () {
      testWidgets('can create with privacyPolicy type', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen(documentType: LegalDocumentType.privacyPolicy),
          ),
        );

        expect(find.text('Privacy Policy'), findsAtLeastNWidgets(1));
      });

      testWidgets('can create with termsOfService type', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: LegalDocumentScreen(documentType: LegalDocumentType.termsOfService),
          ),
        );

        expect(find.text('Terms of Service'), findsAtLeastNWidgets(1));
      });
    });
  });
}
