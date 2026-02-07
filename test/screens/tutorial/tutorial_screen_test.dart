import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';
import 'package:onemind_app/screens/tutorial/widgets/tutorial_progress_dots.dart';

import '../../helpers/pump_app.dart';

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
      expect(find.text('Start Tutorial'), findsOneWidget);
    });

    testWidgets('hides app bar on intro, shows after start', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // No app bar on intro screen
      expect(find.byType(AppBar), findsNothing);

      // Start the tutorial
      await tester.ensureVisible(find.text('Start Tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Tutorial'));
      await tester.pumpAndSettle();

      // App bar appears with 3-dot menu (Skip is now inside PopupMenu)
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('navigates to round 1 proposing when start tapped',
        (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Ensure button is visible before tapping
      await tester.ensureVisible(find.text('Start Tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Tutorial'));
      await tester.pumpAndSettle();

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
      await tester.ensureVisible(find.text('Start Tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Tutorial'));
      await tester.pumpAndSettle();

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


    testWidgets('displays progress dots after intro', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // No progress dots on intro
      expect(find.byType(TutorialProgressDots), findsNothing);

      // Go to proposing
      await tester.ensureVisible(find.text('Start Tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Tutorial'));
      await tester.pumpAndSettle();

      // Should see progress dots now
      expect(find.byType(TutorialProgressDots), findsOneWidget);
    });

    testWidgets('displays initial message in chat history', (tester) async {
      await tester.pumpApp(
        TutorialScreen(
          onComplete: () {},
        ),
      );
      await tester.pumpAndSettle();

      // Go to proposing
      await tester.ensureVisible(find.text('Start Tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Tutorial'));
      await tester.pumpAndSettle();

      // Initial message (the question) should be visible in the scrollable area
      expect(
        find.textContaining('What do we value?'),
        findsWidgets, // May appear in chat history
      );
    });

    group('Tutorial panel widgets', () {
      testWidgets('intro panel has start and skip buttons', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Start Tutorial'), findsOneWidget);
        expect(find.text('Skip tutorial'), findsOneWidget);
      });

      testWidgets('proposing state shows text field', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

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
        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

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

      testWidgets('displays localized tutorial question', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // The question should be from l10n
        expect(find.textContaining('What do we value?'), findsOneWidget);
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

        expect(find.text('Start Tutorial'), findsOneWidget);
        expect(find.text('Skip tutorial'), findsOneWidget);
      });

      testWidgets('displays localized initial message after starting', (tester) async {
        await tester.pumpApp(
          TutorialScreen(
            onComplete: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Start the tutorial
        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

        // Initial message should display the localized question
        expect(find.text('What do we value?'), findsOneWidget);
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

        // Start the tutorial
        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

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

        // Start the tutorial
        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

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

        // Go to proposing
        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

        // Try to submit "Success" (which already exists in round 1)
        await tester.enterText(find.byType(TextField), 'Success');
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

        // Go to proposing
        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

        // Try to submit "success" (lowercase - should match "Success")
        await tester.enterText(find.byType(TextField), 'success');
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

        // Go to proposing
        await tester.ensureVisible(find.text('Start Tutorial'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Tutorial'));
        await tester.pumpAndSettle();

        // Submit a unique proposition
        await tester.enterText(find.byType(TextField), 'Family');
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
  });
}
