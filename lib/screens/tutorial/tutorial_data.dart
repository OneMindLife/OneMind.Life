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

  static const templates = <String, TutorialTemplate>{
    'family': TutorialTemplate(
      key: 'family',
      nameKey: 'tutorialTemplateFamily',
      descriptionKey: 'tutorialTemplateFamilyDesc',
      icon: Icons.family_restroom,
      question: 'Where should we go on vacation?',
      chatName: 'Family',
      round1Props: ['Beach Resort', 'Mountain Cabin', 'City Trip'],
      round1Winner: 'Beach Resort',
      round2Props: ['Road Trip', 'Camping Adventure', 'Beach Resort'],
      round3Props: ['Cruise', 'Theme Park', 'Cultural Exchange'],
    ),
    'community': TutorialTemplate(
      key: 'community',
      nameKey: 'tutorialTemplateCommunity',
      descriptionKey: 'tutorialTemplateCommunityDesc',
      icon: Icons.location_city,
      question: 'What should our neighborhood do together?',
      chatName: 'Community',
      round1Props: ['Block Party', 'Community Garden', 'Neighborhood Watch'],
      round1Winner: 'Community Garden',
      round2Props: ['Tool Library', 'Mutual Aid Fund', 'Community Garden'],
      round3Props: ['Free Little Library', 'Street Mural', 'Skill-Share Night'],
    ),
    'workplace': TutorialTemplate(
      key: 'workplace',
      nameKey: 'tutorialTemplateWorkplace',
      descriptionKey: 'tutorialTemplateWorkplaceDesc',
      icon: Icons.business,
      question: 'What should our team focus on?',
      chatName: 'Workplace',
      round1Props: ['Flexible Hours', 'Mental Health Support', 'Team Building'],
      round1Winner: 'Mental Health Support',
      round2Props: ['Skills Training', 'Open Communication', 'Mental Health Support'],
      round3Props: ['Fair Compensation', 'Work-Life Balance', 'Innovation Time'],
    ),
    'government': TutorialTemplate(
      key: 'government',
      nameKey: 'tutorialTemplateGovernment',
      descriptionKey: 'tutorialTemplateGovernmentDesc',
      icon: Icons.account_balance,
      question: 'How should we spend the city budget?',
      chatName: 'City Budget',
      round1Props: ['Public Transportation', 'School Funding', 'Emergency Services'],
      round1Winner: 'Emergency Services',
      round2Props: ['Road Repairs', 'Public Health', 'Emergency Services'],
      round3Props: ['Affordable Housing', 'Small Business Grants', 'Parks & Recreation'],
    ),
    'world': TutorialTemplate(
      key: 'world',
      nameKey: 'tutorialTemplateWorld',
      descriptionKey: 'tutorialTemplateWorldDesc',
      icon: Icons.public,
      question: 'What global issue matters most?',
      chatName: 'Global Issues',
      round1Props: ['Climate Change', 'Global Poverty', 'AI Governance'],
      round1Winner: 'Climate Change',
      round2Props: ['Pandemic Preparedness', 'Nuclear Disarmament', 'Climate Change'],
      round3Props: ['Ocean Conservation', 'Digital Rights', 'Space Cooperation'],
    ),
    'personal': TutorialTemplate(
      key: 'personal',
      nameKey: 'tutorialTemplatePersonal',
      descriptionKey: 'tutorialTemplatePersonalDesc',
      icon: Icons.person,
      question: 'What should I do after graduation?',
      chatName: 'Personal Decision',
      round1Props: ['Travel Abroad', 'Start a Business', 'Graduate School'],
      round1Winner: 'Graduate School',
      round2Props: ['Get a Job First', 'Take a Gap Year', 'Graduate School'],
      round3Props: ['Freelance', 'Move to a New City', 'Volunteer Program'],
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
    return templates[key] ?? templates['classic']!;
  }

  /// Translate a template question using l10n description keys.
  static String translateQuestion(String? templateKey, dynamic l10n) {
    switch (templateKey) {
      case 'personal':
        return l10n.tutorialTemplatePersonalDesc;
      case 'family':
        return l10n.tutorialTemplateFamilyDesc;
      case 'community':
        return l10n.tutorialTemplateCommunityDesc;
      case 'workplace':
        return l10n.tutorialTemplateWorkplaceDesc;
      case 'government':
        return l10n.tutorialTemplateGovernmentDesc;
      case 'world':
        return l10n.tutorialTemplateWorldDesc;
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
    // Classic
    'Success': (l10n) => l10n.tutorialPropSuccess,
    'Adventure': (l10n) => l10n.tutorialPropAdventure,
    'Growth': (l10n) => l10n.tutorialPropGrowth,
    'Harmony': (l10n) => l10n.tutorialPropHarmony,
    'Innovation': (l10n) => l10n.tutorialPropInnovation,
    'Freedom': (l10n) => l10n.tutorialPropFreedom,
    'Security': (l10n) => l10n.tutorialPropSecurity,
    'Stability': (l10n) => l10n.tutorialPropStability,
    // Personal
    'Travel Abroad': (l10n) => l10n.tutorialPropTravelAbroad,
    'Start a Business': (l10n) => l10n.tutorialPropStartABusiness,
    'Graduate School': (l10n) => l10n.tutorialPropGraduateSchool,
    'Get a Job First': (l10n) => l10n.tutorialPropGetAJobFirst,
    'Take a Gap Year': (l10n) => l10n.tutorialPropTakeAGapYear,
    'Freelance': (l10n) => l10n.tutorialPropFreelance,
    'Move to a New City': (l10n) => l10n.tutorialPropMoveToANewCity,
    'Volunteer Program': (l10n) => l10n.tutorialPropVolunteerProgram,
    // Family
    'Beach Resort': (l10n) => l10n.tutorialPropBeachResort,
    'Mountain Cabin': (l10n) => l10n.tutorialPropMountainCabin,
    'City Trip': (l10n) => l10n.tutorialPropCityTrip,
    'Road Trip': (l10n) => l10n.tutorialPropRoadTrip,
    'Camping Adventure': (l10n) => l10n.tutorialPropCampingAdventure,
    'Cruise': (l10n) => l10n.tutorialPropCruise,
    'Theme Park': (l10n) => l10n.tutorialPropThemePark,
    'Cultural Exchange': (l10n) => l10n.tutorialPropCulturalExchange,
    // Community
    'Block Party': (l10n) => l10n.tutorialPropBlockParty,
    'Community Garden': (l10n) => l10n.tutorialPropCommunityGarden,
    'Neighborhood Watch': (l10n) => l10n.tutorialPropNeighborhoodWatch,
    'Tool Library': (l10n) => l10n.tutorialPropToolLibrary,
    'Mutual Aid Fund': (l10n) => l10n.tutorialPropMutualAidFund,
    'Free Little Library': (l10n) => l10n.tutorialPropFreeLittleLibrary,
    'Street Mural': (l10n) => l10n.tutorialPropStreetMural,
    'Skill-Share Night': (l10n) => l10n.tutorialPropSkillShareNight,
    // Workplace
    'Flexible Hours': (l10n) => l10n.tutorialPropFlexibleHours,
    'Mental Health Support': (l10n) => l10n.tutorialPropMentalHealthSupport,
    'Team Building': (l10n) => l10n.tutorialPropTeamBuilding,
    'Skills Training': (l10n) => l10n.tutorialPropSkillsTraining,
    'Open Communication': (l10n) => l10n.tutorialPropOpenCommunication,
    'Fair Compensation': (l10n) => l10n.tutorialPropFairCompensation,
    'Work-Life Balance': (l10n) => l10n.tutorialPropWorkLifeBalance,
    'Innovation Time': (l10n) => l10n.tutorialPropInnovationTime,
    // Government
    'Public Transportation': (l10n) => l10n.tutorialPropPublicTransportation,
    'School Funding': (l10n) => l10n.tutorialPropSchoolFunding,
    'Emergency Services': (l10n) => l10n.tutorialPropEmergencyServices,
    'Road Repairs': (l10n) => l10n.tutorialPropRoadRepairs,
    'Public Health': (l10n) => l10n.tutorialPropPublicHealth,
    'Affordable Housing': (l10n) => l10n.tutorialPropAffordableHousing,
    'Small Business Grants': (l10n) => l10n.tutorialPropSmallBusinessGrants,
    'Parks & Recreation': (l10n) => l10n.tutorialPropParksAndRecreation,
    // World
    'Climate Change': (l10n) => l10n.tutorialPropClimateChange,
    'Global Poverty': (l10n) => l10n.tutorialPropGlobalPoverty,
    'AI Governance': (l10n) => l10n.tutorialPropAiGovernance,
    'Pandemic Preparedness': (l10n) => l10n.tutorialPropPandemicPreparedness,
    'Nuclear Disarmament': (l10n) => l10n.tutorialPropNuclearDisarmament,
    'Ocean Conservation': (l10n) => l10n.tutorialPropOceanConservation,
    'Digital Rights': (l10n) => l10n.tutorialPropDigitalRights,
    'Space Cooperation': (l10n) => l10n.tutorialPropSpaceCooperation,
  };
}

/// Hardcoded data for the interactive tutorial
class TutorialData {
  TutorialData._();

  // Default tutorial question (classic template / fallback)
  static const String question = 'What do we value?';
  static const String chatName = 'Values';
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
  static const round1PropositionContents = ['Success', 'Adventure', 'Growth'];

  /// Round 2 propositions (Success carried + 2 new + user's = 4 total)
  static const round2PropositionContents = [
    'Harmony',
    'Innovation',
    'Success'
  ];

  /// Round 3 propositions (user's carried + 3 new = 4 total)
  static const round3PropositionContents = ['Freedom', 'Security', 'Stability'];

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

  /// Round 1 winner (always "Success" for classic template)
  static const round1WinnerContent = 'Success';

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
  /// R1 winner is carried forward, user's new idea beats it.
  static List<Proposition> round2ResultsWithRatings(String userProposition, {String? templateKey}) {
    final template = TutorialTemplate.getTemplate(templateKey);
    final props = template.round2Props;
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
        content: props[2], // R1 winner carried forward (now last)
        finalRating: 67.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -202,
        roundId: -2,
        participantId: -3, // Bob
        content: props[0],
        finalRating: 33.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -203,
        roundId: -2,
        participantId: -4, // Carol
        content: props[1],
        finalRating: 0.0,
        createdAt: DateTime.now(),
      ),
    ];
  }

  /// Round 3 results - user's proposition wins again = CONSENSUS!
  /// User's idea carried forward and wins again.
  static List<Proposition> round3ResultsWithRatings(String userProposition, {String? templateKey}) {
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
      Proposition(
        id: -301,
        roundId: -3,
        participantId: -2, // Alice
        content: props[0],
        finalRating: 67.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -302,
        roundId: -3,
        participantId: -3, // Bob
        content: props[1],
        finalRating: 33.0,
        createdAt: DateTime.now(),
      ),
      Proposition(
        id: -303,
        roundId: -3,
        participantId: -4, // Carol
        content: props[2],
        finalRating: 0.0,
        createdAt: DateTime.now(),
      ),
    ];
  }
}
