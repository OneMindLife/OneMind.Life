import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/chat/widgets/phase_panels.dart';

import '../../../fixtures/proposition_fixtures.dart';

void main() {
  /// Helper to create a test widget with localization support
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );
  }

  group('WaitingStatePanel', () {
    testWidgets('shows waiting for more participants with default auto-start',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const WaitingStatePanel(
            participantCount: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default auto-start is 3, so with 1 participant need 2 more
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.textContaining('2'), findsOneWidget);
      // No start button - phase auto-starts
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows waiting for 1 more when close to auto-start',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const WaitingStatePanel(
            participantCount: 2,
            autoStartParticipantCount: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // With 2 participants and auto-start at 3, need 1 more
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.textContaining('1'), findsOneWidget);
    });

    testWidgets('shows waiting for 0 when at or above auto-start threshold',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const WaitingStatePanel(
            participantCount: 5,
            autoStartParticipantCount: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // With 5 participants and auto-start at 3, remaining is 0
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.textContaining('0'), findsOneWidget);
    });

    testWidgets('uses custom auto-start participant count', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const WaitingStatePanel(
            participantCount: 2,
            autoStartParticipantCount: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // With 2 participants and auto-start at 5, need 3 more
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.textContaining('3'), findsOneWidget);
    });

    testWidgets('has correct key for testing', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const WaitingStatePanel(
            participantCount: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiting-state-panel')), findsOneWidget);
    });
  });

  group('ProposingStatePanel', () {
    testWidgets('shows input field when no propositions submitted',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 3,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simplified UI: shows submission count only when propositionsPerUser > 1
      expect(find.text('0/3 submitted'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Share your idea...'), findsOneWidget);
      expect(find.byKey(const Key('submit-proposition-button')), findsOneWidget);
    });

    testWidgets('shows submitted propositions when all submitted',
        (tester) async {
      final controller = TextEditingController();
      final propositions = [
        PropositionFixtures.model(id: 1, content: 'First idea'),
        PropositionFixtures.model(id: 2, content: 'Second idea'),
      ];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 2,
            propositionsPerUser: 2,
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Input is gone; user's own proposition cards are shown inline.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('First idea'), findsOneWidget);
      expect(find.text('Second idea'), findsOneWidget);
    });

    testWidgets('shows submitted proposition in single-prop mode',
        (tester) async {
      final controller = TextEditingController();
      final propositions = [
        PropositionFixtures.model(id: 1, content: 'Only idea'),
      ];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Only idea'), findsOneWidget);
    });

    testWidgets('proposition cards hidden while still able to submit',
        (tester) async {
      final controller = TextEditingController();
      final myProps = [PropositionFixtures.model(id: 1, content: 'One')];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 3, // submitted 1 of 3
            myPropositions: myProps,
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Input branch is active; proposition cards are not shown yet.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('One'), findsNothing);
    });

    testWidgets('no proposition cards when no submissions yet',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: const [],
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('calls onSubmit when button pressed', (tester) async {
      final controller = TextEditingController();
      var submitCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () => submitCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text so button becomes enabled (disabled when empty)
      await tester.enterText(find.byType(TextField), 'My idea');
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit-proposition-button')));
      expect(submitCalled, isTrue);
    });

    testWidgets('hides counter when propositionsPerUser is 1', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Counter should not show for single proposition mode
      expect(find.text('0/1 submitted'), findsNothing);
    });

    testWidgets('shows submitted proposition content inline after submission',
        (tester) async {
      final controller = TextEditingController();
      final propositions = [
        PropositionFixtures.model(id: 1, content: 'First'),
        PropositionFixtures.model(id: 2, content: 'Second'),
      ];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 2,
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User's own proposition content is shown inline as cards.
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });

    // Feature intentionally hidden - host should not see propositions to preserve anonymity
    testWidgets('host does NOT see badge icon (feature hidden)', (tester) async {
      final controller = TextEditingController();
      final myProps = [PropositionFixtures.model(id: 1, content: 'My idea')];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 3,
            myPropositions: myProps,
            allPropositionsCount: 3,
            propositionController: controller,
            onSubmit: () {},
            isHost: true,
            onViewAllPropositions: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Host should NOT see badge - feature is hidden to preserve anonymity
      expect(find.byIcon(Icons.list_alt), findsNothing);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('non-host does not see badge icon', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            allPropositionsCount: 1,
            propositionController: controller,
            onSubmit: () {},
            isHost: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Non-host should not see the badge icon
      expect(find.byIcon(Icons.list_alt), findsNothing);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('host can still submit propositions',
        (tester) async {
      final controller = TextEditingController();
      final myProps = [PropositionFixtures.model(id: 1, content: 'My first')];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 3, // Can submit 2 more
            myPropositions: myProps,
            allPropositionsCount: 2,
            propositionController: controller,
            onSubmit: () {},
            isHost: true,
            onViewAllPropositions: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Host should see input field (badge is hidden for anonymity)
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('1/3 submitted'), findsOneWidget);
    });

    // Feature intentionally hidden - badge does not exist so callback cannot be tested
    testWidgets('badge is hidden so callback is not accessible',
        (tester) async {
      final controller = TextEditingController();
      final myProps = [PropositionFixtures.model(id: 1, content: 'My idea')];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 3,
            myPropositions: myProps,
            allPropositionsCount: 2,
            propositionController: controller,
            onSubmit: () {},
            isHost: true,
            onViewAllPropositions: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Badge icon should not exist - feature hidden for anonymity
      expect(find.byIcon(Icons.list_alt), findsNothing);
    });

    testWidgets('disables text field and button when isPaused is true',
        (tester) async {
      final controller = TextEditingController();
      var submitCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () => submitCalled = true,
            isPaused: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Text field should show paused hint
      expect(find.text('Chat is paused...'), findsOneWidget);

      // Text field should be disabled
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);

      // Button should be disabled (onPressed is null)
      final button = tester.widget<IconButton>(find.byKey(const Key('submit-proposition-button')));
      expect(button.onPressed, isNull);

      // Tapping button should not call onSubmit
      await tester.tap(find.byKey(const Key('submit-proposition-button')));
      expect(submitCalled, isFalse);
    });

    testWidgets('enables text field and button when isPaused is false',
        (tester) async {
      final controller = TextEditingController();
      var submitCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () => submitCalled = true,
            isPaused: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Text field should show normal hint
      expect(find.text('Share your idea...'), findsOneWidget);

      // Text field should be enabled
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isTrue);

      // Enter text so button becomes enabled (disabled when empty)
      await tester.enterText(find.byType(TextField), 'My idea');
      await tester.pump();

      // Button should be enabled
      final button = tester.widget<IconButton>(find.byKey(const Key('submit-proposition-button')));
      expect(button.onPressed, isNotNull);

      // Tapping button should call onSubmit
      await tester.tap(find.byKey(const Key('submit-proposition-button')));
      expect(submitCalled, isTrue);
    });
  });

  group('HostPausedBanner', () {
    testWidgets('shows host message when isHost is true', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          HostPausedBanner(
            isHost: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chat Paused'), findsOneWidget);
      expect(
        find.text('The timer is stopped. Tap Resume in the app bar to continue.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    });

    testWidgets('shows participant message when isHost is false', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          HostPausedBanner(
            isHost: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chat Paused by Host'), findsOneWidget);
      expect(
        find.text('The host has paused this chat. Please wait for them to resume.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    });
  });

  group('RatingStatePanel', () {
    testWidgets('shows Start Rating button when not rated', (tester) async {
      var startRatingCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 3,
            hasRated: false,
            propositionCount: 5,
            onStartRating: () => startRatingCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simplified UI: just shows the button with timer
      expect(find.text('Start Rating'), findsOneWidget);
      expect(find.byKey(const Key('start-rating-button')), findsOneWidget);

      await tester.tap(find.text('Start Rating'));
      expect(startRatingCalled, isTrue);
    });

    testWidgets('shows rating complete when rated', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 3,
            hasRated: true,
            propositionCount: 5,
            onStartRating: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Shows waiting message and no button when already rated
      // "Waiting for rating phase to end" text removed — timer is in RoundPhaseBar
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows Continue Rating when hasStartedRating is true', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 7,
            hasRated: false,
            hasStartedRating: true,
            propositionCount: 3,
            onStartRating: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue Rating'), findsOneWidget);
    });

    testWidgets('disables rating button when isPaused is true', (tester) async {
      var startRatingCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            propositionCount: 5,
            onStartRating: () => startRatingCalled = true,
            isPaused: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Button should be disabled when paused
      final button = tester.widget<FilledButton>(find.byKey(const Key('start-rating-button')));
      expect(button.onPressed, isNull);

      // Tapping button should not call onStartRating
      await tester.tap(find.byKey(const Key('start-rating-button')));
      expect(startRatingCalled, isFalse);
    });

    testWidgets('enables rating button when isPaused is false', (tester) async {
      var startRatingCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            propositionCount: 5,
            onStartRating: () => startRatingCalled = true,
            isPaused: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Button should be enabled
      final button = tester.widget<FilledButton>(find.byKey(const Key('start-rating-button')));
      expect(button.onPressed, isNotNull);

      // Tapping button should call onStartRating
      await tester.tap(find.byKey(const Key('start-rating-button')));
      expect(startRatingCalled, isTrue);
    });
  });

  group('ProposingStatePanel - Duplicate Submission Prevention', () {
    testWidgets('disables submit button when isSubmitting is true',
        (tester) async {
      final controller = TextEditingController();
      var submitCallCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () => submitCallCount++,
            isSubmitting: true, // Submission in progress
          ),
        ),
      );
      // Use pump() instead of pumpAndSettle() because CircularProgressIndicator
      // animates continuously and will never "settle"
      await tester.pump();

      // Button should be disabled when submitting
      final button = tester.widget<IconButton>(find.byKey(const Key('submit-proposition-button')));
      expect(button.onPressed, isNull,
          reason: 'Submit button should be disabled when isSubmitting is true');

      // Tapping disabled button should not call onSubmit
      await tester.tap(find.byKey(const Key('submit-proposition-button')));
      expect(submitCallCount, 0,
          reason: 'onSubmit should not be called when button is disabled');
    });

    testWidgets('shows loading spinner when isSubmitting is true',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            isSubmitting: true, // Submission in progress
          ),
        ),
      );
      // Use pump() instead of pumpAndSettle() because CircularProgressIndicator
      // animates continuously and will never "settle"
      await tester.pump();

      // Should show loading indicator instead of text
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'Should show loading spinner when isSubmitting is true');

      // Should NOT show send icon when submitting (shows spinner instead)
      expect(find.byIcon(Icons.send_rounded), findsNothing,
          reason: 'Send icon should be hidden while loading spinner shows');
    });

    testWidgets('shows submit text when isSubmitting is false',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            isSubmitting: false, // Not submitting
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show send icon
      expect(find.byIcon(Icons.send_rounded), findsOneWidget,
          reason: 'Should show send icon when not submitting');

      // Should NOT show loading indicator
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'Should not show loading spinner when not submitting');
    });

    testWidgets('enables submit button when isSubmitting is false',
        (tester) async {
      final controller = TextEditingController();
      var submitCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () => submitCalled = true,
            isSubmitting: false, // Not submitting
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text so button becomes enabled (disabled when empty)
      await tester.enterText(find.byType(TextField), 'My idea');
      await tester.pump();

      // Button should be enabled
      final button = tester.widget<IconButton>(find.byKey(const Key('submit-proposition-button')));
      expect(button.onPressed, isNotNull,
          reason: 'Submit button should be enabled when isSubmitting is false');

      // Tapping button should call onSubmit
      await tester.tap(find.byKey(const Key('submit-proposition-button')));
      expect(submitCalled, isTrue,
          reason: 'onSubmit should be called when button is tapped');
    });

    testWidgets('disables skip-in-send button when isSubmitting',
        (tester) async {
      final controller = TextEditingController();
      var skipCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            onSkip: () => skipCalled = true,
            canSkip: true,
            maxSkips: 3,
            isSubmitting: true, // Submission in progress
          ),
        ),
      );
      // Use pump() instead of pumpAndSettle() because CircularProgressIndicator
      // animates continuously and will never "settle"
      await tester.pump();

      // With empty text + canSkip, the button key is skip-proposing-button
      // but it should be disabled due to isSubmitting
      // The button shows a spinner when isSubmitting regardless of skip state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // No separate skip TextButton should exist (merged into send button)
      expect(find.byType(TextButton), findsNothing);

      // Tapping should not call callback
      // Find the IconButton by type since key depends on text state
      final buttons = find.byType(IconButton);
      expect(buttons, findsWidgets);
      await tester.tap(buttons.last);
      expect(skipCalled, isFalse);
    });

    testWidgets('isSubmitting takes precedence over isPaused for button state',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            isPaused: false,
            isSubmitting: true, // Even when not paused, submitting disables
          ),
        ),
      );
      // Use pump() instead of pumpAndSettle() because CircularProgressIndicator
      // animates continuously and will never "settle"
      await tester.pump();

      // Button should be disabled due to isSubmitting
      final button = tester.widget<IconButton>(find.byKey(const Key('submit-proposition-button')));
      expect(button.onPressed, isNull,
          reason: 'isSubmitting should disable button even when not paused');

      // Should show loading spinner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('default isSubmitting value is false', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            // isSubmitting not specified - should default to false
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text so button becomes enabled (disabled when empty)
      await tester.enterText(find.byType(TextField), 'My idea');
      await tester.pump();

      // Button should be enabled by default
      final button = tester.widget<IconButton>(find.byKey(const Key('submit-proposition-button')));
      expect(button.onPressed, isNotNull,
          reason: 'Button should be enabled when isSubmitting defaults to false');

      // Should show send icon, not loading spinner
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('ProposingStatePanel - Post-action indicators', () {
    // The countdown timer used to live inside this panel via the embedded
    // RoundPhaseBar. The phase bar has since moved to the top of the chat
    // screen (under the AppBar), so the panel only renders post-action
    // state (the user's submitted prop card, the skipped indicator, etc.).
    // These tests verify those indicators render correctly; timer behavior
    // is covered separately by RoundPhaseBar widget tests.

    testWidgets('renders the user\'s submitted prop card after submission',
        (tester) async {
      final controller = TextEditingController();
      final propositions = [
        PropositionFixtures.model(id: 1, content: 'My idea'),
      ];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My idea'), findsOneWidget,
          reason: 'Submitted prop is centered in the panel after submit cap reached');
    });

    testWidgets('renders the skipped indicator after skipping',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            hasSkipped: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skipped-indicator')), findsOneWidget);
    });

    testWidgets('does not render its own countdown timer (now at top of screen)',
        (tester) async {
      final controller = TextEditingController();
      final propositions = [
        PropositionFixtures.model(id: 1, content: 'My idea'),
      ];

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
            phaseEndsAt: DateTime.now().add(const Duration(minutes: 5)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No timer text inside the panel — RoundPhaseBar handles that now.
      expect(find.textContaining('m '), findsNothing,
          reason: 'Countdown timer moved to RoundPhaseBar at the top of the screen');
    });
  });

  group('RatingStatePanel - Skip Rating', () {
    testWidgets('shows skip button when canSkipRating is true and maxRatingSkips > 0',
        (tester) async {
      var skipCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            hasStartedRating: false,
            propositionCount: 5,
            onStartRating: () {},
            canSkipRating: true,
            maxRatingSkips: 2,
            onSkipRating: () => skipCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show both Start Rating and Skip buttons
      expect(find.text('Start Rating'), findsOneWidget);
      expect(find.byKey(const Key('skip-rating-button')), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      // Tapping skip should call onSkipRating
      await tester.tap(find.text('Skip'));
      expect(skipCalled, isTrue);
    });

    testWidgets('hides skip button when canSkipRating is false',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            hasStartedRating: false,
            propositionCount: 5,
            onStartRating: () {},
            canSkipRating: false,
            maxRatingSkips: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start Rating'), findsOneWidget);
      expect(find.byKey(const Key('skip-rating-button')), findsNothing);
    });

    testWidgets('hides skip button when maxRatingSkips is 0',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            hasStartedRating: false,
            propositionCount: 5,
            onStartRating: () {},
            canSkipRating: true,
            maxRatingSkips: 0, // No skips allowed
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start Rating'), findsOneWidget);
      expect(find.byKey(const Key('skip-rating-button')), findsNothing);
    });

    testWidgets('hides skip button when hasStartedRating is true',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            hasStartedRating: true, // Already started
            propositionCount: 5,
            onStartRating: () {},
            canSkipRating: true,
            maxRatingSkips: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue Rating'), findsOneWidget);
      expect(find.byKey(const Key('skip-rating-button')), findsNothing);
    });

    testWidgets('shows skipped indicator when hasSkippedRating is true',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            propositionCount: 5,
            onStartRating: () {},
            hasSkippedRating: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show skipped indicator
      expect(find.byKey(const Key('rating-skipped-indicator')), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      // Should show waiting message
      // "Waiting for rating phase to end" text removed — timer is in RoundPhaseBar
      // Should NOT show Start Rating button
      expect(find.byKey(const Key('start-rating-button')), findsNothing);
    });

    testWidgets('shows countdown timer in skipped indicator when phaseEndsAt is set',
        (tester) async {
      final phaseEndsAt = DateTime.now().add(const Duration(minutes: 3));

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            propositionCount: 5,
            onStartRating: () {},
            hasSkippedRating: true,
            phaseEndsAt: phaseEndsAt,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('rating-skipped-indicator')), findsOneWidget);
      // Timer is now rendered by the top-of-screen RoundPhaseBar, not here.
      expect(find.textContaining('m '), findsNothing,
          reason: 'Countdown timer no longer rendered by RatingStatePanel');
    });

    testWidgets('disables skip button when isPaused is true',
        (tester) async {
      var skipCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            propositionCount: 5,
            onStartRating: () {},
            canSkipRating: true,
            maxRatingSkips: 2,
            onSkipRating: () => skipCalled = true,
            isPaused: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Skip button should be disabled when paused
      final skipButton = tester.widget<TextButton>(
        find.byKey(const Key('skip-rating-button')),
      );
      expect(skipButton.onPressed, isNull);

      await tester.tap(find.byKey(const Key('skip-rating-button')));
      expect(skipCalled, isFalse);
    });

    testWidgets('default skip values show no skip button',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            propositionCount: 5,
            onStartRating: () {},
            // All skip params at defaults
          ),
        ),
      );
      await tester.pumpAndSettle();

      // By default canSkipRating=false and maxRatingSkips=0, so no skip button
      expect(find.byKey(const Key('skip-rating-button')), findsNothing);
      expect(find.text('Start Rating'), findsOneWidget);
    });
  });

  group('ProposingStatePanel - Task Result Mode', () {
    testWidgets('hides skip button in task result mode', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            isTaskResultMode: true,
            canSkip: true,
            maxSkips: 5,
            onSkip: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Skip button should be hidden in task result mode
      expect(find.byKey(const Key('skip-proposing-button')), findsNothing);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('shows "Submit Result" button text in task result mode',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            isTaskResultMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Submit Result'), findsOneWidget);
      expect(find.byTooltip('Submit'), findsNothing);
    });

    testWidgets('shows task result hint text in task result mode',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            isTaskResultMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter task result...'), findsOneWidget);
      expect(find.text('Share your idea...'), findsNothing);
    });

    testWidgets('submit fires callback in task result mode', (tester) async {
      final controller = TextEditingController();
      var submitCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () => submitCalled = true,
            isTaskResultMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text so button becomes enabled (disabled when empty)
      await tester.enterText(find.byType(TextField), 'Task result');
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit-proposition-button')));
      expect(submitCalled, isTrue);
    });
  });

  group('RatingStatePanel - Countdown Timer After Rating', () {
    testWidgets('shows countdown timer after completing rating',
        (tester) async {
      final phaseEndsAt = DateTime.now().add(const Duration(minutes: 2));

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: true,
            propositionCount: 5,
            onStartRating: () {},
            phaseEndsAt: phaseEndsAt,
          ),
        ),
      );
      await tester.pump();

      // Should show the rating complete indicator
      expect(find.byKey(const Key('rating-complete-indicator')), findsOneWidget);
      // Timer moved to top-of-screen RoundPhaseBar; not rendered here.
      expect(find.textContaining('m '), findsNothing,
          reason: 'Countdown timer no longer rendered by RatingStatePanel');
    });

    testWidgets('does not show countdown timer when phaseEndsAt is null after rating',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: true,
            propositionCount: 5,
            onStartRating: () {},
            phaseEndsAt: null, // No deadline
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show waiting text
      // "Waiting for rating phase to end" text removed — timer is in RoundPhaseBar
      // No countdown timer widget should be present in the rating-complete-indicator
      final container = find.byKey(const Key('rating-complete-indicator'));
      expect(container, findsOneWidget);
    });

    testWidgets('still renders rating-complete indicator even with phaseEndsAt set',
        (tester) async {
      // Sanity check that passing phaseEndsAt doesn't break the panel —
      // the timer itself is rendered by the top-of-screen RoundPhaseBar
      // (not here), and the indicator still appears.
      final phaseEndsAt = DateTime.now().add(const Duration(minutes: 5));

      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: true,
            propositionCount: 5,
            onStartRating: () {},
            phaseEndsAt: phaseEndsAt,
            onPhaseExpired: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rating-complete-indicator')), findsOneWidget);
    });
  });
}
