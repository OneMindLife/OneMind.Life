import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/notifiers/tutorial_notifier.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('Tutorial completion flow', () {
    testWidgets('skip from intro shows confirmation dialog', (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();

      final skipFinder = find.text('Skip');
      await tester.ensureVisible(skipFinder);
      await tester.pumpAndSettle();
      await tester.tap(skipFinder);
      await tester.pumpAndSettle();

      expect(find.text('Skip Tutorial?'), findsOneWidget);
      expect(find.text('Yes, Skip'), findsOneWidget);
      expect(find.text('Continue Tutorial'), findsOneWidget);
    });

    testWidgets('confirming skip calls onComplete', (tester) async {
      var completed = false;
      await tester.pumpApp(
        TutorialScreen(onComplete: () => completed = true),
      );
      await tester.pumpAndSettle();

      final skipFinder = find.text('Skip');
      await tester.ensureVisible(skipFinder);
      await tester.pumpAndSettle();
      await tester.tap(skipFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yes, Skip'));
      await tester.pumpAndSettle();

      expect(completed, true);
    });

    testWidgets('cancelling skip returns to current step', (tester) async {
      var completed = false;
      await tester.pumpApp(
        TutorialScreen(onComplete: () => completed = true),
      );
      await tester.pumpAndSettle();

      final skipFinder = find.text('Skip');
      await tester.ensureVisible(skipFinder);
      await tester.pumpAndSettle();
      await tester.tap(skipFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue Tutorial'));
      await tester.pumpAndSettle();

      expect(completed, false);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('exit button during proposing shows skip confirmation',
        (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();

      // Navigate to proposing
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();

      // Skip chat tour via notifier
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      container.read(tutorialChatNotifierProvider.notifier).skipChatTour();
      await tester.pumpAndSettle();

      // Tap exit button in AppBar
      await tester.tap(find.byIcon(Icons.exit_to_app));
      await tester.pumpAndSettle();

      expect(find.text('Skip Tutorial?'), findsOneWidget);
    });
  });

  // These tests use pure notifier logic (no widget) to avoid animation/navigation issues
  group('TutorialChatNotifier completion transitions', () {
    late TutorialChatNotifier notifier;

    setUp(() {
      notifier = TutorialChatNotifier();
    });

    void fastForwardToShareDemo() {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('My Idea');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
      notifier.submitRound2Proposition('Better Idea');
      notifier.completeRound2Rating();
      notifier.continueToRound3();
      notifier.submitRound3Proposition('Final');
      notifier.completeRound3Rating();
      notifier.continueToConvergenceContinue();
      notifier.continueToShareDemo();
    }

    test('completeTutorial sets step to complete', () {
      fastForwardToShareDemo();
      notifier.completeTutorial();
      expect(notifier.state.currentStep, TutorialStep.complete);
    });

    test('skipTutorial from round2 goes to complete', () {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');
      notifier.completeRound1Rating();
      notifier.continueToRound2();

      notifier.skipTutorial();
      expect(notifier.state.currentStep, TutorialStep.complete);
    });

    test('skipTutorial from round1Proposing goes to complete', () {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();

      notifier.skipTutorial();
      expect(notifier.state.currentStep, TutorialStep.complete);
    });

    test('continueToShareDemo transitions from convergenceContinue', () {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
      notifier.submitRound2Proposition('Better');
      notifier.completeRound2Rating();
      notifier.continueToRound3();
      notifier.submitRound3Proposition('Final');
      notifier.completeRound3Rating();
      notifier.continueToConvergenceContinue();

      expect(notifier.state.currentStep, TutorialStep.convergenceContinue);

      notifier.continueToShareDemo();
      expect(notifier.state.currentStep, TutorialStep.shareDemo);
    });

    test('convergenceContinue clears previousRoundWinners for new cycle', () {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
      notifier.submitRound2Proposition('Better');
      notifier.completeRound2Rating();
      notifier.continueToRound3();
      notifier.submitRound3Proposition('Final');
      notifier.completeRound3Rating();

      expect(notifier.state.previousRoundWinners, isNotEmpty);

      notifier.continueToConvergenceContinue();

      expect(notifier.state.previousRoundWinners, isEmpty);
      expect(notifier.state.consensusItems, isNotEmpty);
    });

    test('convergenceContinue sets round 4 proposing phase', () {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
      notifier.submitRound2Proposition('Better');
      notifier.completeRound2Rating();
      notifier.continueToRound3();
      notifier.submitRound3Proposition('Final');
      notifier.completeRound3Rating();
      notifier.continueToConvergenceContinue();

      expect(notifier.state.currentRound?.customId, 4);
      expect(notifier.state.currentRound?.phase, RoundPhase.proposing);
    });

    test('complete flow preserves all user propositions', () {
      fastForwardToShareDemo();
      notifier.completeTutorial();

      expect(notifier.state.currentStep, TutorialStep.complete);
      expect(notifier.state.userProposition1, 'My Idea');
      expect(notifier.state.userProposition2, 'Better Idea');
      expect(notifier.state.userProposition3, 'Final');
      expect(notifier.state.consensusItems, isNotEmpty);
    });

    test('nextStep from shareDemo completes tutorial', () {
      fastForwardToShareDemo();
      notifier.nextStep();
      expect(notifier.state.currentStep, TutorialStep.complete);
    });

    test('nextStep from convergenceContinue goes to shareDemo', () {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
      notifier.submitRound2Proposition('Better');
      notifier.completeRound2Rating();
      notifier.continueToRound3();
      notifier.submitRound3Proposition('Final');
      notifier.completeRound3Rating();
      notifier.continueToConvergenceContinue();

      notifier.nextStep();
      expect(notifier.state.currentStep, TutorialStep.shareDemo);
    });

    test('nextStep from round3Consensus goes to convergenceContinue', () {
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
      notifier.submitRound2Proposition('Better');
      notifier.completeRound2Rating();
      notifier.continueToRound3();
      notifier.submitRound3Proposition('Final');
      notifier.completeRound3Rating();

      notifier.nextStep();
      expect(notifier.state.currentStep, TutorialStep.convergenceContinue);
    });
  });
}
