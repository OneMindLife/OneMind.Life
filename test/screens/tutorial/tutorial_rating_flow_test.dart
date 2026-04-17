import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/notifiers/tutorial_notifier.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('Rating flow state transitions (notifier)', () {
    late TutorialChatNotifier notifier;

    setUp(() {
      notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
    });

    group('Round 1 rating', () {
      setUp(() {
        notifier.submitRound1Proposition('My Idea');
      });

      test('submitRound1Proposition moves to round1Rating', () {
        expect(notifier.state.currentStep, TutorialStep.round1Rating);
      });

      test('round is set to rating phase', () {
        expect(notifier.state.currentRound?.phase, RoundPhase.rating);
        expect(notifier.state.currentRound?.customId, 1);
      });

      test('propositions are populated with NPC + user props', () {
        final props = notifier.state.propositions;
        expect(props.length, 4); // 3 NPC + 1 user
        expect(props.any((p) => p.content == 'My Idea'), true);
        expect(props.any((p) => p.content == 'Movie Night'), true);
      });

      test('myPropositions contains user submission', () {
        expect(notifier.state.myPropositions.length, 1);
        expect(notifier.state.myPropositions.first.content, 'My Idea');
      });

      test('markRatingStarted tracks UI state', () {
        expect(notifier.state.hasStartedRating, false);
        notifier.markRatingStarted();
        expect(notifier.state.hasStartedRating, true);
      });

      test('completeRound1Rating sets hasRated', () {
        notifier.completeRound1Rating();
        expect(notifier.state.hasRated, true);
      });

      test('completeRound1Rating populates round1Results', () {
        notifier.completeRound1Rating();
        expect(notifier.state.round1Results, isNotEmpty);
        expect(notifier.state.round1Results.length, 4);
      });
    });

    group('Round 2 rating', () {
      setUp(() {
        notifier.submitRound1Proposition('Idea 1');
        notifier.completeRound1Rating();
        notifier.continueToRound2();
        notifier.submitRound2Proposition('Idea 2');
      });

      test('submitRound2Proposition moves to round2Rating', () {
        expect(notifier.state.currentStep, TutorialStep.round2Rating);
      });

      test('round is set to rating phase', () {
        expect(notifier.state.currentRound?.phase, RoundPhase.rating);
        expect(notifier.state.currentRound?.customId, 2);
      });

      test('propositions include carried forward from R1', () {
        final carried = notifier.state.propositions
            .where((p) => p.carriedFromId != null)
            .toList();
        expect(carried.length, 1);
        expect(carried.first.content, 'Movie Night');
        expect(carried.first.carriedFromId, -100);
      });

      test('propositions include user R2 submission', () {
        expect(
          notifier.state.propositions.any((p) => p.content == 'Idea 2'),
          true,
        );
      });

      test('hasStartedRating is reset for R2', () {
        expect(notifier.state.hasStartedRating, false);
      });

      test('completeRound2Rating populates round2Results', () {
        notifier.completeRound2Rating();
        expect(notifier.state.round2Results, isNotEmpty);
        expect(notifier.state.round2Results.length, 5);
      });

      test('completeRound2Rating user wins', () {
        notifier.completeRound2Rating();
        expect(notifier.state.previousRoundWinners.first.content, 'Idea 2');
        expect(notifier.state.isUserWinner, true);
      });
    });

    group('Round 3 rating (with submission)', () {
      setUp(() {
        notifier.submitRound1Proposition('Idea 1');
        notifier.completeRound1Rating();
        notifier.continueToRound2();
        notifier.submitRound2Proposition('Idea 2');
        notifier.completeRound2Rating();
        notifier.continueToRound3();
        notifier.submitRound3Proposition('Idea 3');
      });

      test('moves to round3Rating', () {
        expect(notifier.state.currentStep, TutorialStep.round3Rating);
      });

      test('round is set to rating phase', () {
        expect(notifier.state.currentRound?.phase, RoundPhase.rating);
        expect(notifier.state.currentRound?.customId, 3);
      });

      test('propositions include carried R2 winner + new R3 + NPC', () {
        final props = notifier.state.propositions;
        expect(props.length, 5);

        // Carried R2 winner
        final carried = props.where((p) => p.carriedFromId != null).toList();
        expect(carried.length, 1);
        expect(carried.first.content, 'Idea 2');

        // User new R3
        expect(props.any((p) => p.content == 'Idea 3'), true);
      });

      test('myPropositions has both carried and new', () {
        expect(notifier.state.myPropositions.length, 2);
      });

      test('completeRound3Rating creates consensus', () {
        notifier.completeRound3Rating();

        expect(notifier.state.currentStep, TutorialStep.round3Consensus);
        expect(notifier.state.consecutiveSoleWins, 2);
        expect(notifier.state.consensusItems.first.content, 'Idea 2');
      });

      test('completeRound3Rating populates round3Results', () {
        notifier.completeRound3Rating();
        expect(notifier.state.round3Results.length, 5);
      });
    });

    group('Round 3 rating (skip — no submission)', () {
      setUp(() {
        notifier.submitRound1Proposition('Idea 1');
        notifier.completeRound1Rating();
        notifier.continueToRound2();
        notifier.submitRound2Proposition('Idea 2');
        notifier.completeRound2Rating();
        notifier.continueToRound3();
        notifier.beginRound3Rating(); // Skip proposing
      });

      test('moves to round3Rating', () {
        expect(notifier.state.currentStep, TutorialStep.round3Rating);
      });

      test('propositions include carried R2 winner + NPC only', () {
        final props = notifier.state.propositions;
        // carried + 3 NPC = 4
        expect(props.length, 4);

        final carried = props.where((p) => p.carriedFromId != null).toList();
        expect(carried.length, 1);
        expect(carried.first.content, 'Idea 2');
      });

      test('myPropositions has only carried forward', () {
        expect(notifier.state.myPropositions.length, 1);
        expect(notifier.state.myPropositions.first.carriedFromId, -51);
      });

      test('completeRound3Rating still creates consensus', () {
        notifier.completeRound3Rating();
        expect(notifier.state.currentStep, TutorialStep.round3Consensus);
        expect(notifier.state.consecutiveSoleWins, 2);
      });

      test('round3Results has 4 props (no user R3)', () {
        notifier.completeRound3Rating();
        expect(notifier.state.round3Results.length, 4);
      });
    });
  });

  group('Rating flow widget (R1 Start Rating button)', () {
    testWidgets('Start Rating button visible after submitting R1 proposition',
        (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();

      // Navigate to proposing
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      container.read(tutorialChatNotifierProvider.notifier).skipChatTour();
      await tester.pumpAndSettle();

      // Submit proposition
      await tester.enterText(find.byType(TextField), 'Bowling');
      await tester.pumpAndSettle();
      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      // Should show Start Rating button
      expect(find.text('Start Rating'), findsOneWidget);
      expect(
        container.read(tutorialChatNotifierProvider).currentStep,
        TutorialStep.round1Rating,
      );
    });

    testWidgets('completing rating via notifier advances to result',
        (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      final notifier = container.read(tutorialChatNotifierProvider.notifier);
      notifier.skipChatTour();
      await tester.pumpAndSettle();

      // Submit and complete R1
      notifier.submitRound1Proposition('Test');
      notifier.completeRound1Rating();
      await tester.pumpAndSettle();

      expect(
        container.read(tutorialChatNotifierProvider).currentStep,
        TutorialStep.round1Result,
      );
      expect(
        container
            .read(tutorialChatNotifierProvider)
            .previousRoundWinners
            .first
            .content,
        'Movie Night',
      );
    });
  });
}
