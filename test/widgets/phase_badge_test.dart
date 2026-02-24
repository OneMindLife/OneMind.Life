import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/round.dart';
import 'package:onemind_app/widgets/phase_badge.dart';

void main() {
  Widget buildBadge({RoundPhase? phase, bool isPaused = false}) {
    return MaterialApp(
      home: Scaffold(
        body: PhaseBadge(phase: phase, isPaused: isPaused),
      ),
    );
  }

  group('PhaseBadge', () {
    testWidgets('shows "Proposing" for proposing phase', (tester) async {
      await tester.pumpWidget(buildBadge(phase: RoundPhase.proposing));
      expect(find.text('Proposing'), findsOneWidget);
    });

    testWidgets('shows "Rating" for rating phase', (tester) async {
      await tester.pumpWidget(buildBadge(phase: RoundPhase.rating));
      expect(find.text('Rating'), findsOneWidget);
    });

    testWidgets('shows "Waiting" for waiting phase', (tester) async {
      await tester.pumpWidget(buildBadge(phase: RoundPhase.waiting));
      expect(find.text('Waiting'), findsOneWidget);
    });

    testWidgets('shows "Idle" when phase is null', (tester) async {
      await tester.pumpWidget(buildBadge(phase: null));
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('shows "Paused" when isPaused is true regardless of phase',
        (tester) async {
      await tester.pumpWidget(
          buildBadge(phase: RoundPhase.proposing, isPaused: true));
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Proposing'), findsNothing);
    });

    testWidgets('shows "Paused" when isPaused and phase is null',
        (tester) async {
      await tester.pumpWidget(buildBadge(phase: null, isPaused: true));
      expect(find.text('Paused'), findsOneWidget);
    });
  });
}
