import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/wizard_step_convergence.dart';

void main() {
  Widget buildWidget({
    required ConsensusSettings settings,
    required void Function(ConsensusSettings) onChanged,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: WizardStepConvergence(
          consensusSettings: settings,
          onConsensusSettingsChanged: onChanged,
          ratingMode: 'grid',
          onRatingModeChanged: (_) {},
          matchObjective: 'winner_only',
          onMatchObjectiveChanged: (_) {},
          onContinue: () {},
        ),
      ),
    );
  }

  // Selected cards (and only they) show a check_circle icon.
  bool isChecked(WidgetTester tester, String cardText) {
    final check = find.descendant(
      of: find.ancestor(of: find.text(cardText), matching: find.byType(Card)),
      matching: find.byIcon(Icons.check_circle),
    );
    return tester.any(check);
  }

  const instantDesc = 'The first winner is added immediately';
  const convergenceDesc = 'Same proposition must win 2 rounds in a row';

  group('WizardStepConvergence', () {
    testWidgets('shows both modes and the continue button', (tester) async {
      await tester.pumpWidget(
        buildWidget(settings: ConsensusSettings.defaults(), onChanged: (_) {}),
      );

      expect(find.text('Instant'), findsOneWidget);
      expect(find.text(instantDesc), findsOneWidget);
      expect(find.text(convergenceDesc), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('defaults (2) select Convergence, not Instant', (tester) async {
      await tester.pumpWidget(
        buildWidget(settings: ConsensusSettings.defaults(), onChanged: (_) {}),
      );

      expect(isChecked(tester, instantDesc), isFalse);
      expect(isChecked(tester, convergenceDesc), isTrue);
    });

    testWidgets('confirmationRoundsRequired == 1 selects Instant',
        (tester) async {
      await tester.pumpWidget(
        buildWidget(
          settings: ConsensusSettings.defaults()
              .copyWith(confirmationRoundsRequired: 1),
          onChanged: (_) {},
        ),
      );

      expect(isChecked(tester, instantDesc), isTrue);
      expect(isChecked(tester, convergenceDesc), isFalse);
    });

    testWidgets('tapping Instant emits confirmationRoundsRequired = 1',
        (tester) async {
      ConsensusSettings? captured;
      await tester.pumpWidget(
        buildWidget(
          settings: ConsensusSettings.defaults(),
          onChanged: (s) => captured = s,
        ),
      );

      await tester.tap(find.text(instantDesc));
      expect(captured?.confirmationRoundsRequired, 1);
    });

    testWidgets('tapping Convergence emits confirmationRoundsRequired = 2',
        (tester) async {
      ConsensusSettings? captured;
      await tester.pumpWidget(
        buildWidget(
          settings: ConsensusSettings.defaults()
              .copyWith(confirmationRoundsRequired: 1),
          onChanged: (s) => captured = s,
        ),
      );

      await tester.tap(find.text(convergenceDesc));
      expect(captured?.confirmationRoundsRequired, 2);
    });
  });
}
