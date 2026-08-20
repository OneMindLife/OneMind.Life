import 'chat.dart';
import 'cycle.dart';
import 'round.dart';
import 'consensus_item.dart';
import 'participant.dart';
import 'proposition.dart';
import 'chat_credits.dart';
import 'round_winner.dart';

/// Single-trip snapshot of all chat-detail state. Returned by the
/// `get_chat_detail_bootstrap` RPC. Replaces the 18 parallel queries
/// `ChatDetailNotifier._loadData` used to fire each refresh.
///
/// Field shape mirrors the per-query results so callers can swap-in
/// without touching downstream UI.
class ChatDetailBootstrap {
  final Chat? chat;
  final Cycle? currentCycle;
  final Round? currentRound;
  final List<ConsensusItem> consensusItems;
  final List<Participant> participants;
  final Participant? myParticipant;
  final List<Map<String, dynamic>> pendingJoinRequests;
  final ChatCredits? chatCredits;
  final List<RoundWinner> previousRoundWinners;
  final bool isSoleWinner;
  final int consecutiveSoleWins;
  final int? previousRoundId;
  final int? primaryWinnerId;
  final List<Proposition> previousRoundResults;
  final List<Proposition> propositions;
  final List<Proposition> myPropositions;
  final bool hasRated;
  final bool hasStartedRating;
  final int skipCount;
  final bool hasSkipped;
  final int ratingSkipCount;
  final bool hasSkippedRating;
  final int affirmationCount;
  final bool hasAffirmed;
  final Set<int> participantsWhoRated;
  final Set<int> participantsWhoProposed;
  final Set<int> participantsWhoSkippedProposing;
  final Set<int> participantsWhoSkippedRating;
  final Set<int> participantsWhoAffirmed;
  final int minRatingsPerProp;
  final int myCurrentRoundRatingCount;
  final bool isMyParticipantFunded;
  final List<String> allowedCategories;

  const ChatDetailBootstrap({
    required this.chat,
    required this.currentCycle,
    required this.currentRound,
    required this.consensusItems,
    required this.participants,
    required this.myParticipant,
    required this.pendingJoinRequests,
    required this.chatCredits,
    required this.previousRoundWinners,
    required this.isSoleWinner,
    required this.consecutiveSoleWins,
    required this.previousRoundId,
    required this.primaryWinnerId,
    required this.previousRoundResults,
    required this.propositions,
    required this.myPropositions,
    required this.hasRated,
    required this.hasStartedRating,
    required this.skipCount,
    required this.hasSkipped,
    required this.ratingSkipCount,
    required this.hasSkippedRating,
    required this.affirmationCount,
    required this.hasAffirmed,
    required this.participantsWhoRated,
    required this.participantsWhoProposed,
    required this.participantsWhoSkippedProposing,
    required this.participantsWhoSkippedRating,
    required this.participantsWhoAffirmed,
    required this.minRatingsPerProp,
    required this.myCurrentRoundRatingCount,
    required this.isMyParticipantFunded,
    required this.allowedCategories,
  });

  /// Parse the JSONB returned by `get_chat_detail_bootstrap`.
  factory ChatDetailBootstrap.fromJson(Map<String, dynamic> json) {
    final ratingProgress =
        (json['rating_progress'] as Map?)?.cast<String, dynamic>() ?? const {};

    return ChatDetailBootstrap(
      chat: json['chat'] == null
          ? null
          : Chat.fromJson((json['chat'] as Map).cast<String, dynamic>()),
      currentCycle: json['current_cycle'] == null
          ? null
          : Cycle.fromJson(
              (json['current_cycle'] as Map).cast<String, dynamic>()),
      currentRound: json['current_round'] == null
          ? null
          : Round.fromJson(
              (json['current_round'] as Map).cast<String, dynamic>()),
      consensusItems: ((json['consensus_items'] as List?) ?? const [])
          .map((row) => _parseConsensusItem(
              (row as Map).cast<String, dynamic>()))
          .toList(),
      participants: ((json['participants'] as List?) ?? const [])
          .map((row) => Participant.fromJson(
              (row as Map).cast<String, dynamic>()))
          .toList(),
      myParticipant: json['my_participant'] == null
          ? null
          : Participant.fromJson(
              (json['my_participant'] as Map).cast<String, dynamic>()),
      pendingJoinRequests: ((json['pending_join_requests'] as List?) ??
              const [])
          .map((row) => (row as Map).cast<String, dynamic>())
          .toList(),
      chatCredits: json['chat_credits'] == null
          ? null
          : ChatCredits.fromJson(
              (json['chat_credits'] as Map).cast<String, dynamic>()),
      previousRoundWinners: ((json['previous_round_winners'] as List?) ??
              const [])
          .map((row) => RoundWinner.fromJson(
              (row as Map).cast<String, dynamic>()))
          .toList(),
      isSoleWinner: json['is_sole_winner'] as bool? ?? false,
      consecutiveSoleWins: (json['consecutive_sole_wins'] as num?)?.toInt() ?? 0,
      previousRoundId: (json['previous_round_id'] as num?)?.toInt(),
      primaryWinnerId: (json['primary_winner_id'] as num?)?.toInt(),
      previousRoundResults: ((json['previous_round_results'] as List?) ??
              const [])
          .map((row) => Proposition.fromJson(
              (row as Map).cast<String, dynamic>()))
          .toList(),
      propositions: ((json['propositions'] as List?) ?? const [])
          .map((row) => Proposition.fromJson(
              (row as Map).cast<String, dynamic>()))
          .toList(),
      myPropositions: ((json['my_propositions'] as List?) ?? const [])
          .map((row) => Proposition.fromJson(
              (row as Map).cast<String, dynamic>()))
          .toList(),
      hasRated: ratingProgress['completed'] as bool? ?? false,
      hasStartedRating: ratingProgress['started'] as bool? ?? false,
      skipCount: (json['skip_count'] as num?)?.toInt() ?? 0,
      hasSkipped: json['has_skipped'] as bool? ?? false,
      ratingSkipCount: (json['rating_skip_count'] as num?)?.toInt() ?? 0,
      hasSkippedRating: json['has_skipped_rating'] as bool? ?? false,
      affirmationCount: (json['affirmation_count'] as num?)?.toInt() ?? 0,
      hasAffirmed: json['has_affirmed'] as bool? ?? false,
      participantsWhoRated: _parseIntSet(json['participants_who_rated']),
      participantsWhoProposed:
          _parseIntSet(json['participants_who_proposed']),
      participantsWhoSkippedProposing:
          _parseIntSet(json['participants_who_skipped_proposing']),
      participantsWhoSkippedRating:
          _parseIntSet(json['participants_who_skipped_rating']),
      participantsWhoAffirmed:
          _parseIntSet(json['participants_who_affirmed']),
      minRatingsPerProp: (json['min_ratings_per_prop'] as num?)?.toInt() ?? 0,
      myCurrentRoundRatingCount:
          (json['my_current_round_rating_count'] as num?)?.toInt() ?? 0,
      isMyParticipantFunded:
          json['is_my_participant_funded'] as bool? ?? true,
      allowedCategories: ((json['allowed_categories'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }

  static ConsensusItem _parseConsensusItem(Map<String, dynamic> row) {
    final propRaw = (row['propositions'] as Map).cast<String, dynamic>();
    return ConsensusItem(
      cycleId: row['id'] as int,
      proposition: Proposition.fromJson(propRaw),
      taskResult: row['task_result'] as String?,
      isHostOverride: row['host_override'] as bool? ?? false,
      videoUrl: row['video_url'] as String?,
      audioUrl: row['audio_url'] as String?,
    );
  }

  static Set<int> _parseIntSet(dynamic value) {
    if (value is! List) return <int>{};
    return value.map((e) => (e as num).toInt()).toSet();
  }
}
