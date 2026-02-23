import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/notifiers/tutorial_notifier.dart';
import 'package:onemind_app/screens/tutorial/tutorial_data.dart';

void main() {
  group('TutorialNotifier', () {
    late TutorialNotifier notifier;

    setUp(() {
      notifier = TutorialNotifier();
    });

    group('initialization', () {
      test('starts with default state', () {
        expect(notifier.state.currentStep, TutorialStep.intro);
        expect(notifier.state.currentRound, 1);
        expect(notifier.state.userProposition1, isNull);
        expect(notifier.state.userProposition2, isNull);
      });
    });

    group('startTutorial', () {
      test('sets state to intro', () {
        notifier.startTutorial();
        expect(notifier.state.currentStep, TutorialStep.intro);
      });
    });

    group('resetTutorial', () {
      test('resets to initial state', () {
        // Advance to some state
        notifier.beginRound1();
        notifier.submitRound1Proposition('Test');

        // Reset
        notifier.resetTutorial();

        expect(notifier.state.currentStep, TutorialStep.intro);
        expect(notifier.state.userProposition1, isNull);
      });
    });

    group('Round 1 flow', () {
      test('beginRound1 advances to round1Proposing', () {
        notifier.beginRound1();
        expect(notifier.state.currentStep, TutorialStep.round1Proposing);
        expect(notifier.state.currentRound, 1);
      });

      test('submitRound1Proposition saves content and advances to rating', () {
        notifier.beginRound1();
        notifier.submitRound1Proposition('Family');

        expect(notifier.state.userProposition1, 'Family');
        expect(notifier.state.currentStep, TutorialStep.round1Rating);
      });

      test('completeRound1Rating sets winner to Success and advances', () {
        notifier.beginRound1();
        notifier.submitRound1Proposition('Family');
        notifier.completeRound1Rating();

        expect(notifier.state.currentStep, TutorialStep.round1Result);
        expect(notifier.state.currentWinnerContent, 'Success');
        expect(notifier.state.isUserWinner, false);
      });

      test('continueToRound2 advances to round2Prompt', () {
        notifier.beginRound1();
        notifier.submitRound1Proposition('Family');
        notifier.completeRound1Rating();
        notifier.continueToRound2();

        expect(notifier.state.currentStep, TutorialStep.round2Prompt);
        expect(notifier.state.currentRound, 2);
      });
    });

    group('Round 2 flow', () {
      setUp(() {
        // Set up to round 2
        notifier.beginRound1();
        notifier.submitRound1Proposition('Family');
        notifier.completeRound1Rating();
        notifier.continueToRound2();
      });

      test('beginRound2Proposing advances to proposing', () {
        notifier.beginRound2Proposing();
        expect(notifier.state.currentStep, TutorialStep.round2Proposing);
      });

      test('submitRound2Proposition saves content and advances to rating', () {
        notifier.beginRound2Proposing();
        notifier.submitRound2Proposition('Balance');

        expect(notifier.state.userProposition2, 'Balance');
        expect(notifier.state.currentStep, TutorialStep.round2Rating);
      });

      test('completeRound2Rating sets user as winner', () {
        notifier.beginRound2Proposing();
        notifier.submitRound2Proposition('Balance');
        notifier.completeRound2Rating();

        expect(notifier.state.currentStep, TutorialStep.round2Result);
        expect(notifier.state.currentWinnerContent, 'Balance');
        expect(notifier.state.isUserWinner, true);
      });

      test('continueToRound3 advances to carry forward', () {
        notifier.beginRound2Proposing();
        notifier.submitRound2Proposition('Balance');
        notifier.completeRound2Rating();
        notifier.continueToRound3();

        expect(notifier.state.currentStep, TutorialStep.round3CarryForward);
        expect(notifier.state.currentRound, 3);
      });
    });

    group('Round 3 flow', () {
      setUp(() {
        // Set up to round 3
        notifier.beginRound1();
        notifier.submitRound1Proposition('Family');
        notifier.completeRound1Rating();
        notifier.continueToRound2();
        notifier.beginRound2Proposing();
        notifier.submitRound2Proposition('Balance');
        notifier.completeRound2Rating();
        notifier.continueToRound3();
      });

      test('beginRound3Rating advances to rating', () {
        notifier.beginRound3Rating();
        expect(notifier.state.currentStep, TutorialStep.round3Rating);
      });

      test('completeRound3Rating sets user as winner (consensus)', () {
        notifier.beginRound3Rating();
        notifier.completeRound3Rating();

        expect(notifier.state.currentStep, TutorialStep.round3Consensus);
        expect(notifier.state.currentWinnerContent, 'Balance');
        expect(notifier.state.isUserWinner, true);
      });

      test('continueToShareDemo advances to share', () {
        notifier.beginRound3Rating();
        notifier.completeRound3Rating();
        notifier.continueToShareDemo();

        expect(notifier.state.currentStep, TutorialStep.shareDemo);
      });
    });

    group('Completion flow', () {
      test('completeTutorial sets step to complete', () {
        notifier.completeTutorial();
        expect(notifier.state.currentStep, TutorialStep.complete);
      });
    });

    group('Skip flow', () {
      test('skipTutorial from any step goes to complete', () {
        notifier.beginRound1();
        notifier.skipTutorial();
        expect(notifier.state.currentStep, TutorialStep.complete);
      });
    });

    group('nextStep', () {
      test('from intro goes to round1Proposing', () {
        notifier.nextStep();
        expect(notifier.state.currentStep, TutorialStep.round1Proposing);
      });

      test('from round1Result goes to round2Prompt', () {
        notifier.beginRound1();
        notifier.submitRound1Proposition('Test');
        notifier.completeRound1Rating();
        notifier.nextStep();
        expect(notifier.state.currentStep, TutorialStep.round2Prompt);
      });

      test('from round2Prompt goes to round2Proposing', () {
        notifier.beginRound1();
        notifier.submitRound1Proposition('Test');
        notifier.completeRound1Rating();
        notifier.continueToRound2();
        notifier.nextStep();
        expect(notifier.state.currentStep, TutorialStep.round2Proposing);
      });

      test('from shareDemo goes to complete', () {
        // Fast forward to share demo
        notifier.beginRound1();
        notifier.submitRound1Proposition('Family');
        notifier.completeRound1Rating();
        notifier.continueToRound2();
        notifier.beginRound2Proposing();
        notifier.submitRound2Proposition('Balance');
        notifier.completeRound2Rating();
        notifier.continueToRound3();
        notifier.beginRound3Rating();
        notifier.completeRound3Rating();
        notifier.continueToShareDemo();

        notifier.nextStep();
        expect(notifier.state.currentStep, TutorialStep.complete);
      });
    });

    group('Full tutorial flow', () {
      test('completes entire flow maintaining state', () {
        // Round 1
        notifier.startTutorial();
        expect(notifier.state.currentStep, TutorialStep.intro);

        notifier.beginRound1();
        expect(notifier.state.currentStep, TutorialStep.round1Proposing);

        notifier.submitRound1Proposition('Family');
        expect(notifier.state.userProposition1, 'Family');
        expect(notifier.state.currentStep, TutorialStep.round1Rating);

        notifier.completeRound1Rating();
        expect(notifier.state.currentWinnerContent, 'Success');
        expect(notifier.state.currentStep, TutorialStep.round1Result);

        // Round 2
        notifier.continueToRound2();
        expect(notifier.state.currentRound, 2);
        expect(notifier.state.currentStep, TutorialStep.round2Prompt);

        notifier.beginRound2Proposing();
        notifier.submitRound2Proposition('Balance');
        expect(notifier.state.userProposition2, 'Balance');
        expect(notifier.state.currentStep, TutorialStep.round2Rating);

        notifier.completeRound2Rating();
        expect(notifier.state.currentWinnerContent, 'Balance');
        expect(notifier.state.isUserWinner, true);

        // Round 3
        notifier.continueToRound3();
        expect(notifier.state.currentRound, 3);

        notifier.beginRound3Rating();
        notifier.completeRound3Rating();
        expect(notifier.state.currentStep, TutorialStep.round3Consensus);
        expect(notifier.state.currentWinnerContent, 'Balance');

        // Completion
        notifier.continueToShareDemo();
        expect(notifier.state.currentStep, TutorialStep.shareDemo);

        notifier.completeTutorial();
        expect(notifier.state.currentStep, TutorialStep.complete);

        // User propositions preserved throughout
        expect(notifier.state.userProposition1, 'Family');
        expect(notifier.state.userProposition2, 'Balance');
      });
    });
  });

  group('TutorialState', () {
    test('currentUserProposition returns correct value for each round', () {
      final round1 = const TutorialState(
        currentRound: 1,
        userProposition1: 'First',
      );
      expect(round1.currentUserProposition, 'First');

      final round2 = const TutorialState(
        currentRound: 2,
        userProposition1: 'First',
        userProposition2: 'Second',
      );
      expect(round2.currentUserProposition, 'Second');

      final round3 = const TutorialState(
        currentRound: 3,
        userProposition1: 'First',
        userProposition2: 'Second',
      );
      expect(round3.currentUserProposition, 'Second');
    });

    test('hasSubmittedCurrentRound returns correct value', () {
      final notSubmitted1 = const TutorialState(currentRound: 1);
      expect(notSubmitted1.hasSubmittedCurrentRound, false);

      final submitted1 = const TutorialState(
        currentRound: 1,
        userProposition1: 'Test',
      );
      expect(submitted1.hasSubmittedCurrentRound, true);

      final notSubmitted2 = const TutorialState(
        currentRound: 2,
        userProposition1: 'Test',
      );
      expect(notSubmitted2.hasSubmittedCurrentRound, false);

      final submitted2 = const TutorialState(
        currentRound: 2,
        userProposition1: 'Test',
        userProposition2: 'Test2',
      );
      expect(submitted2.hasSubmittedCurrentRound, true);

      // Round 3 has no proposing (carry forward)
      final round3 = const TutorialState(currentRound: 3);
      expect(round3.hasSubmittedCurrentRound, true);
    });

    test('copyWith preserves unchanged values', () {
      const original = TutorialState(
        currentStep: TutorialStep.round1Rating,
        currentRound: 1,
        userProposition1: 'Test',
      );

      final copied = original.copyWith(currentStep: TutorialStep.round1Result);

      expect(copied.currentStep, TutorialStep.round1Result);
      expect(copied.currentRound, 1);
      expect(copied.userProposition1, 'Test');
    });

    test('equality works correctly', () {
      const state1 = TutorialState(
        currentStep: TutorialStep.intro,
        userProposition1: 'Test',
      );
      const state2 = TutorialState(
        currentStep: TutorialStep.intro,
        userProposition1: 'Test',
      );
      const state3 = TutorialState(
        currentStep: TutorialStep.intro,
        userProposition1: 'Different',
      );

      expect(state1, equals(state2));
      expect(state1, isNot(equals(state3)));
    });
  });

  group('TutorialChatNotifier', () {
    late TutorialChatNotifier chatNotifier;

    setUp(() {
      chatNotifier = TutorialChatNotifier();
    });

    group('streamlined round 1 result flow', () {
      test('nextStep from round1Result goes directly to round2Prompt', () {
        chatNotifier.selectTemplate('community');
        chatNotifier.submitRound1Proposition('My Idea');
        chatNotifier.completeRound1Rating();

        expect(chatNotifier.state.currentStep, TutorialStep.round1Result);

        chatNotifier.nextStep();

        // Should go directly to round2Prompt (no round1SeeResults intermediate)
        expect(chatNotifier.state.currentStep, TutorialStep.round2Prompt);
      });

      test('completeRound1Rating stores round1Results for auto-open', () {
        chatNotifier.selectTemplate('community');
        chatNotifier.submitRound1Proposition('My Idea');
        chatNotifier.completeRound1Rating();

        // round1Results should be populated for the results screen
        expect(chatNotifier.state.round1Results, isNotEmpty);
        expect(chatNotifier.state.currentStep, TutorialStep.round1Result);
      });

      test('continueToRound2 works directly from round1Result', () {
        chatNotifier.selectTemplate('community');
        chatNotifier.submitRound1Proposition('My Idea');
        chatNotifier.completeRound1Rating();

        expect(chatNotifier.state.currentStep, TutorialStep.round1Result);

        chatNotifier.continueToRound2();

        expect(chatNotifier.state.currentStep, TutorialStep.round2Prompt);
        expect(chatNotifier.state.hasRated, false);
        expect(chatNotifier.state.myPropositions, isEmpty);
      });

      test('round1Result has previousRoundWinners set', () {
        chatNotifier.selectTemplate('community');
        chatNotifier.submitRound1Proposition('My Idea');
        chatNotifier.completeRound1Rating();

        expect(chatNotifier.state.previousRoundWinners, isNotEmpty);
        expect(chatNotifier.state.previousRoundWinners.first.content,
            'Community Garden');
      });
    });

    group('template selection', () {
      test('selectTemplate sets template and advances to round1Proposing', () {
        chatNotifier.selectTemplate('community');

        expect(chatNotifier.state.currentStep, TutorialStep.round1Proposing);
        expect(chatNotifier.state.selectedTemplate, 'community');
      });

      test('selectTemplate with custom question stores question', () {
        chatNotifier.selectTemplate('classic', customQuestion: 'My question?');

        expect(chatNotifier.state.selectedTemplate, 'classic');
        expect(chatNotifier.state.customQuestion, 'My question?');
        expect(chatNotifier.state.currentStep, TutorialStep.round1Proposing);
      });

    });

    group('template-aware propositions', () {
      test('community template uses community props in round 1', () {
        chatNotifier.selectTemplate('community');
        chatNotifier.submitRound1Proposition('My Idea');

        // Should contain community props + user prop
        final propContents = chatNotifier.state.propositions.map((p) => p.content).toList();
        expect(propContents, contains('Block Party'));
        expect(propContents, contains('Community Garden'));
        expect(propContents, contains('Neighborhood Watch'));
        expect(propContents, contains('My Idea'));
      });

      test('community template round 1 winner is Community Garden', () {
        chatNotifier.selectTemplate('community');
        chatNotifier.submitRound1Proposition('My Idea');
        chatNotifier.completeRound1Rating();

        final winnerContent = chatNotifier.state.previousRoundWinners.first.content;
        expect(winnerContent, 'Community Garden');
      });

      test('workplace template uses workplace props', () {
        chatNotifier.selectTemplate('workplace');
        chatNotifier.submitRound1Proposition('My Idea');

        final propContents = chatNotifier.state.propositions.map((p) => p.content).toList();
        expect(propContents, contains('Flexible Hours'));
        expect(propContents, contains('Mental Health Support'));
        expect(propContents, contains('Team Building'));
      });

      test('classic template (null) uses default props', () {
        // beginRound1 without selectTemplate (backwards compat)
        chatNotifier.beginRound1();
        chatNotifier.submitRound1Proposition('My Idea');

        final propContents = chatNotifier.state.propositions.map((p) => p.content).toList();
        expect(propContents, contains('Success'));
        expect(propContents, contains('Adventure'));
        expect(propContents, contains('Growth'));
      });
    });

    group('full flow with template', () {
      test('completes entire flow with community template', () {
        chatNotifier.selectTemplate('community');
        expect(chatNotifier.state.currentStep, TutorialStep.round1Proposing);
        expect(chatNotifier.state.selectedTemplate, 'community');

        chatNotifier.submitRound1Proposition('Education');
        expect(chatNotifier.state.currentStep, TutorialStep.round1Rating);

        chatNotifier.completeRound1Rating();
        expect(chatNotifier.state.currentStep, TutorialStep.round1Result);
        expect(chatNotifier.state.previousRoundWinners.first.content, 'Community Garden');

        chatNotifier.continueToRound2();
        chatNotifier.submitRound2Proposition('Better Education');
        chatNotifier.completeRound2Rating();
        expect(chatNotifier.state.currentStep, TutorialStep.round2Result);

        chatNotifier.continueToRound3();
        chatNotifier.submitRound3Proposition('Arts');
        chatNotifier.completeRound3Rating();
        expect(chatNotifier.state.currentStep, TutorialStep.round3Consensus);

        chatNotifier.continueToShareDemo();
        expect(chatNotifier.state.currentStep, TutorialStep.shareDemo);

        chatNotifier.completeTutorial();
        expect(chatNotifier.state.currentStep, TutorialStep.complete);
      });
    });
  });

  group('TutorialStep enum', () {
    test('does not contain round1SeeResults', () {
      // round1SeeResults was removed - verify it no longer exists
      final stepNames = TutorialStep.values.map((s) => s.name).toList();
      expect(stepNames, isNot(contains('round1SeeResults')));
    });

    test('round1Result is followed by round2Prompt in flow', () {
      // Verify the expected flow order
      final steps = TutorialStep.values;
      final round1ResultIndex = steps.indexOf(TutorialStep.round1Result);
      final round2PromptIndex = steps.indexOf(TutorialStep.round2Prompt);
      expect(round2PromptIndex, round1ResultIndex + 1);
    });
  });

  group('TutorialChatState', () {
    test('does not have hasViewedRound1Grid field', () {
      // Verify the state can be constructed without hasViewedRound1Grid
      final chatNotifier = TutorialChatNotifier();
      chatNotifier.selectTemplate('community');
      chatNotifier.submitRound1Proposition('Test');
      chatNotifier.completeRound1Rating();

      // The state should work correctly without hasViewedRound1Grid
      expect(chatNotifier.state.currentStep, TutorialStep.round1Result);
      expect(chatNotifier.state.round1Results, isNotEmpty);
    });
  });

  group('TutorialProposition', () {
    test('equality works correctly', () {
      const prop1 = TutorialProposition(id: '1', content: 'Test');
      const prop2 = TutorialProposition(id: '1', content: 'Test');
      const prop3 = TutorialProposition(id: '2', content: 'Test');

      expect(prop1, equals(prop2));
      expect(prop1, isNot(equals(prop3)));
    });

    test('properties are set correctly', () {
      const prop = TutorialProposition(
        id: 'test',
        content: 'Content',
        isUserSubmitted: true,
        isCarriedForward: true,
      );

      expect(prop.id, 'test');
      expect(prop.content, 'Content');
      expect(prop.isUserSubmitted, true);
      expect(prop.isCarriedForward, true);
    });
  });
}
