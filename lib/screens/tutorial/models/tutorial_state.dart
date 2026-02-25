import 'package:equatable/equatable.dart';
import '../../../models/models.dart';

/// Steps in the tutorial flow
enum TutorialStep {
  // Intro
  intro,

  // Chat screen tour (after template, before rounds)
  chatTourTitle,
  chatTourParticipants,
  chatTourMessage,
  chatTourProposing,

  // Round 1
  round1Proposing,
  round1Rating,
  round1Result,

  // Round 2
  round2Prompt,
  round2Proposing,
  round2Rating,
  round2Result,

  // Round 3
  round3CarryForward,
  round3Proposing,
  round3Rating,
  round3Consensus,

  // Completion
  shareDemo,
  complete,
}

/// A fake proposition used in the tutorial
class TutorialProposition extends Equatable {
  final String id;
  final String content;
  final bool isUserSubmitted;
  final bool isCarriedForward;

  const TutorialProposition({
    required this.id,
    required this.content,
    this.isUserSubmitted = false,
    this.isCarriedForward = false,
  });

  @override
  List<Object?> get props => [id, content, isUserSubmitted, isCarriedForward];
}

/// State for the tutorial chat screen - mirrors ChatDetailState structure
class TutorialChatState extends Equatable {
  final TutorialStep currentStep;

  // Chat data (mirrors ChatDetailState)
  final Chat chat;
  final Round? currentRound;
  final List<Proposition> consensusItems;
  final List<Proposition> propositions;
  final List<Participant> participants;
  final Participant myParticipant;
  final List<Proposition> myPropositions;
  final bool hasRated;
  final bool hasStartedRating;
  final List<RoundWinner> previousRoundWinners;
  final bool isSoleWinner;
  final int consecutiveSoleWins;

  // Tutorial-specific state
  final String? selectedTemplate; // template key: 'community', 'workplace', 'big_questions', 'family', 'custom'
  final String? customQuestion; // custom topic question (only for 'custom' template)
  final String? userProposition1; // Round 1 submission
  final String? userProposition2; // Round 2 submission

  /// Round 1 results with final ratings (for "See Results" grid)
  final List<Proposition> round1Results;

  /// Round 2 results with final ratings (for "See Results" grid)
  final List<Proposition> round2Results;

  /// Round 3 results with final ratings (for "See Results" grid)
  final List<Proposition> round3Results;

  const TutorialChatState({
    this.currentStep = TutorialStep.intro,
    required this.chat,
    this.currentRound,
    this.consensusItems = const [],
    this.propositions = const [],
    this.participants = const [],
    required this.myParticipant,
    this.myPropositions = const [],
    this.hasRated = false,
    this.hasStartedRating = false,
    this.previousRoundWinners = const [],
    this.isSoleWinner = false,
    this.consecutiveSoleWins = 0,
    this.selectedTemplate,
    this.customQuestion,
    this.userProposition1,
    this.userProposition2,
    this.round1Results = const [],
    this.round2Results = const [],
    this.round3Results = const [],
  });

  /// Whether the current step is a chat tour step
  bool get isChatTourStep =>
      currentStep.index >= TutorialStep.chatTourTitle.index &&
      currentStep.index <= TutorialStep.chatTourProposing.index;

  /// Zero-based index within the chat tour (0..4)
  int get chatTourStepIndex =>
      currentStep.index - TutorialStep.chatTourTitle.index;

  /// Total number of chat tour steps
  static const int chatTourTotalSteps = 4;

  /// Get the user's current proposition based on round
  String? get currentUserProposition {
    final roundNum = currentRound?.customId ?? 1;
    if (roundNum == 1) return userProposition1;
    if (roundNum >= 2) return userProposition2;
    return null;
  }

  /// Whether user is the winner (for display purposes)
  bool get isUserWinner {
    if (previousRoundWinners.isEmpty) return false;
    final winnerContent = previousRoundWinners.first.content;
    return winnerContent == userProposition2;
  }

  TutorialChatState copyWith({
    TutorialStep? currentStep,
    Chat? chat,
    Round? currentRound,
    List<Proposition>? consensusItems,
    List<Proposition>? propositions,
    List<Participant>? participants,
    Participant? myParticipant,
    List<Proposition>? myPropositions,
    bool? hasRated,
    bool? hasStartedRating,
    List<RoundWinner>? previousRoundWinners,
    bool? isSoleWinner,
    int? consecutiveSoleWins,
    String? selectedTemplate,
    String? customQuestion,
    String? userProposition1,
    String? userProposition2,
    List<Proposition>? round1Results,
    List<Proposition>? round2Results,
    List<Proposition>? round3Results,
  }) {
    return TutorialChatState(
      currentStep: currentStep ?? this.currentStep,
      chat: chat ?? this.chat,
      currentRound: currentRound ?? this.currentRound,
      consensusItems: consensusItems ?? this.consensusItems,
      propositions: propositions ?? this.propositions,
      participants: participants ?? this.participants,
      myParticipant: myParticipant ?? this.myParticipant,
      myPropositions: myPropositions ?? this.myPropositions,
      hasRated: hasRated ?? this.hasRated,
      hasStartedRating: hasStartedRating ?? this.hasStartedRating,
      previousRoundWinners: previousRoundWinners ?? this.previousRoundWinners,
      isSoleWinner: isSoleWinner ?? this.isSoleWinner,
      consecutiveSoleWins: consecutiveSoleWins ?? this.consecutiveSoleWins,
      selectedTemplate: selectedTemplate ?? this.selectedTemplate,
      customQuestion: customQuestion ?? this.customQuestion,
      userProposition1: userProposition1 ?? this.userProposition1,
      userProposition2: userProposition2 ?? this.userProposition2,
      round1Results: round1Results ?? this.round1Results,
      round2Results: round2Results ?? this.round2Results,
      round3Results: round3Results ?? this.round3Results,
    );
  }

  @override
  List<Object?> get props => [
        currentStep,
        chat,
        currentRound,
        consensusItems,
        propositions,
        participants,
        myParticipant,
        myPropositions,
        hasRated,
        hasStartedRating,
        previousRoundWinners,
        isSoleWinner,
        consecutiveSoleWins,
        selectedTemplate,
        customQuestion,
        userProposition1,
        userProposition2,
        round1Results,
        round2Results,
        round3Results,
      ];
}

/// Legacy state for backwards compatibility with existing tests
class TutorialState extends Equatable {
  final TutorialStep currentStep;
  final int currentRound;
  final String? userProposition1;
  final String? userProposition2;
  final String? currentWinnerContent;
  final bool isUserWinner;

  const TutorialState({
    this.currentStep = TutorialStep.intro,
    this.currentRound = 1,
    this.userProposition1,
    this.userProposition2,
    this.currentWinnerContent,
    this.isUserWinner = false,
  });

  String? get currentUserProposition {
    if (currentRound == 1) return userProposition1;
    if (currentRound >= 2) return userProposition2;
    return null;
  }

  bool get hasSubmittedCurrentRound {
    if (currentRound == 1) return userProposition1 != null;
    if (currentRound == 2) return userProposition2 != null;
    return true;
  }

  TutorialState copyWith({
    TutorialStep? currentStep,
    int? currentRound,
    String? userProposition1,
    String? userProposition2,
    String? currentWinnerContent,
    bool? isUserWinner,
  }) {
    return TutorialState(
      currentStep: currentStep ?? this.currentStep,
      currentRound: currentRound ?? this.currentRound,
      userProposition1: userProposition1 ?? this.userProposition1,
      userProposition2: userProposition2 ?? this.userProposition2,
      currentWinnerContent: currentWinnerContent ?? this.currentWinnerContent,
      isUserWinner: isUserWinner ?? this.isUserWinner,
    );
  }

  @override
  List<Object?> get props => [
        currentStep,
        currentRound,
        userProposition1,
        userProposition2,
        currentWinnerContent,
        isUserWinner,
      ];
}
