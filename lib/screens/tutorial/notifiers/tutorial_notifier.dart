import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../models/tutorial_state.dart';
import '../tutorial_data.dart';

/// Notifier for managing tutorial chat state (mirrors ChatDetailState behavior)
class TutorialChatNotifier extends StateNotifier<TutorialChatState> {
  TutorialChatNotifier()
      : super(TutorialChatState(
          chat: TutorialData.tutorialChat,
          myParticipant: TutorialData.tutorialParticipant,
          participants: TutorialData.allParticipants,
        ));

  /// Start the tutorial from intro
  void startTutorial() {
    state = TutorialChatState(
      currentStep: TutorialStep.intro,
      chat: TutorialData.tutorialChat,
      myParticipant: TutorialData.tutorialParticipant,
      participants: TutorialData.allParticipants,
    );
  }

  /// Reset the tutorial
  void resetTutorial() {
    state = TutorialChatState(
      chat: TutorialData.tutorialChat,
      myParticipant: TutorialData.tutorialParticipant,
      participants: TutorialData.allParticipants,
    );
  }

  // === ROUND 1 ===

  /// Move from intro to round 1 proposing
  void beginRound1() {
    state = state.copyWith(
      currentStep: TutorialStep.round1Proposing,
      currentRound: TutorialData.round1(phase: RoundPhase.proposing),
      myPropositions: [],
      hasRated: false,
      hasStartedRating: false,
    );
  }

  /// Submit proposition for round 1
  void submitRound1Proposition(String content) {
    final userProp = Proposition(
      id: -50,
      roundId: -1,
      participantId: -1,
      content: content,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      userProposition1: content,
      currentStep: TutorialStep.round1Rating,
      currentRound: TutorialData.round1(phase: RoundPhase.rating),
      myPropositions: [userProp],
      propositions: TutorialData.createPropositions(
        TutorialData.round1PropositionContents,
        roundId: -1,
        userProposition: content,
      ),
    );
  }

  /// Complete round 1 rating - "Success" wins
  void completeRound1Rating() {
    // Store Round 1 results for "See Results" button
    final round1Results = TutorialData.round1ResultsWithRatings(
      state.userProposition1 ?? '',
    );

    state = state.copyWith(
      currentStep: TutorialStep.round1Result,
      hasRated: true,
      previousRoundWinners: [TutorialData.round1Winner()],
      isSoleWinner: true,
      consecutiveSoleWins: 0, // User didn't win
      round1Results: round1Results,
    );
  }

  /// Move from round1Result to round1SeeResults (after first Continue)
  void continueToSeeResults() {
    print('DEBUG continueToSeeResults: before=${state.currentStep}');
    state = state.copyWith(
      currentStep: TutorialStep.round1SeeResults,
    );
    print('DEBUG continueToSeeResults: after=${state.currentStep}');
  }

  /// Mark that user has viewed the Round 1 grid
  void markRound1GridViewed() {
    state = state.copyWith(
      hasViewedRound1Grid: true,
    );
  }

  /// Move to round 2 - show prompt message and proposing input
  void continueToRound2() {
    state = state.copyWith(
      currentStep: TutorialStep.round2Prompt,
      currentRound: TutorialData.round2(phase: RoundPhase.proposing),
      myPropositions: [],
      hasRated: false,
      hasStartedRating: false,
    );
  }

  // === ROUND 2 ===

  /// Legacy - kept for test compatibility
  void beginRound2Proposing() {
    continueToRound2();
  }

  /// Submit proposition for round 2
  void submitRound2Proposition(String content) {
    final userProp = Proposition(
      id: -51,
      roundId: -2,
      participantId: -1,
      content: content,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      userProposition2: content,
      currentStep: TutorialStep.round2Rating,
      currentRound: TutorialData.round2(phase: RoundPhase.rating),
      myPropositions: [userProp],
      propositions: TutorialData.createPropositions(
        TutorialData.round2PropositionContents,
        roundId: -2,
        userProposition: content,
      ),
    );
  }

  /// Complete round 2 rating - user's proposition wins!
  void completeRound2Rating() {
    final userProp = state.userProposition2 ?? 'Your idea';
    state = state.copyWith(
      currentStep: TutorialStep.round2Result,
      hasRated: true,
      previousRoundWinners: [TutorialData.round2Winner(userProp)],
      isSoleWinner: true,
      consecutiveSoleWins: 1, // First win for user
      round2Results: TutorialData.round2ResultsWithRatings(userProp),
    );
  }

  /// Move to round 3 - go directly to proposing phase
  void continueToRound3() {
    state = state.copyWith(
      currentStep: TutorialStep.round3Proposing,
      currentRound: TutorialData.round3(phase: RoundPhase.proposing),
      myPropositions: [],
      hasRated: false,
      hasStartedRating: false,
    );
  }

  // === ROUND 3 ===

  /// Legacy - kept for test compatibility
  void beginRound3Rating() {
    // Skip to rating (used by tests)
    final userProp = state.userProposition2 ?? 'Your idea';
    final carriedProp = Proposition(
      id: -52,
      roundId: -3,
      participantId: -1,
      content: userProp,
      carriedFromId: -51,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      currentStep: TutorialStep.round3Rating,
      currentRound: TutorialData.round3(phase: RoundPhase.rating),
      myPropositions: [carriedProp],
      propositions: [
        carriedProp,
        ...TutorialData.createPropositions(
          TutorialData.round3PropositionContents,
          roundId: -3,
          includeUserProp: false,
        ),
      ],
    );
  }

  /// Submit proposition for round 3 (but Round 2 winner will still win - consensus!)
  void submitRound3Proposition(String content) {
    final userProp2 = state.userProposition2 ?? 'Your idea';

    // User's Round 2 proposition is carried forward (this is what will win)
    final carriedProp = Proposition(
      id: -52,
      roundId: -3,
      participantId: -1,
      content: userProp2,
      carriedFromId: -51,
      createdAt: DateTime.now(),
    );

    // User's new Round 3 proposition (will NOT win)
    final newProp = Proposition(
      id: -53,
      roundId: -3,
      participantId: -1,
      content: content,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      currentStep: TutorialStep.round3Rating,
      currentRound: TutorialData.round3(phase: RoundPhase.rating),
      // User has both: carried prop + new prop
      myPropositions: [carriedProp, newProp],
      propositions: [
        carriedProp,
        newProp,
        ...TutorialData.createPropositions(
          TutorialData.round3PropositionContents,
          roundId: -3,
          includeUserProp: false,
        ),
      ],
    );
  }

  /// Complete round 3 rating - CONSENSUS!
  void completeRound3Rating() {
    final userProp = state.userProposition2 ?? 'Your idea';
    state = state.copyWith(
      currentStep: TutorialStep.round3Consensus,
      hasRated: true,
      previousRoundWinners: [TutorialData.round3Winner(userProp)],
      isSoleWinner: true,
      round3Results: TutorialData.round3ResultsWithRatings(userProp),
      consecutiveSoleWins: 2, // Second consecutive win = CONSENSUS!
      consensusItems: [TutorialData.consensusProposition(userProp)],
    );
  }

  // === COMPLETION ===

  /// Move to share demo
  void continueToShareDemo() {
    state = state.copyWith(
      currentStep: TutorialStep.shareDemo,
    );
  }

  /// Complete the tutorial
  void completeTutorial() {
    state = state.copyWith(
      currentStep: TutorialStep.complete,
    );
  }

  /// Skip the tutorial
  void skipTutorial() {
    state = state.copyWith(
      currentStep: TutorialStep.complete,
    );
  }

  /// Mark rating as started (for UI tracking)
  void markRatingStarted() {
    state = state.copyWith(hasStartedRating: true);
  }

  /// Generic next step handler
  void nextStep() {
    switch (state.currentStep) {
      case TutorialStep.intro:
        beginRound1();
        break;
      case TutorialStep.round1Result:
        continueToSeeResults();
        break;
      case TutorialStep.round1SeeResults:
        continueToRound2();
        break;
      case TutorialStep.round2Prompt:
        beginRound2Proposing();
        break;
      case TutorialStep.round2Result:
        continueToRound3();
        break;
      case TutorialStep.round3CarryForward:
        beginRound3Rating();
        break;
      case TutorialStep.round3Consensus:
        continueToShareDemo();
        break;
      case TutorialStep.shareDemo:
        completeTutorial();
        break;
      default:
        break;
    }
  }
}

/// Legacy notifier for backwards compatibility with existing tests
class TutorialNotifier extends StateNotifier<TutorialState> {
  TutorialNotifier() : super(const TutorialState());

  void startTutorial() {
    state = const TutorialState(currentStep: TutorialStep.intro);
  }

  void resetTutorial() {
    state = const TutorialState();
  }

  void beginRound1() {
    state = state.copyWith(
      currentStep: TutorialStep.round1Proposing,
      currentRound: 1,
    );
  }

  void submitRound1Proposition(String content) {
    state = state.copyWith(
      userProposition1: content,
      currentStep: TutorialStep.round1Rating,
    );
  }

  void completeRound1Rating() {
    state = state.copyWith(
      currentStep: TutorialStep.round1Result,
      currentWinnerContent: TutorialData.round1WinnerContent,
      isUserWinner: false,
    );
  }

  void continueToRound2() {
    state = state.copyWith(
      currentStep: TutorialStep.round2Prompt,
      currentRound: 2,
    );
  }

  void beginRound2Proposing() {
    state = state.copyWith(
      currentStep: TutorialStep.round2Proposing,
    );
  }

  void submitRound2Proposition(String content) {
    state = state.copyWith(
      userProposition2: content,
      currentStep: TutorialStep.round2Rating,
    );
  }

  void completeRound2Rating() {
    state = state.copyWith(
      currentStep: TutorialStep.round2Result,
      currentWinnerContent: state.userProposition2,
      isUserWinner: true,
    );
  }

  void continueToRound3() {
    state = state.copyWith(
      currentStep: TutorialStep.round3CarryForward,
      currentRound: 3,
    );
  }

  void beginRound3Rating() {
    state = state.copyWith(
      currentStep: TutorialStep.round3Rating,
    );
  }

  void completeRound3Rating() {
    state = state.copyWith(
      currentStep: TutorialStep.round3Consensus,
      currentWinnerContent: state.userProposition2,
      isUserWinner: true,
    );
  }

  void continueToShareDemo() {
    state = state.copyWith(
      currentStep: TutorialStep.shareDemo,
    );
  }

  void completeTutorial() {
    state = state.copyWith(
      currentStep: TutorialStep.complete,
    );
  }

  void skipTutorial() {
    state = state.copyWith(
      currentStep: TutorialStep.complete,
    );
  }

  void nextStep() {
    switch (state.currentStep) {
      case TutorialStep.intro:
        beginRound1();
        break;
      case TutorialStep.round1Result:
        // Legacy: goes directly to round2Prompt (skipping round1SeeResults)
        // New TutorialChatNotifier uses sequential flow
        continueToRound2();
        break;
      case TutorialStep.round2Prompt:
        beginRound2Proposing();
        break;
      case TutorialStep.round2Result:
        continueToRound3();
        break;
      case TutorialStep.round3CarryForward:
        beginRound3Rating();
        break;
      case TutorialStep.round3Consensus:
        continueToShareDemo();
        break;
      case TutorialStep.shareDemo:
        completeTutorial();
        break;
      default:
        break;
    }
  }
}
