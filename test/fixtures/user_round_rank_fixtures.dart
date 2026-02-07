import 'package:onemind_app/models/user_round_rank.dart';

/// Test fixtures for UserRoundRank model
class UserRoundRankFixtures {
  /// Valid JSON matching Supabase response
  static Map<String, dynamic> json({
    int id = 1,
    int roundId = 1,
    int participantId = 1,
    double rank = 75.0,
    double? votingRank = 80.0,
    double? proposingRank = 70.0,
    DateTime? createdAt,
    String? displayName,
  }) {
    return {
      'id': id,
      'round_id': roundId,
      'participant_id': participantId,
      'rank': rank,
      'voting_rank': votingRank,
      'proposing_rank': proposingRank,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      if (displayName != null)
        'participants': {'display_name': displayName},
    };
  }

  /// JSON with participants as a list (PostgREST format)
  static Map<String, dynamic> jsonWithParticipantsList({
    int id = 1,
    int roundId = 1,
    int participantId = 1,
    double rank = 75.0,
    String? displayName,
  }) {
    return {
      'id': id,
      'round_id': roundId,
      'participant_id': participantId,
      'rank': rank,
      'voting_rank': null,
      'proposing_rank': null,
      'created_at': DateTime.now().toIso8601String(),
      'participants': displayName != null
          ? [{'display_name': displayName}]
          : [],
    };
  }

  /// Valid UserRoundRank model instance
  static UserRoundRank model({
    int id = 1,
    int roundId = 1,
    int participantId = 1,
    double rank = 75.0,
    double? votingRank = 80.0,
    double? proposingRank = 70.0,
    String? displayName,
  }) {
    return UserRoundRank.fromJson(json(
      id: id,
      roundId: roundId,
      participantId: participantId,
      rank: rank,
      votingRank: votingRank,
      proposingRank: proposingRank,
      displayName: displayName,
    ));
  }

  /// User who only voted (no propositions)
  static UserRoundRank voterOnly({
    int id = 1,
    int roundId = 1,
    int participantId = 1,
    double votingRank = 85.0,
    String? displayName,
  }) {
    return UserRoundRank.fromJson(json(
      id: id,
      roundId: roundId,
      participantId: participantId,
      rank: votingRank,
      votingRank: votingRank,
      proposingRank: null,
      displayName: displayName,
    ));
  }

  /// User who only proposed (no voting)
  static UserRoundRank proposerOnly({
    int id = 1,
    int roundId = 1,
    int participantId = 1,
    double proposingRank = 90.0,
    String? displayName,
  }) {
    return UserRoundRank.fromJson(json(
      id: id,
      roundId: roundId,
      participantId: participantId,
      rank: proposingRank,
      votingRank: null,
      proposingRank: proposingRank,
      displayName: displayName,
    ));
  }

  /// Winner with high rank
  static UserRoundRank winner({
    int id = 1,
    int roundId = 1,
    int participantId = 1,
    double rank = 95.0,
    String displayName = 'Winner',
  }) {
    return UserRoundRank.fromJson(json(
      id: id,
      roundId: roundId,
      participantId: participantId,
      rank: rank,
      votingRank: 95.0,
      proposingRank: 95.0,
      displayName: displayName,
    ));
  }

  /// List of user round ranks for a round
  static List<UserRoundRank> list({int count = 3, int roundId = 1}) {
    return List.generate(
      count,
      (i) => model(
        id: i + 1,
        roundId: roundId,
        participantId: i + 1,
        rank: 90.0 - (i * 10), // 90, 80, 70...
        votingRank: 90.0 - (i * 10),
        proposingRank: 90.0 - (i * 10),
        displayName: 'User ${i + 1}',
      ),
    );
  }

  /// Diverse user ranks for testing leaderboard display
  static List<UserRoundRank> diverse({int roundId = 1}) {
    return [
      // Current user - middle rank
      model(
        id: 1,
        roundId: roundId,
        participantId: 1,
        rank: 65.0,
        votingRank: 70.0,
        proposingRank: 60.0,
        displayName: 'Current User',
      ),
      // Winner - highest rank
      model(
        id: 2,
        roundId: roundId,
        participantId: 2,
        rank: 92.5,
        votingRank: 95.0,
        proposingRank: 90.0,
        displayName: 'Top Performer',
      ),
      // Voter only
      voterOnly(
        id: 3,
        roundId: roundId,
        participantId: 3,
        votingRank: 55.0,
        displayName: 'Just Voted',
      ),
      // Proposer only
      proposerOnly(
        id: 4,
        roundId: roundId,
        participantId: 4,
        proposingRank: 80.0,
        displayName: 'Just Proposed',
      ),
    ];
  }
}
