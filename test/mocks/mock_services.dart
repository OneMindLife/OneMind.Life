import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/models/chat_dashboard_info.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/services/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mock ChatService for testing
class MockChatService extends Mock implements ChatService {}

/// Mock ParticipantService for testing
class MockParticipantService extends Mock implements ParticipantService {}

/// Mock PropositionService for testing
class MockPropositionService extends Mock implements PropositionService {}

/// Mock AuthService for testing
class MockAuthService extends Mock implements AuthService {}

/// Register fallback values for mocktail
/// Call this in setUpAll() for tests using these mocks
void registerFallbackValues() {
  // Enums
  registerFallbackValue(AccessMethod.code);
  registerFallbackValue(StartMode.manual);
  registerFallbackValue(ParticipantStatus.active);
  registerFallbackValue(RoundPhase.proposing);
  registerFallbackValue(PostgresChangeEvent.all);

  // Realtime
  registerFallbackValue(PostgresChangeFilter(
    type: PostgresChangeFilterType.eq,
    column: 'id',
    value: 1,
  ));
}

/// Extension with common mock setups for ChatService
extension MockChatServiceSetup on MockChatService {
  /// Setup getMyChats to return a list of chats
  void setupGetMyChats(List<Chat> chats) {
    when(() => getMyChats()).thenAnswer((_) async => chats);
  }

  /// Setup getMyDashboard to return a list of dashboard infos
  void setupGetMyDashboard(List<ChatDashboardInfo> dashboardChats) {
    when(() => getMyDashboard(languageCode: any(named: 'languageCode')))
        .thenAnswer((_) async => dashboardChats);
  }

  /// Setup getOfficialChat
  void setupGetOfficialChat(Chat? chat) {
    when(() => getOfficialChat()).thenAnswer((_) async => chat);
  }

  /// Setup getChatByCode
  void setupGetChatByCode(String code, Chat? chat) {
    when(() => getChatByCode(code)).thenAnswer((_) async => chat);
  }

  /// Setup getChatById
  void setupGetChatById(int id, Chat? chat) {
    when(() => getChatById(id)).thenAnswer((_) async => chat);
  }

  /// Setup createChat to return a chat
  void setupCreateChat(Chat chat) {
    when(() => createChat(
          name: any(named: 'name'),
          initialMessage: any(named: 'initialMessage'),
          accessMethod: any(named: 'accessMethod'),
          requireAuth: any(named: 'requireAuth'),
          requireApproval: any(named: 'requireApproval'),
          startMode: any(named: 'startMode'),
          hostDisplayName: any(named: 'hostDisplayName'),
          autoStartParticipantCount: any(named: 'autoStartParticipantCount'),
          proposingDurationSeconds: any(named: 'proposingDurationSeconds'),
          ratingDurationSeconds: any(named: 'ratingDurationSeconds'),
          proposingMinimum: any(named: 'proposingMinimum'),
          ratingMinimum: any(named: 'ratingMinimum'),
          proposingThresholdPercent: any(named: 'proposingThresholdPercent'),
          proposingThresholdCount: any(named: 'proposingThresholdCount'),
          ratingThresholdPercent: any(named: 'ratingThresholdPercent'),
          ratingThresholdCount: any(named: 'ratingThresholdCount'),
          enableAiParticipant: any(named: 'enableAiParticipant'),
          aiPropositionsCount: any(named: 'aiPropositionsCount'),
          confirmationRoundsRequired: any(named: 'confirmationRoundsRequired'),
          showPreviousResults: any(named: 'showPreviousResults'),
          propositionsPerUser: any(named: 'propositionsPerUser'),
        )).thenAnswer((_) async => chat);
  }

  /// Setup getPublicChats
  void setupGetPublicChats(List<PublicChatSummary> chats) {
    when(() => getPublicChats(
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          languageCode: any(named: 'languageCode'),
        )).thenAnswer((_) async => chats);
  }

  /// Setup searchPublicChats
  void setupSearchPublicChats(String query, List<PublicChatSummary> chats) {
    when(() => searchPublicChats(query,
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          languageCode: any(named: 'languageCode'),
        )).thenAnswer((_) async => chats);
  }

  /// Setup getCurrentCycle
  void setupGetCurrentCycle(int chatId, Cycle? cycle) {
    when(() => getCurrentCycle(chatId)).thenAnswer((_) async => cycle);
  }

  /// Setup getCurrentRound
  void setupGetCurrentRound(int cycleId, Round? round) {
    when(() => getCurrentRound(cycleId)).thenAnswer((_) async => round);
  }

  /// Setup getConsensusItems
  void setupGetConsensusItems(int chatId, List<ConsensusItem> items) {
    when(() => getConsensusItems(chatId)).thenAnswer((_) async => items);
  }

  /// Setup getPreviousRoundWinners (supports multiple tied winners)
  void setupGetPreviousRoundWinners({
    required int cycleId,
    required List<RoundWinner> winners,
    required bool isSoleWinner,
    required int consecutiveSoleWins,
    int? previousRoundId,
    int? primaryWinnerId,
  }) {
    when(() => getPreviousRoundWinners(cycleId)).thenAnswer((_) async => {
          'winners': winners,
          'isSoleWinner': isSoleWinner,
          'consecutiveSoleWins': consecutiveSoleWins,
          'previousRoundId': previousRoundId,
          'primaryWinnerId': primaryWinnerId,
        });
  }

  /// Setup getPreviousRoundWinners with no winners
  void setupGetPreviousRoundWinnersEmpty(int cycleId) {
    setupGetPreviousRoundWinners(
      cycleId: cycleId,
      winners: [],
      isSoleWinner: false,
      consecutiveSoleWins: 0,
      previousRoundId: null,
      primaryWinnerId: null,
    );
  }

  /// Setup getPreviousRoundWinners with sole winner
  void setupGetPreviousRoundWinnersSole({
    required int cycleId,
    required RoundWinner winner,
    required int consecutiveSoleWins,
    int? previousRoundId,
  }) {
    setupGetPreviousRoundWinners(
      cycleId: cycleId,
      winners: [winner],
      isSoleWinner: true,
      consecutiveSoleWins: consecutiveSoleWins,
      previousRoundId: previousRoundId,
      primaryWinnerId: winner.propositionId,
    );
  }

  /// Setup getPreviousRoundWinners with tied winners
  void setupGetPreviousRoundWinnersTied({
    required int cycleId,
    required List<RoundWinner> winners,
    int? previousRoundId,
  }) {
    setupGetPreviousRoundWinners(
      cycleId: cycleId,
      winners: winners,
      isSoleWinner: false,
      consecutiveSoleWins: 0,
      previousRoundId: previousRoundId,
      primaryWinnerId: winners.isNotEmpty ? winners.first.propositionId : null,
    );
  }
}

/// Extension with common mock setups for ParticipantService
extension MockParticipantServiceSetup on MockParticipantService {
  /// Setup getParticipants
  void setupGetParticipants(int chatId, List<Participant> participants) {
    when(() => getParticipants(chatId)).thenAnswer((_) async => participants);
  }

  /// Setup getMyParticipant (uses auth.uid() internally)
  void setupGetMyParticipant(int chatId, Participant? participant) {
    when(() => getMyParticipant(chatId)).thenAnswer((_) async => participant);
  }

  /// Setup joinChat (uses auth.uid() internally)
  void setupJoinChat(Participant participant) {
    when(() => joinChat(
          chatId: any(named: 'chatId'),
          displayName: any(named: 'displayName'),
          isHost: any(named: 'isHost'),
        )).thenAnswer((_) async => participant);
  }

  /// Setup requestToJoin
  void setupRequestToJoin(JoinRequest request) {
    when(() => requestToJoin(
          chatId: any(named: 'chatId'),
          displayName: any(named: 'displayName'),
        )).thenAnswer((_) async => request);
  }

  /// Setup getMyPendingRequests
  void setupGetMyPendingRequests(List<JoinRequest> requests) {
    when(() => getMyPendingRequests()).thenAnswer((_) async => requests);
  }

  /// Setup getPendingRequests (for host)
  void setupGetPendingRequests(int chatId, List<Map<String, dynamic>> requests) {
    when(() => getPendingRequests(chatId)).thenAnswer((_) async => requests);
  }

  /// Setup kickParticipant
  void setupKickParticipant() {
    when(() => kickParticipant(any())).thenAnswer((_) async {});
  }

  /// Setup leaveChat
  void setupLeaveChat() {
    when(() => leaveChat(any())).thenAnswer((_) async {});
  }
}

/// Extension with common mock setups for PropositionService
extension MockPropositionServiceSetup on MockPropositionService {
  /// Setup getPropositions
  void setupGetPropositions(int roundId, List<Proposition> propositions) {
    when(() => getPropositions(roundId))
        .thenAnswer((_) async => propositions);
  }

  /// Setup submitProposition
  void setupSubmitProposition(Proposition proposition) {
    when(() => submitProposition(
          roundId: any(named: 'roundId'),
          participantId: any(named: 'participantId'),
          content: any(named: 'content'),
        )).thenAnswer((_) async => proposition);
  }

  /// Setup getMyPropositions (for multiple propositions per user)
  void setupGetMyPropositions(
    int roundId,
    int participantId,
    List<Proposition> propositions,
  ) {
    when(() => getMyPropositions(roundId, participantId))
        .thenAnswer((_) async => propositions);
  }

  /// Setup getRatingProgress
  void setupGetRatingProgress(int roundId, int participantId, bool completed, bool started) {
    when(() => getRatingProgress(roundId, participantId))
        .thenAnswer((_) async => {'completed': completed, 'started': started});
  }

  /// Setup hasRated
  void setupHasRated(int roundId, int participantId, bool hasRated) {
    when(() => this.hasRated(roundId, participantId))
        .thenAnswer((_) async => hasRated);
  }

  /// Setup getUserRoundRanks (for leaderboard display)
  void setupGetUserRoundRanks(List<UserRoundRank> ranks) {
    when(() => getUserRoundRanks(
          roundId: any(named: 'roundId'),
          myParticipantId: any(named: 'myParticipantId'),
        )).thenAnswer((_) async => ranks);
  }

  /// Setup getUserRoundRanks to throw an error
  void setupGetUserRoundRanksError(Exception error) {
    when(() => getUserRoundRanks(
          roundId: any(named: 'roundId'),
          myParticipantId: any(named: 'myParticipantId'),
        )).thenThrow(error);
  }
}

/// Extension with common mock setups for AuthService
extension MockAuthServiceSetup on MockAuthService {
  /// Setup currentUserId
  void setupCurrentUserId(String? userId) {
    when(() => currentUserId).thenReturn(userId);
  }

  /// Setup isSignedIn
  void setupIsSignedIn(bool signedIn) {
    when(() => isSignedIn).thenReturn(signedIn);
  }

  /// Setup displayName
  void setupDisplayName(String? name) {
    when(() => displayName).thenReturn(name);
  }

  /// Setup ensureSignedIn
  void setupEnsureSignedIn(String userId) {
    when(() => ensureSignedIn()).thenAnswer((_) async => userId);
  }

  /// Setup setDisplayName
  void setupSetDisplayName() {
    when(() => setDisplayName(any())).thenAnswer((_) async {});
  }

  /// Setup all common auth mocks with default values
  void setupDefaults({String userId = 'test-user-id', String? displayName}) {
    setupCurrentUserId(userId);
    setupIsSignedIn(true);
    setupDisplayName(displayName);
    setupEnsureSignedIn(userId);
    setupSetDisplayName();
  }
}
