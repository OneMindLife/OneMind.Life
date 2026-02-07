import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';

/// Test fixtures for tutorial-related tests
class TutorialFixtures {
  TutorialFixtures._();

  // ==========================================================================
  // TutorialState fixtures
  // ==========================================================================

  /// Default initial state
  static TutorialState initial() => const TutorialState();

  /// State at intro step
  static TutorialState intro() => const TutorialState(
        currentStep: TutorialStep.intro,
        currentRound: 1,
      );

  /// State at round 1 proposing
  static TutorialState round1Proposing() => const TutorialState(
        currentStep: TutorialStep.round1Proposing,
        currentRound: 1,
      );

  /// State at round 1 rating (after user submitted)
  static TutorialState round1Rating({String userProp = 'Family'}) =>
      TutorialState(
        currentStep: TutorialStep.round1Rating,
        currentRound: 1,
        userProposition1: userProp,
      );

  /// State at round 1 result
  static TutorialState round1Result({String userProp = 'Family'}) =>
      TutorialState(
        currentStep: TutorialStep.round1Result,
        currentRound: 1,
        userProposition1: userProp,
        currentWinnerContent: 'Success',
        isUserWinner: false,
      );

  /// State at round 2 prompt
  static TutorialState round2Prompt({String userProp1 = 'Family'}) =>
      TutorialState(
        currentStep: TutorialStep.round2Prompt,
        currentRound: 2,
        userProposition1: userProp1,
      );

  /// State at round 2 proposing
  static TutorialState round2Proposing({String userProp1 = 'Family'}) =>
      TutorialState(
        currentStep: TutorialStep.round2Proposing,
        currentRound: 2,
        userProposition1: userProp1,
      );

  /// State at round 2 rating
  static TutorialState round2Rating({
    String userProp1 = 'Family',
    String userProp2 = 'Balance',
  }) =>
      TutorialState(
        currentStep: TutorialStep.round2Rating,
        currentRound: 2,
        userProposition1: userProp1,
        userProposition2: userProp2,
      );

  /// State at round 2 result (user wins)
  static TutorialState round2Result({
    String userProp1 = 'Family',
    String userProp2 = 'Balance',
  }) =>
      TutorialState(
        currentStep: TutorialStep.round2Result,
        currentRound: 2,
        userProposition1: userProp1,
        userProposition2: userProp2,
        currentWinnerContent: userProp2,
        isUserWinner: true,
      );

  /// State at round 3 carry forward
  static TutorialState round3CarryForward({
    String userProp1 = 'Family',
    String userProp2 = 'Balance',
  }) =>
      TutorialState(
        currentStep: TutorialStep.round3CarryForward,
        currentRound: 3,
        userProposition1: userProp1,
        userProposition2: userProp2,
      );

  /// State at round 3 rating
  static TutorialState round3Rating({
    String userProp1 = 'Family',
    String userProp2 = 'Balance',
  }) =>
      TutorialState(
        currentStep: TutorialStep.round3Rating,
        currentRound: 3,
        userProposition1: userProp1,
        userProposition2: userProp2,
      );

  /// State at round 3 consensus
  static TutorialState round3Consensus({
    String userProp1 = 'Family',
    String userProp2 = 'Balance',
  }) =>
      TutorialState(
        currentStep: TutorialStep.round3Consensus,
        currentRound: 3,
        userProposition1: userProp1,
        userProposition2: userProp2,
        currentWinnerContent: userProp2,
        isUserWinner: true,
      );

  /// State at share demo
  static TutorialState shareDemo({
    String userProp1 = 'Family',
    String userProp2 = 'Balance',
  }) =>
      TutorialState(
        currentStep: TutorialStep.shareDemo,
        currentRound: 3,
        userProposition1: userProp1,
        userProposition2: userProp2,
      );

  /// State at complete
  static TutorialState complete({
    String userProp1 = 'Family',
    String userProp2 = 'Balance',
  }) =>
      TutorialState(
        currentStep: TutorialStep.complete,
        currentRound: 3,
        userProposition1: userProp1,
        userProposition2: userProp2,
      );

  // ==========================================================================
  // TutorialProposition fixtures
  // ==========================================================================

  /// Standard proposition
  static TutorialProposition proposition({
    String id = 'test_1',
    String content = 'Test proposition',
    bool isUserSubmitted = false,
    bool isCarriedForward = false,
  }) =>
      TutorialProposition(
        id: id,
        content: content,
        isUserSubmitted: isUserSubmitted,
        isCarriedForward: isCarriedForward,
      );

  /// User-submitted proposition
  static TutorialProposition userProposition({
    String id = 'user_1',
    String content = 'User idea',
  }) =>
      TutorialProposition(
        id: id,
        content: content,
        isUserSubmitted: true,
      );

  /// Carried forward proposition
  static TutorialProposition carriedForward({
    String id = 'carried_1',
    String content = 'Previous winner',
  }) =>
      TutorialProposition(
        id: id,
        content: content,
        isCarriedForward: true,
      );

  /// List of propositions for rating tests
  static List<TutorialProposition> ratingPropositions({int count = 3}) =>
      List.generate(
        count,
        (i) => TutorialProposition(
          id: 'prop_$i',
          content: 'Proposition ${i + 1}',
        ),
      );
}
