import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/wizard_step_auto_advance.dart';

void main() {
  Widget buildWidget({
    required AutoAdvanceSettings settings,
    required void Function(AutoAdvanceSettings) onChanged,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: WizardStepAutoAdvance(
          autoAdvanceSettings: settings,
          onAutoAdvanceSettingsChanged: onChanged,
          onContinue: () {},
        ),
      ),
    );
  }

  Finder switchIn(String cardTitle) => find.descendant(
        of: find.ancestor(
            of: find.text(cardTitle), matching: find.byType(Card)),
        matching: find.byType(Switch),
      );

  group('WizardStepAutoAdvance', () {
    testWidgets('shows one toggle per phase, both off by default',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        settings: AutoAdvanceSettings.defaults(),
        onChanged: (_) {},
      ));

      expect(find.text('End proposing early'), findsOneWidget);
      expect(find.text('End rating early'), findsOneWidget);
      expect(tester.widget<Switch>(switchIn('End proposing early')).value,
          isFalse);
      expect(
          tester.widget<Switch>(switchIn('End rating early')).value, isFalse);
      expect(find.text('Proposing always runs for its full time'),
          findsOneWidget);
      expect(
          find.text('Rating always runs for its full time'), findsOneWidget);
    });

    testWidgets('proposing toggle only flips the proposing flag',
        (tester) async {
      AutoAdvanceSettings? captured;
      await tester.pumpWidget(buildWidget(
        settings: AutoAdvanceSettings.defaults(),
        onChanged: (s) => captured = s,
      ));

      await tester.tap(switchIn('End proposing early'));
      expect(captured?.enableProposing, isTrue);
      expect(captured?.enableRating, isFalse);
    });

    testWidgets('rating toggle only flips the rating flag', (tester) async {
      AutoAdvanceSettings? captured;
      await tester.pumpWidget(buildWidget(
        settings: AutoAdvanceSettings.defaults(),
        onChanged: (s) => captured = s,
      ));

      await tester.tap(switchIn('End rating early'));
      expect(captured?.enableProposing, isFalse);
      expect(captured?.enableRating, isTrue);
    });

    testWidgets('enabled toggles show the ends-early descriptions',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        settings: AutoAdvanceSettings.defaults()
            .copyWith(enableProposing: true, enableRating: true),
        onChanged: (_) {},
      ));

      expect(
          find.text('Proposing ends as soon as everyone has submitted or '
              'skipped'),
          findsOneWidget);
      expect(find.text('Rating ends as soon as everyone has rated'),
          findsOneWidget);
    });
  });
}
