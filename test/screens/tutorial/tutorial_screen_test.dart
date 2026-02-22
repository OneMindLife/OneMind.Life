import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';
import 'package:onemind_app/screens/tutorial/widgets/tutorial_progress_dots.dart';

import '../../helpers/pump_app.dart';

/// Helper to navigate from intro through template selection to proposing
Future<void> _navigateToProposing(WidgetTester tester) async {
  // Tap Next on intro
  await tester.ensureVisible(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  // Select Community Decision template
  await tester.ensureVisible(find.text('Community Decision'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Community Decision'));
  await tester.pumpAndSettle();
}

void main() {
  group('TutorialScreen', () {
    testWidgets('displays intro panel on start', (tester) async {
      var completed = false;

      await tester.pumpApp(
        TutorialScreen(
          onComplete: () => completed = true,
        ),
      );

      // Wait for post-frame callback to start tutorial
      await tester.pumpAndSettle();

      expect(find.text('Welcome to OneMind'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('tapping Next shows template selection', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Tap Next
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Template selection should appear
      expect(find.text('Personalize Your Tutorial'), findsOneWidget);
      expect(find.text('Personal Decision'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Community Decision'), findsOneWidget);
      expect(find.text('Workplace Culture'), findsOneWidget);
      expect(find.text('City Budget'), findsOneWidget);
      expect(find.text('Global Issues'), findsOneWidget);
    });

    testWidgets('hides app bar on intro and template selection, shows after template pick', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // No app bar on intro screen
      expect(find.byType(AppBar), findsNothing);

      // Go to template selection
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Still no app bar on template selection
      expect(find.byType(AppBar), findsNothing);

      // Select a template
      await tester.ensureVisible(find.text('Community Decision'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community Decision'));
      await tester.pumpAndSettle();

      // App bar appears with 3-dot menu (Skip is now inside PopupMenu)
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
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
      final submitFinder = find.widgetWithText(ElevatedButton, 'Submit');
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      // Should be at rating state now - shows "Start Rating" button
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
      expect(find.text('Welcome to OneMind'), findsOneWidget);
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
      testWidgets('intro panel has next and skip buttons', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Next'), findsOneWidget);
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

        final submitFinder = find.widgetWithText(ElevatedButton, 'Submit');
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should show rating state panel with "Start Rating" button
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
        expect(find.text('Welcome to OneMind'), findsOneWidget);
        expect(find.text('Learn how groups reach consensus together'), findsOneWidget);
      });

      testWidgets('displays localized bullet points', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Submit your ideas anonymously'), findsOneWidget);
        expect(find.text('Rate ideas from others'), findsOneWidget);
        expect(find.text('See how consensus is reached'), findsOneWidget);
      });

      testWidgets('displays localized button labels', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Next'), findsOneWidget);
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
      testWidgets('share button appears only at shareDemo step', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Share button should NOT be visible during proposing
        expect(find.byKey(const Key('tutorial-share-button')), findsNothing);
      });

      testWidgets('skip option is accessible via 3-dot menu', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to proposing
        await _navigateToProposing(tester);

        // Tap the 3-dot menu
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();

        // Skip option should be visible in the menu
        expect(find.text('Skip Tutorial'), findsOneWidget);
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

        final submitFinder = find.widgetWithText(ElevatedButton, 'Submit');
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

        final submitFinder = find.widgetWithText(ElevatedButton, 'Submit');
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

        final submitFinder = find.widgetWithText(ElevatedButton, 'Submit');
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();
        await tester.tap(submitFinder);
        await tester.pumpAndSettle();

        // Should not show snackbar
        expect(
          find.text('This idea already exists in this round. Try something different!'),
          findsNothing,
        );

        // Should be on rating state now
        expect(find.text('Start Rating'), findsOneWidget);
      });
    });

    group('Template selection', () {
      testWidgets('back button on template selection returns to intro', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Go to template selection
        await tester.ensureVisible(find.text('Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        expect(find.text('Personalize Your Tutorial'), findsOneWidget);

        // Tap back button
        await tester.tap(find.byKey(const Key('template-back-button')));
        await tester.pumpAndSettle();

        // Should be back on intro
        expect(find.text('Welcome to OneMind'), findsOneWidget);
      });

    });
  });
}
