import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/round.dart';
import 'package:onemind_app/widgets/phase_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('PhaseBadge', () {
    testWidgets('shows "Proposing" for proposing phase', (tester) async {
      await tester.pumpWidget(wrap(
        const PhaseBadge(phase: RoundPhase.proposing),
      ));
      expect(find.text('Proposing'), findsOneWidget);
    });

    testWidgets('shows "Rating" for rating phase', (tester) async {
      await tester.pumpWidget(wrap(
        const PhaseBadge(phase: RoundPhase.rating),
      ));
      expect(find.text('Rating'), findsOneWidget);
    });

    testWidgets('shows "Waiting" for waiting phase', (tester) async {
      await tester.pumpWidget(wrap(
        const PhaseBadge(phase: RoundPhase.waiting),
      ));
      expect(find.text('Waiting'), findsOneWidget);
    });

    testWidgets('shows "Idle" when phase is null', (tester) async {
      await tester.pumpWidget(wrap(
        const PhaseBadge(phase: null),
      ));
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('shows "Paused" when isPaused is true regardless of phase', (tester) async {
      await tester.pumpWidget(wrap(
        const PhaseBadge(phase: RoundPhase.proposing, isPaused: true),
      ));
      expect(find.text('Paused'), findsOneWidget);
    });
  });
}
