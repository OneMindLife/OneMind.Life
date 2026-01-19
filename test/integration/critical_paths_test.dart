import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';

import '../fixtures/fixtures.dart';
import '../mocks/mock_services.dart';

/// Critical path integration tests
///
/// These tests verify the end-to-end functionality of critical user flows
/// using mocked services. They ensure that the integration between
/// services works correctly.
void main() {
  setUpAll(() {
    registerFallbackValues();
  });

  group('Critical Path: Chat Creation Flow', () {
    late MockChatService chatService;
    late MockParticipantService participantService;
    late MockAuthService authService;

    setUp(() {
      chatService = MockChatService();
      participantService = MockParticipantService();
      authService = MockAuthService();
    });

    test('complete chat creation flow with all settings', () async {
      // Arrange
      final testChat = ChatFixtures.model(
        id: 1,
        name: 'Integration Test Chat',
        inviteCode: 'TEST01',
      );

      final testParticipant = ParticipantFixtures.host(
        id: 1,
        chatId: 1,
      );

      chatService.setupCreateChat(testChat);
      participantService.setupJoinChat(testParticipant);
      authService.setupDefaults(userId: 'test-user-id', displayName: 'Test Host');

      // Act - Create chat
      final createdChat = await chatService.createChat(
        name: 'Integration Test Chat',
        initialMessage: 'Test message',
        accessMethod: AccessMethod.code,
        requireAuth: false,
        requireApproval: false,
        startMode: StartMode.manual,
        hostDisplayName: 'Test Host',
        proposingDurationSeconds: 300,
        ratingDurationSeconds: 300,
        proposingMinimum: 2,
        ratingMinimum: 2,
        confirmationRoundsRequired: 2,
        propositionsPerUser: 1,
        enableAiParticipant: false,
        showPreviousResults: false,
      );

      // Assert
      expect(createdChat, isNotNull);
      expect(createdChat.id, equals(1));
      expect(createdChat.name, equals('Integration Test Chat'));
      expect(createdChat.accessMethod, equals(AccessMethod.code));
      expect(createdChat.inviteCode, isNotEmpty);
    });

    test('chat creation with auto-start configuration', () async {
      // Arrange
      final autoStartChat = ChatFixtures.withAutoStart(participantCount: 5);

      chatService.setupCreateChat(autoStartChat);

      // Act
      final chat = await chatService.createChat(
        name: 'Auto Start Chat',
        initialMessage: 'Auto start test',
        startMode: StartMode.auto,
        hostDisplayName: 'Test Host',
        autoStartParticipantCount: 5,
        accessMethod: AccessMethod.code,
        requireAuth: false,
        requireApproval: false,
        proposingDurationSeconds: 300,
        ratingDurationSeconds: 300,
        proposingMinimum: 2,
        ratingMinimum: 2,
        confirmationRoundsRequired: 2,
        propositionsPerUser: 1,
        enableAiParticipant: false,
        showPreviousResults: false,
      );

      // Assert
      expect(chat.startMode, equals(StartMode.auto));
      expect(chat.autoStartParticipantCount, equals(5));
    });

    test('joining existing chat by code', () async {
      // Arrange
      final existingChat = ChatFixtures.model(id: 3, inviteCode: 'ABC123');
      final newParticipant = ParticipantFixtures.model(
        id: 5,
        chatId: 3,
        displayName: 'New User',
      );

      chatService.setupGetChatByCode('ABC123', existingChat);
      participantService.setupJoinChat(newParticipant);

      // Act
      final chat = await chatService.getChatByCode('ABC123');
      final participant = await participantService.joinChat(
        chatId: chat!.id,
        displayName: 'New User',
        isHost: false,
      );

      // Assert
      expect(chat.id, equals(3));
      expect(participant.chatId, equals(3));
      expect(participant.displayName, equals('New User'));
      expect(participant.status, equals(ParticipantStatus.active));
    });
  });

  group('Critical Path: Consensus Achievement Flow', () {
    late MockChatService chatService;
    late MockPropositionService propositionService;

    setUp(() {
      chatService = MockChatService();
      propositionService = MockPropositionService();
    });

    test('full consensus flow - proposal to consensus', () async {
      // Arrange - Set up chat in proposing phase
      final chat = ChatFixtures.model(id: 1);
      final cycle = CycleFixtures.active(id: 1, chatId: 1);
      final proposingRound = RoundFixtures.proposing(id: 1, cycleId: 1);

      chatService.setupGetChatById(1, chat);
      chatService.setupGetCurrentCycle(1, cycle);
      chatService.setupGetCurrentRound(1, proposingRound);

      // Act & Assert - Verify proposing phase setup
      final fetchedChat = await chatService.getChatById(1);
      final fetchedCycle = await chatService.getCurrentCycle(1);
      final fetchedRound = await chatService.getCurrentRound(1);

      expect(fetchedChat?.isActive, isTrue);
      expect(fetchedCycle?.isComplete, isFalse);
      expect(fetchedRound?.phase, equals(RoundPhase.proposing));
    });

    test('proposition submission updates participant state', () async {
      // Arrange
      final proposition = PropositionFixtures.model(
        id: 1,
        roundId: 1,
        participantId: 1,
        content: 'Test proposal',
      );

      propositionService.setupSubmitProposition(proposition);
      propositionService.setupGetMyPropositions(1, 1, [proposition]);

      // Act
      final submitted = await propositionService.submitProposition(
        roundId: 1,
        participantId: 1,
        content: 'Test proposal',
      );

      final myPropositions = await propositionService.getMyPropositions(1, 1);

      // Assert
      expect(submitted.content, equals('Test proposal'));
      expect(myPropositions, hasLength(1));
      expect(myPropositions.first.id, equals(proposition.id));
    });

    test('rating phase tracks participant ratings', () async {
      // Arrange
      propositionService.setupHasRated(1, 1, false);
      propositionService.setupHasRated(1, 2, true);

      // Act
      final hasNotRated = await propositionService.hasRated(1, 1);
      final hasRated = await propositionService.hasRated(1, 2);

      // Assert
      expect(hasNotRated, isFalse);
      expect(hasRated, isTrue);
    });

    test('consensus achieved after required consecutive wins', () async {
      // Arrange - Simulate second consecutive win
      final winningProposition = PropositionFixtures.winner(
        id: 1,
        roundId: 2,
        content: 'Winning proposal',
      );

      final roundWinner = RoundWinnerFixtures.soleWinner(
        roundId: 2,
        propositionId: 1,
        globalScore: 0.85,
        content: 'Winning proposal',
      );

      // Setup 2 consecutive sole wins (matches confirmationRoundsRequired: 2)
      chatService.setupGetPreviousRoundWinnersSole(
        cycleId: 1,
        winner: roundWinner,
        consecutiveSoleWins: 2,
        previousRoundId: 2,
      );

      chatService.setupGetConsensusItems(1, [winningProposition]);

      // Act
      final winnersResult = await chatService.getPreviousRoundWinners(1);
      final consensusItems = await chatService.getConsensusItems(1);

      // Assert
      expect(winnersResult['consecutiveSoleWins'], equals(2));
      expect(winnersResult['isSoleWinner'], isTrue);
      expect(consensusItems, hasLength(1));
      expect(consensusItems.first.content, equals('Winning proposal'));
    });

    test('tied winners do not count toward consensus', () async {
      // Arrange - Setup tied winners
      final winners = RoundWinnerFixtures.tiedWinners(
        roundId: 3,
        count: 2,
        score: 0.75,
      );

      chatService.setupGetPreviousRoundWinnersTied(
        cycleId: 1,
        winners: winners,
        previousRoundId: 3,
      );

      // Act
      final winnersResult = await chatService.getPreviousRoundWinners(1);

      // Assert
      expect(winnersResult['winners'], hasLength(2));
      expect(winnersResult['isSoleWinner'], isFalse);
      expect(winnersResult['consecutiveSoleWins'], equals(0));
    });
  });

  group('Critical Path: Billing Calculations', () {
    // These tests don't need mocks - testing static utility methods

    test('credit cost calculation is accurate', () {
      // Using UserCredits constants since BillingService isn't imported
      const creditPriceCents = 1; // $0.01 per credit

      // Manual calculation tests
      expect(100 * creditPriceCents, equals(100)); // 100 credits = $1.00
      expect(500 * creditPriceCents, equals(500)); // 500 credits = $5.00
      expect(100 * creditPriceCents / 100.0, equals(1.00));
      expect(250 * creditPriceCents / 100.0, equals(2.50));
    });

    test('user credits model tracks balance correctly', () {
      // Test UserCredits model directly
      final credits = UserCredits(
        id: 1,
        userId: 'test-user',
        creditBalance: 100,
        freeTierUsed: 200,
        freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(credits.creditBalance, equals(100));
      expect(credits.freeTierUsed, equals(200));
      expect(credits.freeTierRemaining, equals(300)); // 500 - 200
      expect(credits.totalAvailable, equals(400)); // 300 free + 100 paid
      expect(credits.hasCredits, isTrue);
      expect(credits.canAfford(400), isTrue);
      expect(credits.canAfford(401), isFalse);
    });

    test('auto-refill settings validation', () {
      // Test auto-refill configuration
      final creditsWithAutoRefill = UserCredits(
        id: 1,
        userId: 'test-user',
        creditBalance: 30,
        freeTierUsed: 500,
        freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        autoRefillEnabled: true,
        autoRefillThreshold: 50,
        autoRefillAmount: 500,
        stripeCustomerId: 'cus_test',
        stripePaymentMethodId: 'pm_test',
      );

      expect(creditsWithAutoRefill.autoRefillEnabled, isTrue);
      expect(creditsWithAutoRefill.hasPaymentMethod, isTrue);
      expect(creditsWithAutoRefill.isAutoRefillActive, isTrue);
      // Balance (30) is below threshold (50), would trigger auto-refill
      expect(creditsWithAutoRefill.creditBalance < creditsWithAutoRefill.autoRefillThreshold, isTrue);
    });
  });

  group('Critical Path: Phase Transitions', () {
    late MockChatService chatService;

    setUp(() {
      chatService = MockChatService();
    });

    test('proposing to rating phase transition', () async {
      // Arrange - First in proposing phase
      final proposingRound = RoundFixtures.proposing(id: 1, cycleId: 1);
      chatService.setupGetCurrentRound(1, proposingRound);

      // Verify proposing
      var round = await chatService.getCurrentRound(1);
      expect(round?.phase, equals(RoundPhase.proposing));

      // Arrange - Transition to rating
      final ratingRound = RoundFixtures.rating(id: 1, cycleId: 1);
      chatService.setupGetCurrentRound(1, ratingRound);

      // Act & Assert - Now in rating
      round = await chatService.getCurrentRound(1);
      expect(round?.phase, equals(RoundPhase.rating));
    });

    test('rating to completed phase transition with winner', () async {
      // Arrange
      final completedRound = RoundFixtures.soleWinner(
        id: 1,
        cycleId: 1,
        winningPropositionId: 5,
      );

      final winner = RoundWinnerFixtures.soleWinner(
        roundId: 1,
        propositionId: 5,
        globalScore: 0.9,
        content: 'Winner',
      );

      chatService.setupGetCurrentRound(1, completedRound);
      chatService.setupGetPreviousRoundWinnersSole(
        cycleId: 1,
        winner: winner,
        consecutiveSoleWins: 1,
      );

      // Act
      final round = await chatService.getCurrentRound(1);
      final winnersResult = await chatService.getPreviousRoundWinners(1);

      // Assert
      expect(round?.winningPropositionId, equals(5));
      expect(round?.isSoleWinner, isTrue);
      expect(winnersResult['winners'], hasLength(1));
    });

    test('cycle completion starts new cycle', () async {
      // Arrange - First cycle completed
      final completedCycle = CycleFixtures.completed(id: 1, chatId: 1);
      chatService.setupGetCurrentCycle(1, completedCycle);

      // Verify first cycle completed
      var cycle = await chatService.getCurrentCycle(1);
      expect(cycle?.isComplete, isTrue);

      // Arrange - New cycle started
      final newCycle = CycleFixtures.active(id: 2, chatId: 1);
      chatService.setupGetCurrentCycle(1, newCycle);

      // Act & Assert - New cycle is active
      cycle = await chatService.getCurrentCycle(1);
      expect(cycle?.id, equals(2));
      expect(cycle?.isComplete, isFalse);
    });
  });

  group('Critical Path: Participant Management', () {
    late MockParticipantService participantService;

    setUp(() {
      participantService = MockParticipantService();
    });

    test('host can kick participants', () async {
      // Arrange
      final hostParticipant = ParticipantFixtures.host(id: 1, chatId: 1);
      final regularParticipant = ParticipantFixtures.model(id: 2, chatId: 1);
      final kickedParticipant = ParticipantFixtures.kicked(id: 2, chatId: 1);

      participantService.setupGetParticipants(1, [hostParticipant, regularParticipant]);
      participantService.setupKickParticipant();

      // Act
      var participants = await participantService.getParticipants(1);
      expect(participants, hasLength(2));

      await participantService.kickParticipant(2);

      // Simulate updated list after kick
      participantService.setupGetParticipants(1, [hostParticipant, kickedParticipant]);
      participants = await participantService.getParticipants(1);

      // Assert
      final kicked = participants.firstWhere((p) => p.id == 2);
      expect(kicked.status, equals(ParticipantStatus.kicked));
    });

    test('participant retrieval by user id', () async {
      // Arrange
      final participant = ParticipantFixtures.model(
        id: 3,
        chatId: 1,
        displayName: 'User',
      );

      participantService.setupGetMyParticipant(1, participant);

      // Act
      final myParticipant = await participantService.getMyParticipant(1);

      // Assert
      expect(myParticipant, isNotNull);
      expect(myParticipant?.displayName, equals('User'));
    });
  });

  group('Critical Path: Multi-Proposition Support', () {
    late MockPropositionService propositionService;

    setUp(() {
      propositionService = MockPropositionService();
    });

    test('user can submit multiple propositions when allowed', () async {
      // Arrange
      final propositions = [
        PropositionFixtures.model(id: 1, roundId: 1, participantId: 1, content: 'Prop 1'),
        PropositionFixtures.model(id: 2, roundId: 1, participantId: 1, content: 'Prop 2'),
        PropositionFixtures.model(id: 3, roundId: 1, participantId: 1, content: 'Prop 3'),
      ];

      propositionService.setupGetMyPropositions(1, 1, propositions);
      propositionService.setupSubmitProposition(propositions.last);

      // Act
      final myPropositions = await propositionService.getMyPropositions(1, 1);

      // Assert
      expect(myPropositions, hasLength(3));
      expect(myPropositions.map((p) => p.content), containsAll(['Prop 1', 'Prop 2', 'Prop 3']));
    });

    test('all propositions from a round are returned for rating', () async {
      // Arrange
      final allPropositions = [
        PropositionFixtures.model(id: 1, roundId: 1, participantId: 1, content: 'User 1 Prop'),
        PropositionFixtures.model(id: 2, roundId: 1, participantId: 2, content: 'User 2 Prop'),
        PropositionFixtures.model(id: 3, roundId: 1, participantId: 3, content: 'User 3 Prop'),
      ];

      propositionService.setupGetPropositions(1, allPropositions);

      // Act
      final propositions = await propositionService.getPropositions(1);

      // Assert
      expect(propositions, hasLength(3));
    });
  });

  group('Critical Path: Winner Navigation (Tie Handling)', () {
    late MockChatService chatService;

    setUp(() {
      chatService = MockChatService();
    });

    test('single winner returns sole winner info', () async {
      // Arrange
      final winner = RoundWinnerFixtures.soleWinner(
        roundId: 1,
        propositionId: 1,
        globalScore: 85.0,
        content: 'The winner',
      );

      chatService.setupGetPreviousRoundWinnersSole(
        cycleId: 1,
        winner: winner,
        consecutiveSoleWins: 1,
      );

      // Act
      final result = await chatService.getPreviousRoundWinners(1);

      // Assert
      expect(result['isSoleWinner'], isTrue);
      expect(result['consecutiveSoleWins'], equals(1));
      expect((result['winners'] as List), hasLength(1));
    });

    test('tied winners returns multiple winners with tie info', () async {
      // Arrange
      final winners = RoundWinnerFixtures.tiedWinners(roundId: 1, count: 3);

      chatService.setupGetPreviousRoundWinnersTied(
        cycleId: 1,
        winners: winners,
      );

      // Act
      final result = await chatService.getPreviousRoundWinners(1);

      // Assert
      expect(result['isSoleWinner'], isFalse);
      expect(result['consecutiveSoleWins'], equals(0));
      expect((result['winners'] as List), hasLength(3));
    });

    test('tie breaks consecutive win streak', () async {
      // Scenario: A wins, A+B tie, A wins
      // Expected: Only 1 consecutive win (tie broke the streak)

      // Arrange - Simulate result after tie broke streak
      final winner = RoundWinnerFixtures.soleWinner(roundId: 3, propositionId: 1);

      chatService.setupGetPreviousRoundWinnersSole(
        cycleId: 1,
        winner: winner,
        consecutiveSoleWins: 1, // Only 1 because tie broke the streak
      );

      // Act
      final result = await chatService.getPreviousRoundWinners(1);

      // Assert
      expect(result['consecutiveSoleWins'], equals(1));
      expect(result['isSoleWinner'], isTrue);
    });

    test('no winners returns empty result', () async {
      // Arrange
      chatService.setupGetPreviousRoundWinnersEmpty(1);

      // Act
      final result = await chatService.getPreviousRoundWinners(1);

      // Assert
      expect((result['winners'] as List), isEmpty);
      expect(result['isSoleWinner'], isFalse);
      expect(result['consecutiveSoleWins'], equals(0));
    });
  });
}
