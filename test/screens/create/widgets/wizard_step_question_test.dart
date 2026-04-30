import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/widgets/wizard_step_question.dart';

void main() {
  group('WizardStepQuestion', () {
    Future<void> pumpStep(
      WidgetTester tester, {
      required TextEditingController nameController,
      required TextEditingController messageController,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: WizardStepQuestion(
              nameController: nameController,
              messageController: messageController,
              formKey: GlobalKey<FormState>(),
              onContinue: () {},
            ),
          ),
        ),
      );
    }

    testWidgets(
      'initial-message toggle defaults to ON and reveals the message field',
      (tester) async {
        final nameController = TextEditingController();
        final messageController = TextEditingController();

        await pumpStep(
          tester,
          nameController: nameController,
          messageController: messageController,
        );

        final toggleFinder = find.widgetWithText(SwitchListTile, 'Set initial message');
        expect(toggleFinder, findsOneWidget);
        expect(
          tester.widget<SwitchListTile>(toggleFinder).value,
          isTrue,
          reason: 'Default-on nudges hosts to frame a question.',
        );

        // The message TextFormField is rendered when the toggle is on.
        expect(find.text('Initial Message'), findsOneWidget);

        nameController.dispose();
        messageController.dispose();
      },
    );

    testWidgets(
      'toggling off hides the message field and clears the controller',
      (tester) async {
        final nameController = TextEditingController();
        final messageController = TextEditingController(text: 'Existing question?');

        await pumpStep(
          tester,
          nameController: nameController,
          messageController: messageController,
        );

        // Sanity: starts on, field present, text preserved.
        expect(find.text('Initial Message'), findsOneWidget);
        expect(messageController.text, 'Existing question?');

        // Tap the switch off.
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(find.text('Initial Message'), findsNothing);
        expect(
          messageController.text,
          isEmpty,
          reason: 'Toggling off should also clear stale draft text.',
        );

        nameController.dispose();
        messageController.dispose();
      },
    );

    testWidgets(
      're-toggling on after off shows the field again with an empty controller',
      (tester) async {
        final nameController = TextEditingController();
        final messageController = TextEditingController();

        await pumpStep(
          tester,
          nameController: nameController,
          messageController: messageController,
        );

        // Off, then back on.
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(find.text('Initial Message'), findsNothing);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(find.text('Initial Message'), findsOneWidget);
        expect(messageController.text, isEmpty);

        nameController.dispose();
        messageController.dispose();
      },
    );
  });
}
