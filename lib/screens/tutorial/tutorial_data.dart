import '../../models/models.dart';
import 'models/tutorial_state.dart';

/// Hardcoded data for the interactive tutorial
class TutorialData {
  TutorialData._();

  // Tutorial question
  static const String question = 'What do we value?';
  static const String chatName = 'Tutorial: Values';
  static const String initialMessage = question;

  // === MOCK MODELS ===

  /// Tutorial chat (fake Chat object)
  static Chat get tutorialChat => Chat(
        id: -1, // Negative ID to indicate tutorial
        name: chatName,
        initialMessage: initialMessage,
        accessMethod: AccessMethod.code,
        requireAuth: false,
        requireApproval: false,
        isActive: true,
        isOfficial: false,
        startMode: StartMode.manual,
        proposingDurationSeconds: 300,
        ratingDurationSeconds: 300,
        proposingMinimum: 2,
        ratingMinimum: 2,
        enableAiParticipant: false,
        confirmationRoundsRequired: 2,
        showPreviousResults: false,
        propositionsPerUser: 1,
        createdAt: DateTime.now(),
        inviteCode: 'ABC123',
      );

  /// Tutorial participant (the user)
  static Participant get tutorialParticipant => Participant(
        id: -1,
        chatId: -1,
        userId: 'tutorial-user',
        displayName: 'You',
        isHost: true,
        isAuthenticated: false,
        status: ParticipantStatus.active,
        createdAt: DateTime.now(),
      );

  /// Other tutorial participants (fake)
  static List<Participant> get otherParticipants => [
        Participant(
          id: -2,
          chatId: -1,
          userId: 'tutorial-alice',
          displayName: 'Alice',
          isHost: false,
          isAuthenticated: false,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        ),
        Participant(
          id: -3,
          chatId: -1,
          userId: 'tutorial-bob',
          displayName: 'Bob',
          isHost: false,
          isAuthenticated: false,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        ),
        Participant(
          id: -4,
          chatId: -1,
          userId: 'tutorial-carol',
          displayName: 'Carol',
          isHost: false,
          isAuthenticated: false,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        ),
      ];

  /// All participants including the user
  static List<Participant> get allParticipants =>
      [tutorialParticipant, ...otherParticipants];

  // === ROUNDS ===

  static Round round1({RoundPhase phase = RoundPhase.proposing}) => Round(
        id: -1,
        cycleId: -1,
        customId: 1,
        phase: phase,
        phaseStartedAt: DateTime.now(),
        phaseEndsAt: phase == RoundPhase.waiting
            ? null
            : DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

  static Round round2({RoundPhase phase = RoundPhase.proposing}) => Round(
        id: -2,
        cycleId: -1,
        customId: 2,
        phase: phase,
        phaseStartedAt: DateTime.now(),
        phaseEndsAt: phase == RoundPhase.waiting
            ? null
            : DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

  static Round round3({RoundPhase phase = RoundPhase.proposing}) => Round(
        id: -3,
        cycleId: -1,
        customId: 3,
        phase: phase,
        phaseStartedAt: DateTime.now(),
        phaseEndsAt: phase == RoundPhase.waiting
            ? null
            : DateTime.now().add(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

  // === PROPOSITIONS (for rating screen) ===

  /// Round 1 propositions (3 visible + user's hidden = 4 total)
  static const round1PropositionContents = ['Success', 'Adventure', 'Growth'];

  /// Round 2 propositions (Success carried + 2 new + user's = 4 total)
  static const round2PropositionContents = [
    'Success',
    'Harmony',
    'Innovation'
  ];

  /// Round 3 propositions (user's carried + 3 new = 4 total)
  static const round3PropositionContents = ['Freedom', 'Security', 'Stability'];

  /// Create Proposition objects for rating
  static List<Proposition> createPropositions(
    List<String> contents, {
    int roundId = -1,
    String? userProposition,
    bool includeUserProp = true,
  }) {
    final props = <Proposition>[];
    int id = -100;

    // Add other propositions
    for (final content in contents) {
      props.add(Proposition(
        id: id--,
        roundId: roundId,
        participantId: -2, // Alice
        content: content,
        createdAt: DateTime.now(),
      ));
    }

    // Add user's proposition if provided
    if (includeUserProp && userProposition != null) {
      props.add(Proposition(
        id: id--,
        roundId: roundId,
        participantId: -1, // User
        content: userProposition,
        createdAt: DateTime.now(),
      ));
    }

    return props;
  }

  /// Convert propositions to format expected by RatingWidget
  static List<Map<String, dynamic>> propositionsForRating(
      List<Proposition> props) {
    return props
        .map((p) => {
              'id': p.id,
              'content': p.content,
            })
        .toList();
  }

  // === WINNERS ===

  /// Round 1 winner (always "Success")
  static const round1WinnerContent = 'Success';

  static RoundWinner round1Winner() => RoundWinner(
        id: -1,
        roundId: -1,
        propositionId: -100,
        rank: 1,
        createdAt: DateTime.now(),
        content: round1WinnerContent,
      );

  /// Round 2 winner (user's proposition)
  static RoundWinner round2Winner(String userProposition) => RoundWinner(
        id: -2,
        roundId: -2,
        propositionId: -200,
        rank: 1,
        createdAt: DateTime.now(),
        content: userProposition,
      );

  /// Round 3 winner (user's proposition again = CONSENSUS!)
  static RoundWinner round3Winner(String userProposition) => RoundWinner(
        id: -3,
        roundId: -3,
        propositionId: -300,
        rank: 1,
        createdAt: DateTime.now(),
        content: userProposition,
      );

  /// Create consensus proposition from user's winning idea
  static Proposition consensusProposition(String content) => Proposition(
        id: -999,
        roundId: -3,
        participantId: -1,
        content: content,
        createdAt: DateTime.now(),
      );

  // === LEGACY: Tutorial Propositions (for backwards compat) ===

  static const round1Propositions = [
    TutorialProposition(id: 'r1_1', content: 'Success'),
    TutorialProposition(id: 'r1_2', content: 'Adventure'),
    TutorialProposition(id: 'r1_3', content: 'Growth'),
  ];

  static const round2Propositions = [
    TutorialProposition(
      id: 'r2_1',
      content: 'Success',
      isCarriedForward: true,
    ),
    TutorialProposition(id: 'r2_2', content: 'Harmony'),
    TutorialProposition(id: 'r2_3', content: 'Innovation'),
  ];

  static const round3Propositions = [
    TutorialProposition(id: 'r3_1', content: 'Freedom'),
    TutorialProposition(id: 'r3_2', content: 'Security'),
    TutorialProposition(id: 'r3_3', content: 'Stability'),
  ];

  // === MESSAGES ===

  static const round1ResultMessage =
      "The group chose 'Success'. But is that the best we can do?";

  static const round2Prompt =
      "Seeing 'Success' as the group's current answer - what do you think we REALLY value?";

  static String round2ResultMessage(String userProp) =>
      "Your idea '$userProp' is now leading! One more round to confirm consensus.";

  static String round3CarryForwardMessage(String userProp) =>
      "Your winning idea '$userProp' automatically advances to Round 3. If it wins again, consensus is reached!";

  static String round3ConsensusMessage(String userProp) =>
      "The group has reached consensus on '$userProp'! This idea won two consecutive rounds.";

  /// Demo invite code for share screen
  static const String demoInviteCode = 'ABC123';

  /// Round 1 results with predetermined final ratings for grid display.
  /// Shows user why "Success" won and where their proposition landed.
  /// Ratings are normalized so the highest is 100 and lowest is 0.
  static List<Proposition> round1ResultsWithRatings(String userProposition) {
    return [
      Proposition(
        id: -100,
        roundId: -1,
        participantId: -2, // Alice
        content: 'Success',
        finalRating: 100.0, // Winner - normalized to top
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -101,
        roundId: -1,
        participantId: -3, // Bob
        content: 'Adventure',
        finalRating: 58.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -102,
        roundId: -1,
        participantId: -4, // Carol
        content: 'Growth',
        finalRating: 33.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -103,
        roundId: -1,
        participantId: -1, // User
        content: userProposition,
        finalRating: 0.0, // Normalized to bottom
        createdAt: DateTime.now(),
      ),
    ];
  }

  /// Round 2 results - user's proposition wins!
  /// Success is carried forward, user's new idea beats it.
  static List<Proposition> round2ResultsWithRatings(String userProposition) {
    return [
      Proposition(
        id: -200,
        roundId: -2,
        participantId: -1, // User
        content: userProposition,
        finalRating: 100.0, // Winner - user's idea wins!
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -201,
        roundId: -2,
        participantId: -2, // Alice (carried forward)
        content: 'Success',
        finalRating: 67.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -202,
        roundId: -2,
        participantId: -3, // Bob
        content: 'Harmony',
        finalRating: 33.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -203,
        roundId: -2,
        participantId: -4, // Carol
        content: 'Innovation',
        finalRating: 0.0,
        createdAt: DateTime.now(),
      ),
    ];
  }

  /// Round 3 results - user's proposition wins again = CONSENSUS!
  /// User's idea carried forward and wins again.
  static List<Proposition> round3ResultsWithRatings(String userProposition) {
    return [
      Proposition(
        id: -300,
        roundId: -3,
        participantId: -1, // User (carried forward)
        content: userProposition,
        finalRating: 100.0, // Winner again - CONSENSUS!
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -301,
        roundId: -3,
        participantId: -2, // Alice
        content: 'Freedom',
        finalRating: 67.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -302,
        roundId: -3,
        participantId: -3, // Bob
        content: 'Security',
        finalRating: 33.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -303,
        roundId: -3,
        participantId: -4, // Carol
        content: 'Stability',
        finalRating: 0.0,
        createdAt: DateTime.now(),
      ),
    ];
  }
}
