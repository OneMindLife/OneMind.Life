import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'models/tutorial_state.dart';

/// Template definition for tutorial topics
class TutorialTemplate {
  final String key;
  final String nameKey;
  final String descriptionKey;
  final IconData icon;
  final String question;
  final String chatName;
  final List<String> round1Props;
  final String round1Winner;
  final List<String> round2Props;
  final List<String> round3Props;

  const TutorialTemplate({
    required this.key,
    required this.nameKey,
    required this.descriptionKey,
    required this.icon,
    required this.question,
    required this.chatName,
    required this.round1Props,
    required this.round1Winner,
    required this.round2Props,
    required this.round3Props,
  });

  /// Default template key used for the tutorial.
  static const defaultKey = 'saturday';

  static const templates = <String, TutorialTemplate>{
    'saturday': TutorialTemplate(
      key: 'saturday',
      nameKey: 'tutorialTemplateSaturday',
      descriptionKey: 'tutorialTemplateSaturdayDesc',
      icon: Icons.calendar_today,
      question: "What's the best way to spend a free Saturday?",
      chatName: 'Saturday Plans',
      round1Props: ['Movie Night', 'Cook-off', 'Board Games'],
      round1Winner: 'Movie Night',
      round2Props: ['Karaoke', 'Potluck Dinner', 'Movie Night', 'Board Games'],
      round3Props: ['DIY Craft Night', 'Trivia Night', 'Video Game Tournament'],
    ),
    'classic': TutorialTemplate(
      key: 'classic',
      nameKey: 'tutorialTemplateCustom',
      descriptionKey: 'tutorialTemplateCustomDesc',
      icon: Icons.edit_note,
      question: 'What do we value?',
      chatName: 'Values',
      round1Props: ['Success', 'Adventure', 'Growth'],
      round1Winner: 'Success',
      round2Props: ['Harmony', 'Innovation', 'Success'],
      round3Props: ['Freedom', 'Security', 'Stability'],
    ),
  };

  static TutorialTemplate getTemplate(String? key) {
    return templates[key] ?? templates[defaultKey]!;
  }

  /// Translate a template question using l10n description keys.
  static String translateQuestion(String? templateKey, dynamic l10n) {
    switch (templateKey) {
      case 'saturday':
        return l10n.tutorialTemplateSaturdayDesc;
      default:
        return l10n.tutorialQuestion;
    }
  }

  /// Translate a proposition content string using l10n.
  /// Returns the translated string if a key exists, otherwise the original.
  static String translateProp(String content, dynamic l10n) {
    // Map English content → l10n getter name
    return _propTranslations[content]?.call(l10n) ?? content;
  }

  /// Translate a list of proposition content strings.
  static List<String> translateProps(List<String> contents, dynamic l10n) {
    return contents.map((c) => translateProp(c, l10n)).toList();
  }

  static final Map<String, String Function(dynamic)> _propTranslations = {
    // Saturday
    'Movie Night': (l10n) => l10n.tutorialPropMovieNight,
    'Cook-off': (l10n) => l10n.tutorialPropCookOff,
    'Board Games': (l10n) => l10n.tutorialPropBoardGames,
    'Karaoke': (l10n) => l10n.tutorialPropKaraoke,
    'Potluck Dinner': (l10n) => l10n.tutorialPropPotluckDinner,
    'DIY Craft Night': (l10n) => l10n.tutorialPropDiyCraftNight,
    'Trivia Night': (l10n) => l10n.tutorialPropTriviaNight,
    'Video Game Tournament': (l10n) => l10n.tutorialPropVideoGameTournament,
    // Classic (fallback)
    'Success': (l10n) => l10n.tutorialPropSuccess,
    'Adventure': (l10n) => l10n.tutorialPropAdventure,
    'Growth': (l10n) => l10n.tutorialPropGrowth,
    'Harmony': (l10n) => l10n.tutorialPropHarmony,
    'Innovation': (l10n) => l10n.tutorialPropInnovation,
    'Freedom': (l10n) => l10n.tutorialPropFreedom,
    'Security': (l10n) => l10n.tutorialPropSecurity,
    'Stability': (l10n) => l10n.tutorialPropStability,
  };
}

/// Hardcoded data for the interactive tutorial
class TutorialData {
  TutorialData._();

  // Default tutorial question
  static const String question = "What's the best way to spend a free Saturday?";
  static const String chatName = 'Saturday Plans';
  static const String initialMessage = question;

  /// Get question for a given template key (falls back to classic)
  static String questionForTemplate(String? templateKey) {
    return TutorialTemplate.getTemplate(templateKey).question;
  }

  /// Get chat name for a given template key
  static String chatNameForTemplate(String? templateKey) {
    return TutorialTemplate.getTemplate(templateKey).chatName;
  }

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
          userId: 'tutorial-alex',
          displayName: 'Alex',
          isHost: false,
          isAuthenticated: false,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        ),
        Participant(
          id: -3,
          chatId: -1,
          userId: 'tutorial-sam',
          displayName: 'Sam',
          isHost: false,
          isAuthenticated: false,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        ),
        Participant(
          id: -4,
          chatId: -1,
          userId: 'tutorial-jordan',
          displayName: 'Jordan',
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

  /// Tutorial timer: 5 minutes from now. If it expires, it just stays at 0.
  static DateTime _tutorialDeadline() =>
      DateTime.now().add(const Duration(minutes: 5));

  static Round round1({RoundPhase phase = RoundPhase.proposing}) => Round(
        id: -1,
        cycleId: -1,
        customId: 1,
        phase: phase,
        phaseStartedAt: DateTime.now(),
        phaseEndsAt: _tutorialDeadline(),
        createdAt: DateTime.now(),
      );

  static Round round2({RoundPhase phase = RoundPhase.proposing}) => Round(
        id: -2,
        cycleId: -1,
        customId: 2,
        phase: phase,
        phaseStartedAt: DateTime.now(),
        phaseEndsAt: _tutorialDeadline(),
        createdAt: DateTime.now(),
      );

  static Round round3({RoundPhase phase = RoundPhase.proposing}) => Round(
        id: -3,
        cycleId: -1,
        customId: 3,
        phase: phase,
        phaseStartedAt: DateTime.now(),
        phaseEndsAt: _tutorialDeadline(),
        createdAt: DateTime.now(),
      );

  // === PROPOSITIONS (for rating screen) ===

  /// Round 1 propositions (3 visible + user's hidden = 4 total)
  static const round1PropositionContents = ['Movie Night', 'Cook-off', 'Board Games'];

  /// Round 2 propositions (3 new NPC + Movie Night carried + user's = 5 total)
  static const round2PropositionContents = [
    'Karaoke',
    'Potluck Dinner',
    'Movie Night',
    'Board Games'
  ];

  /// Round 3 propositions (user's carried + 3 new = 4 total)
  static const round3PropositionContents = ['DIY Craft Night', 'Trivia Night', 'Video Game Tournament'];

  /// Template-aware proposition getters
  static List<String> round1Props(String? templateKey) =>
      TutorialTemplate.getTemplate(templateKey).round1Props;

  static List<String> round2Props(String? templateKey) =>
      TutorialTemplate.getTemplate(templateKey).round2Props;

  static List<String> round3Props(String? templateKey) =>
      TutorialTemplate.getTemplate(templateKey).round3Props;

  /// Create Proposition objects for rating
  static List<Proposition> createPropositions(
    List<String> contents, {
    int roundId = -1,
    String? userProposition,
    bool includeUserProp = true,
    int? carriedPropIndex,
    int? carriedFromId,
  }) {
    final props = <Proposition>[];
    int id = -100;

    // Add other propositions
    for (int i = 0; i < contents.length; i++) {
      props.add(Proposition(
        id: id--,
        roundId: roundId,
        participantId: -2, // Alice
        content: contents[i],
        carriedFromId: (carriedPropIndex == i) ? carriedFromId : null,
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

  /// Round 1 winner
  static const round1WinnerContent = 'Movie Night';

  /// Template-aware round 1 winner content
  static String round1WinnerForTemplate(String? templateKey) =>
      TutorialTemplate.getTemplate(templateKey).round1Winner;

  static RoundWinner round1Winner({String? templateKey}) => RoundWinner(
        id: -1,
        roundId: -1,
        propositionId: -100,
        rank: 1,
        createdAt: DateTime.now(),
        content: round1WinnerForTemplate(templateKey),
      );

  /// Round 1 tied winner (second winner for testing tie display)
  static RoundWinner round1TiedWinner({String? templateKey}) {
    final template = TutorialTemplate.getTemplate(templateKey);
    // Use the second proposition from round 1 as the tied winner
    final tiedContent = template.round1Props.length > 1
        ? template.round1Props[1]
        : template.round1Props[0];
    return RoundWinner(
      id: -10,
      roundId: -1,
      propositionId: -101,
      rank: 1,
      createdAt: DateTime.now(),
      content: tiedContent,
    );
  }

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
    TutorialProposition(id: 'r1_1', content: 'Movie Night'),
    TutorialProposition(id: 'r1_2', content: 'Cook-off'),
    TutorialProposition(id: 'r1_3', content: 'Board Games'),
  ];

  static const round2Propositions = [
    TutorialProposition(id: 'r2_1', content: 'Karaoke'),
    TutorialProposition(id: 'r2_2', content: 'Potluck Dinner'),
    TutorialProposition(
      id: 'r2_3',
      content: 'Movie Night',
      isCarriedForward: true,
    ),
    TutorialProposition(id: 'r2_4', content: 'Board Games'),
  ];

  static const round3Propositions = [
    TutorialProposition(id: 'r3_1', content: 'DIY Craft Night'),
    TutorialProposition(id: 'r3_2', content: 'Trivia Night'),
    TutorialProposition(id: 'r3_3', content: 'Video Game Tournament'),
  ];

  // === MESSAGES ===

  static const round1ResultMessage =
      "The group chose 'Movie Night'. But can you come up with something better?";

  static const round2Prompt =
      "'Movie Night' is the current winner — what's your best idea to beat it?";

  static String round2ResultMessage(String userProp) =>
      "Your idea '$userProp' is now leading! One more round to confirm convergence.";

  static String round3CarryForwardMessage(String userProp) =>
      "Your winning idea '$userProp' automatically advances to Round 3. If it wins again, convergence is reached!";

  static String round3ConsensusMessage(String userProp) =>
      "The group has reached convergence on '$userProp'! This idea won two consecutive rounds.";

  /// Demo invite code for share screen
  static const String demoInviteCode = 'ABC123';

  /// Round 1 results with predetermined final ratings for grid display.
  /// Shows user why the R1 winner won and where their proposition landed.
  /// Ratings are normalized so the highest is 100 and lowest is 0.
  static List<Proposition> round1ResultsWithRatings(String userProposition, {String? templateKey}) {
    final template = TutorialTemplate.getTemplate(templateKey);
    final props = template.round1Props;
    final winner = template.round1Winner;

    // Assign ratings so the declared winner gets 100, others get descending scores
    final ratings = <String, double>{};
    // Non-winner props get descending scores below 100
    final nonWinnerScores = [58.0, 33.0];
    var scoreIndex = 0;
    for (final prop in props) {
      if (prop == winner) {
        ratings[prop] = 100.0;
      } else {
        ratings[prop] = scoreIndex < nonWinnerScores.length
            ? nonWinnerScores[scoreIndex]
            : 10.0;
        scoreIndex++;
      }
    }

    final participantIds = [-2, -3, -4]; // Alice, Bob, Carol
    return [
      ...props.asMap().entries.map((entry) => Proposition(
        id: -100 - entry.key,
        roundId: -1,
        participantId: participantIds[entry.key],
        content: entry.value,
        finalRating: ratings[entry.value] ?? 0.0,
        createdAt: DateTime.now(),
      )),
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
  /// R1 winner is carried forward, 3 new NPC props, user's new idea beats all.
  static List<Proposition> round2ResultsWithRatings(String userProposition, {String? templateKey}) {
    final template = TutorialTemplate.getTemplate(templateKey);
    final props = template.round2Props;
    // props layout: [new0, new1, carried, new3]
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
        participantId: -2, // Alice (carried forward from R1)
        content: props[2], // R1 winner carried forward (Movie Night)
        finalRating: 75.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -202,
        roundId: -2,
        participantId: -3, // Bob
        content: props[0],
        finalRating: 50.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -203,
        roundId: -2,
        participantId: -4, // Carol
        content: props[1],
        finalRating: 25.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -204,
        roundId: -2,
        participantId: -2, // Alice (new submission)
        content: props[3],
        finalRating: 0.0,
        createdAt: DateTime.now(),
      ),
    ];
  }

  /// Round 3 results - user's proposition wins again = CONSENSUS!
  /// User's idea carried forward and wins again.
  static List<Proposition> round3ResultsWithRatings(String userProposition, {String? templateKey, String? userR3Proposition}) {
    final template = TutorialTemplate.getTemplate(templateKey);
    final props = template.round3Props;
    return [
      Proposition(
        id: -300,
        roundId: -3,
        participantId: -1, // User (carried forward)
        content: userProposition,
        finalRating: 100.0, // Winner again - CONSENSUS!
        createdAt: DateTime.now(),
      ),
      // User's R3 submission (if they submitted instead of skipping)
      if (userR3Proposition != null)
        Proposition(
          id: -304,
          roundId: -3,
          participantId: -1, // User (new R3 idea)
          content: userR3Proposition,
          finalRating: 75.0,
          createdAt: DateTime.now(),
        ),
      Proposition(
        id: -301,
        roundId: -3,
        participantId: -2, // Alice
        content: props[0],
        finalRating: userR3Proposition != null ? 50.0 : 67.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -302,
        roundId: -3,
        participantId: -3, // Bob
        content: props[1],
        finalRating: userR3Proposition != null ? 25.0 : 33.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -303,
        roundId: -3,
        participantId: -4, // Carol
        content: props[2],
        finalRating: userR3Proposition != null ? 0.0 : 0.0,
        createdAt: DateTime.now(),
      ),
    ];
  }
}
