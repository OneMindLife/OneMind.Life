/// Utility class for calculating winners from grid rankings.
/// Extracted for testability.
class WinnerCalculator {
  /// Calculate winners from raw grid ranking data.
  ///
  /// Returns a map with:
  /// - `winnerIds`: List of all winning proposition IDs
  /// - `highestScore`: The winning score
  /// - `isSoleWinner`: Whether there's exactly one winner
  static Map<String, dynamic> calculateWinners(
    List<Map<String, dynamic>> rankings,
  ) {
    if (rankings.isEmpty) {
      return {
        'winnerIds': <int>[],
        'highestScore': 0.0,
        'isSoleWinner': false,
      };
    }

    // Calculate average position for each proposition
    final Map<int, List<double>> positionsByProposition = {};
    for (final r in rankings) {
      final propId = r['proposition_id'] as int;
      final position = (r['grid_position'] as num).toDouble();
      positionsByProposition.putIfAbsent(propId, () => []).add(position);
    }

    final Map<int, double> avgPositions = {};
    for (final entry in positionsByProposition.entries) {
      avgPositions[entry.key] =
          entry.value.reduce((a, b) => a + b) / entry.value.length;
    }

    // Find the HIGHEST average position (higher = better, top of screen)
    double highestAvg = -1;
    for (final entry in avgPositions.entries) {
      if (entry.value > highestAvg) {
        highestAvg = entry.value;
      }
    }

    // Find ALL propositions with the highest (best) score (handles ties)
    final List<int> winningPropositionIds = [];
    for (final entry in avgPositions.entries) {
      if (entry.value == highestAvg) {
        winningPropositionIds.add(entry.key);
      }
    }

    return {
      'winnerIds': winningPropositionIds,
      'highestScore': highestAvg,
      'isSoleWinner': winningPropositionIds.length == 1,
    };
  }
}
