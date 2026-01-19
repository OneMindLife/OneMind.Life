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
    testWidgets('shows host controls when isHost is true', (tester) async {
      var startCalled = false;

      await tester.pumpWidget(
        createTestWidget(
          WaitingStatePanel(
            isHost: true,
            participantCount: 5,
            onStartPhase: () => startCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start Phase'), findsNWidgets(2)); // Title and button
      expect(find.text('5 participants have joined'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      expect(startCalled, isTrue);
    });

    testWidgets('shows waiting message when not host', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          WaitingStatePanel(
            isHost: false,
            participantCount: 5,
            onStartPhase: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Waiting for host to start...'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('displays correct participant count', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          WaitingStatePanel(
            isHost: true,
            participantCount: 10,
            onStartPhase: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('10 participants have joined'), findsOneWidget);
    });

    testWidgets('displays singular participant for count of 1', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          WaitingStatePanel(
            isHost: true,
            participantCount: 1,
            onStartPhase: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 participants have joined'), findsOneWidget);
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

      expect(find.text('Round 1'), findsOneWidget);
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

      expect(find.text('Round 2'), findsOneWidget);
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

    testWidgets('host sees badge icon when propositions exist', (tester) async {
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

      // Host should see badge with count
      expect(find.byIcon(Icons.list_alt), findsOneWidget);
      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Badge shows total count
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

    testWidgets('host can still submit while having access to all propositions',
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

      // Host should see both: input field AND badge icon
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.list_alt), findsOneWidget);
      expect(find.text('1/3 submitted'), findsOneWidget);
    });

    testWidgets('tapping badge calls onViewAllPropositions callback',
        (tester) async {
      final controller = TextEditingController();
      final myProps = [PropositionFixtures.model(id: 1, content: 'My idea')];
      var viewAllCalled = false;

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
            onViewAllPropositions: () => viewAllCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the badge icon
      await tester.tap(find.byIcon(Icons.list_alt));
      await tester.pumpAndSettle();

      // Callback should be called (bottom sheet is now handled by parent)
      expect(viewAllCalled, isTrue);
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

      expect(find.text('Rate Propositions'), findsOneWidget);
      expect(find.text('Round 3'), findsOneWidget);
      expect(find.text('Rate all 5 propositions'), findsOneWidget);
      expect(find.text('Start Rating'), findsOneWidget);

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

      expect(find.text('Rating Complete'), findsOneWidget);
      expect(find.text('Round 3'), findsOneWidget);
      expect(find.text('Waiting for rating phase to end.'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('displays correct round number', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 7,
            hasRated: false,
            propositionCount: 3,
            onStartRating: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Round 7'), findsOneWidget);
    });

    testWidgets('displays correct proposition count', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          RatingStatePanel(
            roundCustomId: 1,
            hasRated: false,
            propositionCount: 10,
            onStartRating: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rate all 10 propositions'), findsOneWidget);
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

      // Should show paused message instead of proposition count
      expect(find.text('Chat is paused...'), findsOneWidget);
      expect(find.text('Rate all 5 propositions'), findsNothing);

      // Button should be disabled
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      // Tapping button should not call onStartRating
      await tester.tap(find.byType(ElevatedButton));
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

      // Should show normal proposition count
      expect(find.text('Rate all 5 propositions'), findsOneWidget);

      // Button should be enabled
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);

      // Tapping button should call onStartRating
      await tester.tap(find.byType(ElevatedButton));
      expect(startRatingCalled, isTrue);
    });
  });
}
