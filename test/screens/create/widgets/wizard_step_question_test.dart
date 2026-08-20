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
      'initial-message toggle defaults to OFF and hides the message field',
      (tester) async {
        final nameController = TextEditingController();
        final messageController = TextEditingController();

        await pumpStep(
          tester,
          nameController: nameController,
          messageController: messageController,
        );

        final toggleFinder =
            find.widgetWithText(SwitchListTile, 'Set initial message');
        expect(toggleFinder, findsOneWidget);
        expect(
          tester.widget<SwitchListTile>(toggleFinder).value,
          isFalse,
          reason:
              'An ongoing group chat is a standing space, not a single poll — '
              'it should not open with a fixed question by default.',
        );

        // With the toggle off, the message field is not rendered.
        expect(find.text('Initial Message'), findsNothing);

        nameController.dispose();
        messageController.dispose();
      },
    );

    testWidgets(
      'toggling on reveals the message field',
      (tester) async {
        final nameController = TextEditingController();
        final messageController = TextEditingController();

        await pumpStep(
          tester,
          nameController: nameController,
          messageController: messageController,
        );

        // Default off -> field hidden.
        expect(find.text('Initial Message'), findsNothing);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(find.text('Initial Message'), findsOneWidget);

        nameController.dispose();
        messageController.dispose();
      },
    );

    testWidgets(
      'toggling on then off hides the field and clears the draft',
      (tester) async {
        final nameController = TextEditingController();
        final messageController = TextEditingController();

        await pumpStep(
          tester,
          nameController: nameController,
          messageController: messageController,
        );

        // On.
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(find.text('Initial Message'), findsOneWidget);

        // Put a draft in, then toggle off.
        messageController.text = 'Existing question?';
        await tester.pump();
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(find.text('Initial Message'), findsNothing);
        expect(
          messageController.text,
          isEmpty,
          reason: 'Toggling off should clear stale draft text.',
        );

        nameController.dispose();
        messageController.dispose();
      },
    );
  });
}
