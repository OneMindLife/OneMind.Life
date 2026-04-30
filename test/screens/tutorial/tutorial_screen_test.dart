import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';


import '../../helpers/pump_app.dart';

/// Helper to navigate from intro to proposing via the notifier.
/// The Flutter intro panel was removed (web/index.html handles the play UI);
/// in tests we just drive the state machine directly.
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
  group('TutorialScreen', () {
    testWidgets('shows app bar with tutorial title during chat tour', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // App bar visible with title
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('OneMind Tutorial'), findsOneWidget);

      await _navigateToProposing(tester);

      // App bar still visible after navigating into the chat tour
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('navigates to round 1 proposing',
        (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      await _navigateToProposing(tester);

      // Should be in proposing state with text field
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('navigates to rating state after submitting proposition',
        (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Go to proposing
      await _navigateToProposing(tester);

      // Submit a proposition
      await tester.enterText(find.byType(TextField), 'Bowling');
      await tester.pumpAndSettle();

      // Find and tap submit button
      final submitFinder = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      // Should show rating state with "Start Rating" button
      expect(find.text('Start Rating'), findsOneWidget);
    });

    testWidgets('navigates to proposing state', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to proposing
      await _navigateToProposing(tester);

      // Should be in proposing state with text field
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('displays saturday initial message in chat history', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to proposing (saturday template)
      await _navigateToProposing(tester);

      // Initial message should display the saturday template question
      expect(
        find.textContaining('best way to spend a free Saturday'),
        findsWidgets,
      );
    });

    group('Tutorial panel widgets', () {
      testWidgets('proposing state shows text field', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        await _navigateToProposing(tester);

        expect(find.byType(TextField), findsOneWidget);
      });
    });

    group('State transitions', () {
      testWidgets('proposing to rating transition', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Go to proposing
        await _navigateToProposing(tester);

        // Submit
        await tester.enterText(find.byType(TextField), 'Test');
        await tester.pumpAndSettle();

        final submitFinder = find.byIcon(Icons.send_rounded);
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should show rating state with "Start Rating" button
        expect(find.text('Start Rating'), findsOneWidget);
      });
    });

    group('Localization', () {
      testWidgets('displays saturday initial message', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing (saturday template)
        await _navigateToProposing(tester);

        // Initial message should display the saturday question
        expect(find.textContaining('best way to spend a free Saturday'), findsWidgets);
      });
    });

    group('Share demo', () {
      testWidgets('participants icon visible but share icon hidden during proposing', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Participants icon visible, share icon not yet revealed
        expect(find.byIcon(Icons.leaderboard), findsOneWidget);
        expect(find.byKey(const Key('tutorial-share-button')), findsNothing);
      });

      testWidgets('close button shows skip confirmation', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Tap the exit button in AppBar
        await tester.tap(find.byIcon(Icons.exit_to_app));
        await tester.pumpAndSettle();

        // Skip confirmation dialog should appear
        expect(find.text('Skip Tutorial?'), findsOneWidget);
      });
    });

    group('Streamlined round 1 result flow', () {
      testWidgets('round1Result shows continue button directly (no seeResults gate)',
          (tester) async {
        await tester.pumpApp(
          TutorialScreen(onComplete: () {}),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Submit proposition
        await tester.enterText(find.byType(TextField), 'My Idea');
        await tester.pumpAndSettle();
        final submitFinder = find.byIcon(Icons.send_rounded);
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should show rating state with "Start Rating" button
        expect(find.text('Start Rating'), findsOneWidget);
      });

      testWidgets('notifier transitions directly from round1Result to round2Prompt',
          (tester) async {
        await tester.pumpApp(
          TutorialScreen(onComplete: () {}),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Get the container to manipulate state directly
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TutorialScreen)),
        );
        final notifier = container.read(tutorialChatNotifierProvider.notifier);

        // Fast-forward to round1Result
        notifier.submitRound1Proposition('My Idea');
        notifier.completeRound1Rating();
        await tester.pumpAndSettle();

        expect(
          container.read(tutorialChatNotifierProvider).currentStep,
          TutorialStep.round1Result,
        );

        // Call continueToRound2 directly (simulates Continue button)
        notifier.continueToRound2();
        await tester.pumpAndSettle();

        expect(
          container.read(tutorialChatNotifierProvider).currentStep,
          TutorialStep.round2Prompt,
        );
      });

      testWidgets('state advances to round1Result after completing rating',
          (tester) async {
        await tester.pumpApp(
          TutorialScreen(onComplete: () {}),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Get the container to manipulate state directly
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TutorialScreen)),
        );
        final notifier = container.read(tutorialChatNotifierProvider.notifier);

        // Submit and complete R1 rating
        notifier.submitRound1Proposition('My Idea');
        notifier.completeRound1Rating();
        await tester.pumpAndSettle();

        // State should be at round1Result (results screen is opened by
        // _pushResultsReplacement from rating onComplete, not by ref.listen)
        final state = container.read(tutorialChatNotifierProvider);
        expect(state.currentStep, TutorialStep.round1Result);
        expect(state.previousRoundWinners, isNotEmpty);
      });
    });

    group('Duplicate detection', () {
      testWidgets('shows orange snackbar when submitting duplicate proposition',
          (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Go to proposing (saturday template)
        await _navigateToProposing(tester);

        // Try to submit "Movie Night" (which exists in saturday round 1)
        await tester.enterText(find.byType(TextField), 'Movie Night');
        await tester.pumpAndSettle();

        final submitFinder = find.byIcon(Icons.send_rounded);
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should show snackbar with duplicate message
        expect(
          find.text('This idea already exists in this round. Try something different!'),
          findsOneWidget,
        );

        // Should still be on proposing state (not moved to rating)
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('duplicate detection is case insensitive', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Go to proposing (saturday template)
        await _navigateToProposing(tester);

        // Try to submit "movie night" (lowercase - should match "Movie Night")
        await tester.enterText(find.byType(TextField), 'movie night');
        await tester.pumpAndSettle();

        final submitFinder = find.byIcon(Icons.send_rounded);
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should show snackbar with duplicate message
        expect(
          find.text('This idea already exists in this round. Try something different!'),
          findsOneWidget,
        );
      });

      testWidgets('allows unique proposition submission', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Go to proposing (saturday template)
        await _navigateToProposing(tester);

        // Submit a unique proposition
        await tester.enterText(find.byType(TextField), 'Bowling');
        await tester.pumpAndSettle();

        final submitFinder = find.byIcon(Icons.send_rounded);
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should not show snackbar
        expect(
          find.text('This idea already exists in this round. Try something different!'),
          findsNothing,
        );

        // Should show rating state with "Start Rating" button
        expect(find.text('Start Rating'), findsOneWidget);
      });
    });
  });
}
