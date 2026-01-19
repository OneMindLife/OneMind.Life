import 'package:onemind_app/models/round_winner.dart';

/// Test fixtures for RoundWinner model
class RoundWinnerFixtures {
  /// Fixed date for equality testing
  static final DateTime _fixedDate = DateTime.utc(2024, 1, 1);

  /// Valid JSON matching Supabase response
  static Map<String, dynamic> json({
    int id = 1,
    int roundId = 1,
    int propositionId = 1,
    int rank = 1,
    double? globalScore = 75.0,
    String? content,
    DateTime? createdAt,
  }) {
    final result = <String, dynamic>{
      'id': id,
      'round_id': roundId,
      'proposition_id': propositionId,
      'rank': rank,
      'global_score': globalScore,
      'created_at': (createdAt ?? _fixedDate).toIso8601String(),
    };

    // Include nested proposition if content is provided
    if (content != null) {
      result['propositions'] = {'content': content};
    }

    return result;
  }

  /// Valid RoundWinner model instance
  static RoundWinner model({
    int id = 1,
    int roundId = 1,
    int propositionId = 1,
    int rank = 1,
    double? globalScore = 75.0,
    String? content,
  }) {
    return RoundWinner.fromJson(json(
      id: id,
      roundId: roundId,
      propositionId: propositionId,
      rank: rank,
      globalScore: globalScore,
      content: content,
    ));
  }

  /// Sole winner (single winner for a round)
  static RoundWinner soleWinner({
    int id = 1,
    int roundId = 1,
    int propositionId = 1,
    double globalScore = 85.0,
    String content = 'Winning proposition',
  }) {
    return model(
      id: id,
      roundId: roundId,
      propositionId: propositionId,
      globalScore: globalScore,
      content: content,
    );
  }

  /// List of tied winners for a round
  static List<RoundWinner> tiedWinners({
    int roundId = 1,
    int count = 2,
    double score = 50.0,
  }) {
    return List.generate(count, (i) {
      return model(
        id: i + 1,
        roundId: roundId,
        propositionId: 100 + i,
        rank: 1,
        globalScore: score,
        content: 'Tied proposition ${i + 1}',
      );
    });
  }

  /// JSON list for tied winners (as returned by Supabase)
  static List<Map<String, dynamic>> tiedWinnersJson({
    int roundId = 1,
    int count = 2,
    double score = 50.0,
  }) {
    return List.generate(count, (i) {
      return json(
        id: i + 1,
        roundId: roundId,
        propositionId: 100 + i,
        rank: 1,
        globalScore: score,
        content: 'Tied proposition ${i + 1}',
      );
    });
  }

  /// Three-way tie scenario
  static List<RoundWinner> threeWayTie({int roundId = 1}) {
    return tiedWinners(roundId: roundId, count: 3, score: 33.33);
  }
}
