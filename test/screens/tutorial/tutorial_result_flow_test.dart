import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/notifiers/tutorial_notifier.dart';

void main() {
  group('Round 1 result flow', () {
    late TutorialChatNotifier notifier;

    setUp(() {
      notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('My Idea');
      notifier.completeRound1Rating();
    });

    test('sets step to round1Result', () {
      expect(notifier.state.currentStep, TutorialStep.round1Result);
    });

    test('winner is Movie Night (saturday template)', () {
      expect(notifier.state.previousRoundWinners.first.content, 'Movie Night');
    });

    test('isSoleWinner is true', () {
      expect(notifier.state.isSoleWinner, true);
    });

    test('consecutiveSoleWins is 0 (user did not win R1)', () {
      expect(notifier.state.consecutiveSoleWins, 0);
    });

    test('round1Results populated with 4 propositions', () {
      expect(notifier.state.round1Results.length, 4);
    });

    test('round1Results winner has rating 100', () {
      final winner = notifier.state.round1Results
          .firstWhere((p) => p.content == 'Movie Night');
      expect(winner.finalRating, 100.0);
    });

    test('round1Results user prop has rating 0', () {
      final userProp = notifier.state.round1Results
          .firstWhere((p) => p.content == 'My Idea');
      expect(userProp.finalRating, 0.0);
    });

    test('continueToRound2 transitions to round2Prompt', () {
      notifier.continueToRound2();
      expect(notifier.state.currentStep, TutorialStep.round2Prompt);
      expect(notifier.state.currentRound?.customId, 2);
    });

    test('continueToRound2 resets hasRated and hasStartedRating', () {
      notifier.continueToRound2();
      expect(notifier.state.hasRated, false);
      expect(notifier.state.hasStartedRating, false);
    });

    test('continueToRound2 clears myPropositions', () {
      notifier.continueToRound2();
      expect(notifier.state.myPropositions, isEmpty);
    });
  });

  group('Round 2 result flow', () {
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
    });

    test('sets step to round2Result', () {
      expect(notifier.state.currentStep, TutorialStep.round2Result);
    });

    test('winner is user proposition', () {
      expect(notifier.state.previousRoundWinners.first.content, 'Idea 2');
    });

    test('isUserWinner is true', () {
      expect(notifier.state.isUserWinner, true);
    });

    test('consecutiveSoleWins is 1 (first win)', () {
      expect(notifier.state.consecutiveSoleWins, 1);
    });

    test('round2Results populated with 5 propositions', () {
      expect(notifier.state.round2Results.length, 5);
    });

    test('round2Results user prop has rating 100', () {
      final userProp = notifier.state.round2Results
          .firstWhere((p) => p.content == 'Idea 2');
      expect(userProp.finalRating, 100.0);
    });

    test('round2Results includes carried forward Movie Night', () {
      final carried = notifier.state.round2Results
          .firstWhere((p) => p.content == 'Movie Night');
      expect(carried.finalRating, 75.0);
    });

    test('continueToRound3 transitions to round3Proposing', () {
      notifier.continueToRound3();
      expect(notifier.state.currentStep, TutorialStep.round3Proposing);
      expect(notifier.state.currentRound?.customId, 3);
    });

    test('continueToRound3 resets rating state', () {
      notifier.continueToRound3();
      expect(notifier.state.hasRated, false);
      expect(notifier.state.hasStartedRating, false);
      expect(notifier.state.myPropositions, isEmpty);
    });
  });

  group('Round 3 result (consensus) flow', () {
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
      notifier.submitRound3Proposition('Idea 3');
      notifier.completeRound3Rating();
    });

    test('sets step to round3Consensus', () {
      expect(notifier.state.currentStep, TutorialStep.round3Consensus);
    });

    test('consecutiveSoleWins is 2 (consensus!)', () {
      expect(notifier.state.consecutiveSoleWins, 2);
    });

    test('consensusItems contains user R2 proposition', () {
      expect(notifier.state.consensusItems.length, 1);
      expect(notifier.state.consensusItems.first.content, 'Idea 2');
    });

    test('winner is still user R2 proposition (carried forward won again)', () {
      expect(notifier.state.previousRoundWinners.first.content, 'Idea 2');
    });

    test('round3Results populated with correct count', () {
      // With R3 submission: carried + user R3 + 3 NPC = 5
      expect(notifier.state.round3Results.length, 5);
    });

    test('round3Results winner (carried) has rating 100', () {
      final winner = notifier.state.round3Results
          .firstWhere((p) => p.content == 'Idea 2');
      expect(winner.finalRating, 100.0);
    });

    test('round3Results includes user R3 submission', () {
      final userR3 = notifier.state.round3Results
          .firstWhere((p) => p.content == 'Idea 3');
      expect(userR3.finalRating, 75.0);
    });
  });

  group('Round 3 result with skip (no R3 submission)', () {
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
      // Skip R3 proposing
      notifier.beginRound3Rating();
      notifier.completeRound3Rating();
    });

    test('consensus still achieved', () {
      expect(notifier.state.currentStep, TutorialStep.round3Consensus);
      expect(notifier.state.consecutiveSoleWins, 2);
    });

    test('round3Results has 4 propositions (no user R3)', () {
      expect(notifier.state.round3Results.length, 4);
    });

    test('NPC ratings are 67, 33, 0 without user R3 prop', () {
      final npcResults = notifier.state.round3Results
          .where((p) => p.participantId != -1)
          .toList();
      final ratings = npcResults.map((p) => p.finalRating).toList()..sort();
      expect(ratings, [0.0, 33.0, 67.0]);
    });
  });

  group('Classic template result flow', () {
    late TutorialChatNotifier notifier;

    setUp(() {
      notifier = TutorialChatNotifier();
      notifier.selectTemplate('classic');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('My Value');
      notifier.completeRound1Rating();
    });

    test('R1 winner is Success (classic template)', () {
      expect(notifier.state.previousRoundWinners.first.content, 'Success');
    });

    test('R1 results use classic props', () {
      final contents = notifier.state.round1Results
          .map((p) => p.content)
          .toList();
      expect(contents, contains('Success'));
      expect(contents, contains('Adventure'));
      expect(contents, contains('Growth'));
      expect(contents, contains('My Value'));
    });

    test('R2 uses classic carried forward (Success)', () {
      notifier.continueToRound2();
      notifier.submitRound2Proposition('My R2');

      final carried = notifier.state.propositions
          .where((p) => p.carriedFromId != null)
          .toList();
      expect(carried.length, 1);
      expect(carried.first.content, 'Success');
    });
  });

  group('setWinnerIndex', () {
    test('updates currentWinnerIndex', () {
      final notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');
      notifier.completeRound1Rating();

      expect(notifier.state.currentWinnerIndex, 0);

      notifier.setWinnerIndex(1);
      expect(notifier.state.currentWinnerIndex, 1);
    });
  });

  group('markRatingStarted', () {
    test('sets hasStartedRating to true', () {
      final notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');
      notifier.skipChatTour();
      notifier.submitRound1Proposition('Idea');

      expect(notifier.state.hasStartedRating, false);
      notifier.markRatingStarted();
      expect(notifier.state.hasStartedRating, true);
    });
  });
}
