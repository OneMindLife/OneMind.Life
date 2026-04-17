import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/widgets/round_phase_bar.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );
  }

  group('RoundPhaseBar participation bar', () {
    testWidgets('shows participation bar when percent is non-null',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 50,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('hides participation bar when percent is null',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: null,
        ),
      ));
      await tester.pumpAndSettle();

      // No percentage text should be found
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('shows 0% when percent is 0', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 0,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('shows 100% when percent is 100', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 100,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('clamps percent to 0-100 range', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 150,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('animateProgress uses TweenAnimationBuilder', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 75,
          animateProgress: true,
        ),
      ));

      // Initially animated from 0
      expect(find.text('0%'), findsOneWidget);

      // After animation completes
      await tester.pumpAndSettle();
      expect(find.text('75%'), findsOneWidget);
    });
  });

  group('RoundPhaseBar progressOpacity', () {
    testWidgets('progressOpacity defaults to phasesOpacity', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 50,
          phasesOpacity: 0.5,
        ),
      ));
      await tester.pumpAndSettle();

      // The progress bar section uses AnimatedOpacity with progressOpacity ?? phasesOpacity.
      // Find AnimatedOpacity widgets wrapping the progress bar.
      final animatedOpacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .toList();

      // There should be an AnimatedOpacity with opacity 0.5 for the progress bar
      // (matching phasesOpacity since progressOpacity is null)
      expect(
        animatedOpacities.any((w) => (w.opacity - 0.5).abs() < 0.01),
        isTrue,
        reason: 'Progress bar should use phasesOpacity when progressOpacity is null',
      );
    });

    testWidgets('progressOpacity overrides phasesOpacity for progress bar',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 50,
          phasesOpacity: 0.5,
          progressOpacity: 0.8,
        ),
      ));
      await tester.pumpAndSettle();

      final animatedOpacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .toList();

      // Should have an AnimatedOpacity with 0.8 for the progress bar
      expect(
        animatedOpacities.any((w) => (w.opacity - 0.8).abs() < 0.01),
        isTrue,
        reason: 'Progress bar should use progressOpacity when provided',
      );
    });

    testWidgets('progressOpacity 0.0 hides progress bar', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: 50,
          progressOpacity: 0.0,
        ),
      ));
      await tester.pumpAndSettle();

      final animatedOpacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .toList();

      // Should have an AnimatedOpacity with 0.0 for the progress bar
      expect(
        animatedOpacities.any((w) => w.opacity == 0.0),
        isTrue,
        reason: 'Progress bar should be hidden when progressOpacity is 0.0',
      );
    });
  });

  group('RoundPhaseBar phase display', () {
    testWidgets('shows only active phase by default (showInactivePhase=false)', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(roundNumber: 1),
      ));
      await tester.pumpAndSettle();

      // Only proposing shown (default isProposing=true, showInactivePhase=false)
      expect(find.text('Proposing'), findsOneWidget);
      expect(find.text('Rating'), findsNothing);
    });

    testWidgets('shows only rating when isProposing is false',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(roundNumber: 1, isProposing: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Proposing'), findsNothing);
      expect(find.text('Rating'), findsOneWidget);
    });

    testWidgets('shows both phases when showInactivePhase is true',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(roundNumber: 1, showInactivePhase: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Proposing'), findsOneWidget);
      expect(find.text('Rating'), findsOneWidget);
    });

    testWidgets('displays correct round number', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(roundNumber: 3),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('3'), findsOneWidget);
    });
  });

  group('RoundPhaseBar opacity controls', () {
    testWidgets('roundOpacity 0.0 hides dividers', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          roundOpacity: 0.0,
        ),
      ));
      await tester.pumpAndSettle();

      // When roundOpacity is 0, barVisible is false, so Dividers are not shown
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('roundOpacity > 0 shows dividers', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          roundOpacity: 1.0,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Divider), findsNWidgets(2));
    });

    testWidgets('all opacities default to 1.0', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(roundNumber: 1),
      ));
      await tester.pumpAndSettle();

      final animatedOpacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .toList();

      // All AnimatedOpacity widgets should have opacity 1.0
      for (final ao in animatedOpacities) {
        expect(ao.opacity, 1.0,
            reason: 'All opacities should default to 1.0');
      }
    });
  });

  group('RoundPhaseBar negative percent', () {
    testWidgets('clamps negative percent to 0', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const RoundPhaseBar(
          roundNumber: 1,
          participationPercent: -10,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('0%'), findsOneWidget);
    });
  });
}
