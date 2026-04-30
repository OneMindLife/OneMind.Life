import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/notifiers/tutorial_notifier.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';

import '../../helpers/pump_app.dart';

/// Navigate to round 1 proposing via notifier (Flutter intro panel was
/// removed; web/index.html handles the play UI in production).
Future<void> _navigateToProposing(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TutorialScreen)),
  );
  container
      .read(tutorialChatNotifierProvider.notifier)
      .selectTemplate('saturday');
  await tester.pumpAndSettle();
  container.read(tutorialChatNotifierProvider.notifier).skipChatTour();
  await tester.pumpAndSettle();
}

void main() {
  group('Round 1 proposing (widget)', () {
    testWidgets('text field is visible at round1Proposing', (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('submit button works with valid text', (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      await tester.enterText(find.byType(TextField), 'Bowling');
      await tester.pumpAndSettle();

      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      final state = container.read(tutorialChatNotifierProvider);
      expect(state.currentStep, TutorialStep.round1Rating);
      expect(state.userProposition1, 'Bowling');
    });

    testWidgets('submitting advances to round1Rating with Start Rating',
        (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      await tester.enterText(find.byType(TextField), 'Hiking');
      await tester.pumpAndSettle();

      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(find.text('Start Rating'), findsOneWidget);
    });

    testWidgets('duplicate detection blocks submission (exact match)',
        (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      await tester.enterText(find.byType(TextField), 'Movie Night');
      await tester.pumpAndSettle();

      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(
        find.text(
            'This idea already exists in this round. Try something different!'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('duplicate detection is case insensitive', (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      await tester.enterText(find.byType(TextField), 'movie night');
      await tester.pumpAndSettle();

      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(
        find.text(
            'This idea already exists in this round. Try something different!'),
        findsOneWidget,
      );
    });

    testWidgets('empty text does not submit', (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      expect(container.read(tutorialChatNotifierProvider).currentStep,
          TutorialStep.round1Proposing);
    });

    testWidgets('displays initial message from saturday template',
        (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      expect(
        find.textContaining('best way to spend a free Saturday'),
        findsWidgets,
      );
    });

    testWidgets('full R1 proposing → R1 rating → R1 result flow via UI',
        (tester) async {
      await tester.pumpApp(TutorialScreen(onComplete: () {}));
      await tester.pumpAndSettle();
      await _navigateToProposing(tester);

      // Submit R1
      await tester.enterText(find.byType(TextField), 'Bowling');
      await tester.pumpAndSettle();
      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );

      // Verify transition to rating
      expect(container.read(tutorialChatNotifierProvider).currentStep,
          TutorialStep.round1Rating);
      expect(find.text('Start Rating'), findsOneWidget);

      // Complete rating via notifier
      container.read(tutorialChatNotifierProvider.notifier).completeRound1Rating();
      await tester.pumpAndSettle();

      expect(container.read(tutorialChatNotifierProvider).currentStep,
          TutorialStep.round1Result);
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

  // Pure notifier tests for round 2 and 3 (avoids widget animation issues)
  group('Round 2 proposing (notifier)', () {
    late TutorialChatNotifier notifier;

    setUp(() {
      notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea 1');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
    });

    test('starts at round2Prompt', () {
      expect(notifier.state.currentStep, TutorialStep.round2Prompt);
    });

    test('submitRound2Proposition saves content and advances to rating', () {
      notifier.submitRound2Proposition('Idea 2');

      expect(notifier.state.currentStep, TutorialStep.round2Rating);
      expect(notifier.state.userProposition2, 'Idea 2');
    });

    test('round2 propositions include carried forward prop', () {
      notifier.submitRound2Proposition('Idea 2');

      final carried = notifier.state.propositions
          .where((p) => p.carriedFromId != null)
          .toList();
      expect(carried.length, 1);
      expect(carried.first.content, 'Movie Night');
    });

    test('submitRound2Proposition resets hasStartedRating', () {
      notifier.markRatingStarted();
      expect(notifier.state.hasStartedRating, true);

      notifier.submitRound2Proposition('Idea 2');
      expect(notifier.state.hasStartedRating, false);
    });

    test('completeRound2Rating sets user as winner', () {
      notifier.submitRound2Proposition('Idea 2');
      notifier.completeRound2Rating();

      expect(notifier.state.currentStep, TutorialStep.round2Result);
      expect(notifier.state.previousRoundWinners.first.content, 'Idea 2');
      expect(notifier.state.consecutiveSoleWins, 1);
    });
  });

  group('Round 3 proposing (notifier)', () {
    late TutorialChatNotifier notifier;

    setUp(() {
      notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea 1');
      notifier.completeRound1Rating();
      notifier.continueToRound2();
      notifier.submitRound2Proposition('Idea 2');
      notifier.completeRound2Rating();
      notifier.continueToRound3();
    });

    test('continueToRound3 goes to round3Proposing', () {
      expect(notifier.state.currentStep, TutorialStep.round3Proposing);
    });

    test('submitRound3Proposition saves content and advances to rating', () {
      notifier.submitRound3Proposition('Final Idea');

      expect(notifier.state.currentStep, TutorialStep.round3Rating);
      expect(notifier.state.userProposition3, 'Final Idea');
    });

    test('round3 propositions include carried forward and new', () {
      notifier.submitRound3Proposition('Final Idea');

      final props = notifier.state.propositions;
      // carried R2 winner + new user idea + 3 NPC props = 5
      expect(props.length, 5);

      final carried = props.where((p) => p.carriedFromId != null).toList();
      expect(carried.length, 1);
      expect(carried.first.content, 'Idea 2');

      final userProps = props.where((p) => p.participantId == -1).toList();
      expect(userProps.length, 2);
    });

    test('beginRound3Rating skips proposing (for skip button)', () {
      notifier.beginRound3Rating();

      expect(notifier.state.currentStep, TutorialStep.round3Rating);
      expect(notifier.state.userProposition3, isNull);
    });

    test('beginRound3Rating creates carried forward proposition', () {
      notifier.beginRound3Rating();

      final carried = notifier.state.propositions
          .where((p) => p.carriedFromId != null)
          .toList();
      expect(carried.length, 1);
      expect(carried.first.content, 'Idea 2');
    });

    test('submitRound3Proposition resets hasStartedRating', () {
      notifier.markRatingStarted();
      expect(notifier.state.hasStartedRating, true);

      notifier.submitRound3Proposition('Final');
      expect(notifier.state.hasStartedRating, false);
    });

    test('completeRound3Rating creates consensus', () {
      notifier.submitRound3Proposition('Final');
      notifier.completeRound3Rating();

      expect(notifier.state.currentStep, TutorialStep.round3Consensus);
      expect(notifier.state.consecutiveSoleWins, 2);
      expect(notifier.state.consensusItems, isNotEmpty);
      expect(notifier.state.consensusItems.first.content, 'Idea 2');
    });

    test('round3 results include user R3 proposition when submitted', () {
      notifier.submitRound3Proposition('Final Idea');
      notifier.completeRound3Rating();

      final results = notifier.state.round3Results;
      expect(results.length, 5);
      expect(results.any((p) => p.content == 'Final Idea'), true);
    });

    test('round3 results exclude user R3 proposition when skipped', () {
      notifier.beginRound3Rating();
      notifier.completeRound3Rating();

      final results = notifier.state.round3Results;
      expect(results.length, 4);
    });
  });
}
