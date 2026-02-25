import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';
import 'package:onemind_app/screens/tutorial/widgets/tutorial_progress_dots.dart';

import '../../helpers/pump_app.dart';

/// Helper to navigate from intro to proposing by tapping a template card
/// then skipping the chat tour
Future<void> _navigateToProposing(WidgetTester tester) async {
  // Select Community Decision template directly from intro
  await tester.ensureVisible(find.text('Community Decision'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Community Decision'));
  await tester.pumpAndSettle();

  // Skip the chat tour to get to proposing
  final skipTourFinder = find.text('Skip tour');
  if (skipTourFinder.evaluate().isNotEmpty) {
    await tester.tap(skipTourFinder);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('TutorialScreen', () {
    testWidgets('displays intro panel with template cards on start', (tester) async {
      var completed = false;

      await tester.pumpApp(
        TutorialScreen(
          onComplete: () => completed = true,
        ),
      );

      // Wait for post-frame callback to start tutorial
      await tester.pumpAndSettle();

      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Personal Decision'), findsOneWidget);
      expect(find.text('Community Decision'), findsOneWidget);
    });

    testWidgets('shows app bar with tutorial title on intro and after template pick', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // App bar visible on intro with title
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('OneMind Tutorial'), findsOneWidget);

      // Select a template
      await tester.ensureVisible(find.text('Community Decision'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community Decision'));
      await tester.pumpAndSettle();

      // App bar still visible with 3-dot menu after template pick
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('navigates to round 1 proposing after selecting template',
        (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      await _navigateToProposing(tester);

      // New UI shows progress dots and uses ProposingStatePanel
      expect(find.byType(TutorialProgressDots), findsOneWidget);
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
      await tester.enterText(find.byType(TextField), 'Family');
      await tester.pumpAndSettle();

      // Find and tap submit button
      final submitFinder = find.widgetWithText(FilledButton, 'Submit');
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      // Should show rating state with "Start Rating" button
      expect(find.text('Start Rating'), findsOneWidget);
    });

    testWidgets('skip button shows confirmation dialog', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Skip button in intro panel
      await tester.ensureVisible(find.text('Skip tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip tutorial'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Skip Tutorial?'), findsOneWidget);
      expect(find.text('Yes, Skip'), findsOneWidget);
      expect(find.text('Continue Tutorial'), findsOneWidget);
    });

    testWidgets('skip confirmation completes tutorial when confirmed', (tester) async {
      var completed = false;

      await tester.pumpApp(
        TutorialScreen(
          onComplete: () => completed = true,
        ),
      );
      await tester.pumpAndSettle();

      // Skip button in intro panel
      await tester.ensureVisible(find.text('Skip tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip tutorial'));
      await tester.pumpAndSettle();

      // Confirm skip
      await tester.tap(find.text('Yes, Skip'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('skip confirmation does not complete tutorial when cancelled', (tester) async {
      var completed = false;

      await tester.pumpApp(
        TutorialScreen(
          onComplete: () => completed = true,
        ),
      );
      await tester.pumpAndSettle();

      // Skip button in intro panel
      await tester.ensureVisible(find.text('Skip tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip tutorial'));
      await tester.pumpAndSettle();

      // Cancel skip
      await tester.tap(find.text('Continue Tutorial'));
      await tester.pumpAndSettle();

      // Should still be on intro, not completed
      expect(completed, isFalse);
      expect(find.text('Welcome!'), findsOneWidget);
    });


    testWidgets('displays progress dots after selecting template', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // No progress dots on intro
      expect(find.byType(TutorialProgressDots), findsNothing);

      // Navigate to proposing
      await _navigateToProposing(tester);

      // Should see progress dots now
      expect(find.byType(TutorialProgressDots), findsOneWidget);
    });

    testWidgets('displays template-specific initial message in chat history', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to proposing (community template)
      await _navigateToProposing(tester);

      // Initial message should display the community template question
      expect(
        find.textContaining('What should our neighborhood do together?'),
        findsWidgets,
      );
    });

    group('Tutorial panel widgets', () {
      testWidgets('intro panel has template cards and skip button', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Personal Decision'), findsOneWidget);
        expect(find.text('Skip tutorial'), findsOneWidget);
      });

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

        final submitFinder = find.widgetWithText(FilledButton, 'Submit');
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should show rating state with "Start Rating" button
        expect(find.text('Start Rating'), findsOneWidget);
      });
    });

    group('Localization', () {
      testWidgets('displays localized welcome text', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // These strings come from l10n, not hardcoded
        expect(find.text('Welcome!'), findsOneWidget);
        expect(find.text('Pick a practice scenario'), findsOneWidget);
      });

      testWidgets('displays template cards', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Personal Decision'), findsOneWidget);
        expect(find.text('Family'), findsOneWidget);
        expect(find.text('Community Decision'), findsOneWidget);
      });

      testWidgets('displays localized button labels', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Skip tutorial'), findsOneWidget);
      });

      testWidgets('displays template-specific initial message after selecting template', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing (community template)
        await _navigateToProposing(tester);

        // Initial message should display the community question
        expect(find.textContaining('What should our neighborhood do together?'), findsWidgets);
      });
    });

    group('Share demo', () {
      testWidgets('share and participants icons visible in AppBar during tutorial', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Share and participants icons should be visible in AppBar
        expect(find.byKey(const Key('tutorial-share-button')), findsOneWidget);
        expect(find.byIcon(Icons.people_outline), findsOneWidget);
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

        // Tap the close button in AppBar
        await tester.tap(find.byIcon(Icons.close));
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
        final submitFinder = find.widgetWithText(FilledButton, 'Submit');
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

      testWidgets('auto-opens results screen after completing round 1 rating',
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

        // The ReadOnlyResultsScreen should have auto-opened via ref.listen
        // It shows "Round 1 Results" in the app bar
        expect(find.text('Round 1 Results'), findsOneWidget);
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

        // Go to proposing (community template)
        await _navigateToProposing(tester);

        // Try to submit "Block Party" (which exists in community round 1)
        await tester.enterText(find.byType(TextField), 'Block Party');
        await tester.pumpAndSettle();

        final submitFinder = find.widgetWithText(FilledButton, 'Submit');
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

        // Go to proposing (community template)
        await _navigateToProposing(tester);

        // Try to submit "block party" (lowercase - should match "Block Party")
        await tester.enterText(find.byType(TextField), 'block party');
        await tester.pumpAndSettle();

        final submitFinder = find.widgetWithText(FilledButton, 'Submit');
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

        // Go to proposing (community template)
        await _navigateToProposing(tester);

        // Submit a unique proposition
        await tester.enterText(find.byType(TextField), 'Education');
        await tester.pumpAndSettle();

        final submitFinder = find.widgetWithText(FilledButton, 'Submit');
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
