import 'package:equatable/equatable.dart';

/// User's combined ranking for a round, based on voting accuracy and proposition performance.
///
/// The combined rank is calculated as:
/// - If both voting and proposing: (voting_rank + proposing_rank) / 2
/// - If only one: that single value
///
/// Ranks are on a 0-100 scale:
/// - voting_rank: Pairwise comparison accuracy against final MOVDA scores
/// - proposing_rank: Normalized average performance of user's propositions
class UserRoundRank extends Equatable {
  final int id;
  final int roundId;
  final int participantId;
  final double rank; // Combined rank (0-100)
  final double? votingRank; // Nullable if user didn't vote
  final double? proposingRank; // Nullable if user didn't propose
  final DateTime createdAt;

  // Joined data from participants table
  final String? displayName;

  const UserRoundRank({
    required this.id,
    required this.roundId,
    required this.participantId,
    required this.rank,
    this.votingRank,
    this.proposingRank,
    required this.createdAt,
    this.displayName,
  });

  factory UserRoundRank.fromJson(Map<String, dynamic> json) {
    // Handle joined participants data
    String? displayName;
    final participants = json['participants'];
    if (participants != null) {
      if (participants is Map<String, dynamic>) {
        displayName = participants['display_name'] as String?;
      } else if (participants is List && participants.isNotEmpty) {
        displayName = participants[0]['display_name'] as String?;
      }
    }

    return UserRoundRank(
      id: json['id'] as int,
      roundId: json['round_id'] as int,
      participantId: json['participant_id'] as int,
      rank: (json['rank'] as num).toDouble(),
      votingRank: json['voting_rank'] != null
          ? (json['voting_rank'] as num).toDouble()
          : null,
      proposingRank: json['proposing_rank'] != null
          ? (json['proposing_rank'] as num).toDouble()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      displayName: displayName,
    );
  }

  @override
  List<Object?> get props => [
        id,
        roundId,
        participantId,
        rank,
        votingRank,
        proposingRank,
        createdAt,
        displayName,
      ];
}
