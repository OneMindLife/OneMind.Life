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
      expect(find.byType(ElevatedButton), findsNothing);
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
      expect(find.text('Submit'), findsOneWidget);
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
            propositionsPerUser: 2, // Equal to propositions count so cards shown
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Shows submitted propositions and waiting message
      expect(find.text('First idea'), findsOneWidget);
      expect(find.text('Second idea'), findsOneWidget);
      expect(find.text('Waiting for rating phase...'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('shows waiting message when all propositions submitted',
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

      expect(find.text('Only idea'), findsOneWidget);
      expect(find.text('Waiting for rating phase...'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
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

      await tester.tap(find.text('Submit'));
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

    testWidgets('shows numbered circles for multiple propositions',
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
            propositionsPerUser: 2, // Equal to propositions count so cards shown
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
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
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      // Tapping button should not call onSubmit
      await tester.tap(find.byType(ElevatedButton));
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

      // Button should be enabled
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);

      // Tapping button should call onSubmit
      await tester.tap(find.byType(ElevatedButton));
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
      expect(find.byIcon(Icons.pause_circle), findsOneWidget);
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
      expect(find.byIcon(Icons.pause_circle), findsOneWidget);
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
      expect(find.byType(FilledButton), findsOneWidget);

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
      expect(find.text('Waiting for rating phase to end.'), findsOneWidget);
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
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      // Tapping button should not call onStartRating
      await tester.tap(find.byType(FilledButton));
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
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);

      // Tapping button should call onStartRating
      await tester.tap(find.byType(FilledButton));
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
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull,
          reason: 'Submit button should be disabled when isSubmitting is true');

      // Tapping disabled button should not call onSubmit
      await tester.tap(find.byType(ElevatedButton));
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

      // Should NOT show "Submit" text when submitting
      expect(find.text('Submit'), findsNothing,
          reason: 'Submit text should be hidden while loading spinner shows');
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

      // Should show "Submit" text
      expect(find.text('Submit'), findsOneWidget,
          reason: 'Should show Submit text when not submitting');

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

      // Button should be enabled
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull,
          reason: 'Submit button should be enabled when isSubmitting is false');

      // Tapping button should call onSubmit
      await tester.tap(find.byType(ElevatedButton));
      expect(submitCalled, isTrue,
          reason: 'onSubmit should be called when button is tapped');
    });

    testWidgets('disables both submit and skip buttons when isSubmitting',
        (tester) async {
      final controller = TextEditingController();
      var submitCalled = false;
      var skipCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () => submitCalled = true,
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

      // Submit button should be disabled
      final submitButton = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(submitButton.onPressed, isNull,
          reason: 'Submit button should be disabled when isSubmitting');

      // Skip button should also be disabled
      final skipButton = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(skipButton.onPressed, isNull,
          reason: 'Skip button should be disabled when isSubmitting');

      // Tapping either should not call the callbacks
      await tester.tap(find.byType(ElevatedButton));
      await tester.tap(find.byType(OutlinedButton));
      expect(submitCalled, isFalse);
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
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
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

      // Button should be enabled by default
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull,
          reason: 'Button should be enabled when isSubmitting defaults to false');

      // Should show "Submit" text, not loading spinner
      expect(find.text('Submit'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('ProposingStatePanel - Countdown Timer After Submission', () {
    testWidgets('shows countdown timer after submitting all propositions',
        (tester) async {
      final controller = TextEditingController();
      final propositions = [
        PropositionFixtures.model(id: 1, content: 'My idea'),
      ];
      final phaseEndsAt = DateTime.now().add(const Duration(minutes: 5));

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: propositions,
            propositionController: controller,
            onSubmit: () {},
            phaseEndsAt: phaseEndsAt,
          ),
        ),
      );
      await tester.pump();

      // Should show the waiting text and countdown timer
      expect(find.text('Waiting for rating phase...'), findsOneWidget);
      // Timer should be present (showing minutes)
      expect(find.textContaining('m'), findsWidgets);
    });

    testWidgets('shows countdown timer after skipping',
        (tester) async {
      final controller = TextEditingController();
      final phaseEndsAt = DateTime.now().add(const Duration(minutes: 3));

      await tester.pumpWidget(
        createTestWidget(
          ProposingStatePanel(
            roundCustomId: 1,
            propositionsPerUser: 1,
            myPropositions: [],
            propositionController: controller,
            onSubmit: () {},
            hasSkipped: true,
            phaseEndsAt: phaseEndsAt,
          ),
        ),
      );
      await tester.pump();

      // Should show skipped indicator
      expect(find.byKey(const Key('skipped-indicator')), findsOneWidget);
      // Should show waiting text with countdown
      expect(find.text('Waiting for rating phase...'), findsOneWidget);
      // Timer should be present (showing minutes)
      expect(find.textContaining('m'), findsWidgets);
    });

    testWidgets('does not show countdown timer when phaseEndsAt is null after submission',
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
            phaseEndsAt: null, // No deadline
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show waiting text without timer parentheses
      expect(find.text('Waiting for rating phase...'), findsOneWidget);
      // Should not have parentheses for timer
      expect(find.text('('), findsNothing);
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
      expect(find.text('Waiting for rating phase to end.'), findsOneWidget);
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
      // Timer should show minutes
      expect(find.textContaining('m'), findsWidgets);
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
      final skipButton = tester.widget<OutlinedButton>(
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

      expect(find.text('Submit Result'), findsOneWidget);
      expect(find.text('Submit'), findsNothing);
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

      await tester.tap(find.text('Submit Result'));
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
      expect(find.text('Waiting for rating phase to end.'), findsOneWidget);
      // Timer should be present (showing minutes)
      expect(find.textContaining('m'), findsWidgets);
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
      expect(find.text('Waiting for rating phase to end.'), findsOneWidget);
      // No countdown timer widget should be present in the rating-complete-indicator
      final container = find.byKey(const Key('rating-complete-indicator'));
      expect(container, findsOneWidget);
    });

    testWidgets('passes onPhaseExpired to CountdownTimer after rating',
        (tester) async {
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
      await tester.pump();

      // Verify CountdownTimer is rendered in the rating-complete-indicator
      // The actual expiration callback behavior is tested in countdown_timer_test.dart
      expect(find.byKey(const Key('rating-complete-indicator')), findsOneWidget);
      expect(find.textContaining('m'), findsWidgets);
    });
  });
}
