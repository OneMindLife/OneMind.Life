import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/widgets/welcome_header.dart';

import '../helpers/pump_app.dart';
import '../mocks/mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
    mockAuthService.setupDefaults(displayName: 'Brave Fox');
  });

  group('WelcomeHeader', () {
    testWidgets('displays greeting with display name', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Brave Fox'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Brave Fox'), findsOneWidget);
    });

    testWidgets('displays edit icon button', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Brave Fox'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('edit button opens dialog with current name', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Brave Fox'),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      // Dialog should appear with TextField pre-filled
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // TextField should contain the current name
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Brave Fox');
    });

    testWidgets('edit dialog has Cancel and Save buttons', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Brave Fox'),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog without saving', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Brave Fox'),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('handles empty display name gracefully', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue(null),
        ],
      );
      await tester.pumpAndSettle();

      // Should still render without crashing
      expect(find.byType(WelcomeHeader), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('readOnly hides edit button', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(readOnly: true),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Brave Fox'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Brave Fox'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('displayNameOverride bypasses provider', (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(displayNameOverride: 'Custom Name'),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Provider Name'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Custom Name'), findsOneWidget);
      expect(find.textContaining('Provider Name'), findsNothing);
    });

    testWidgets('displayNameOverride with readOnly renders tour mode',
        (tester) async {
      await tester.pumpApp(
        const WelcomeHeader(
          displayNameOverride: 'Brave Fox',
          readOnly: true,
        ),
        authService: mockAuthService,
        additionalOverrides: [
          authDisplayNameProvider.overrideWithValue('Real Name'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Brave Fox'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
    });
  });
}
