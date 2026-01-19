import 'package:onemind_app/models/round.dart';

/// Test fixtures for Round model
class RoundFixtures {
  /// Valid JSON matching Supabase response
  static Map<String, dynamic> json({
    int id = 1,
    int cycleId = 1,
    int customId = 1,
    String phase = 'proposing',
    DateTime? phaseStartedAt,
    DateTime? phaseEndsAt,
    int? winningPropositionId,
    bool? isSoleWinner,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return {
      'id': id,
      'cycle_id': cycleId,
      'custom_id': customId,
      'phase': phase,
      'phase_started_at': phaseStartedAt?.toIso8601String(),
      'phase_ends_at': phaseEndsAt?.toIso8601String(),
      'winning_proposition_id': winningPropositionId,
      'is_sole_winner': isSoleWinner,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  /// Fixed date for equality testing
  static final DateTime _fixedDate = DateTime.utc(2024, 1, 1);

  /// Valid Round model instance
  static Round model({
    int id = 1,
    int cycleId = 1,
    int customId = 1,
    RoundPhase phase = RoundPhase.proposing,
    int? winningPropositionId,
    bool? isSoleWinner,
    DateTime? createdAt,
  }) {
    return Round.fromJson(json(
      id: id,
      cycleId: cycleId,
      customId: customId,
      phase: phase.name,
      winningPropositionId: winningPropositionId,
      isSoleWinner: isSoleWinner,
      createdAt: createdAt ?? _fixedDate,
    ));
  }

  /// Waiting phase round (before phase starts)
  static Round waiting({int id = 1, int cycleId = 1, int customId = 1}) {
    return Round.fromJson(json(
      id: id,
      cycleId: cycleId,
      customId: customId,
      phase: 'waiting',
    ));
  }

  /// Proposing phase round
  static Round proposing({
    int id = 1,
    int cycleId = 1,
    int customId = 1,
    Duration? timeRemaining,
  }) {
    final now = DateTime.now();
    return Round.fromJson(json(
      id: id,
      cycleId: cycleId,
      customId: customId,
      phase: 'proposing',
      phaseStartedAt: now.subtract(const Duration(hours: 1)),
      phaseEndsAt: timeRemaining != null ? now.add(timeRemaining) : null,
    ));
  }

  /// Rating phase round
  static Round rating({
    int id = 1,
    int cycleId = 1,
    int customId = 1,
    Duration? timeRemaining,
  }) {
    final now = DateTime.now();
    return Round.fromJson(json(
      id: id,
      cycleId: cycleId,
      customId: customId,
      phase: 'rating',
      phaseStartedAt: now.subtract(const Duration(hours: 1)),
      phaseEndsAt: timeRemaining != null ? now.add(timeRemaining) : null,
    ));
  }

  /// Completed round with winner
  static Round completed({
    int id = 1,
    int cycleId = 1,
    int customId = 1,
    int winningPropositionId = 1,
    bool isSoleWinner = true,
  }) {
    return Round.fromJson(json(
      id: id,
      cycleId: cycleId,
      customId: customId,
      phase: 'rating',
      winningPropositionId: winningPropositionId,
      isSoleWinner: isSoleWinner,
      completedAt: DateTime.now(),
    ));
  }

  /// Completed round with sole winner (counts toward consensus)
  static Round soleWinner({
    int id = 1,
    int cycleId = 1,
    int customId = 1,
    int winningPropositionId = 1,
  }) {
    return completed(
      id: id,
      cycleId: cycleId,
      customId: customId,
      winningPropositionId: winningPropositionId,
      isSoleWinner: true,
    );
  }

  /// Completed round with tied winners (does NOT count toward consensus)
  static Round tiedWinner({
    int id = 1,
    int cycleId = 1,
    int customId = 1,
    int winningPropositionId = 1,
  }) {
    return completed(
      id: id,
      cycleId: cycleId,
      customId: customId,
      winningPropositionId: winningPropositionId,
      isSoleWinner: false,
    );
  }

  /// Round with timer expired
  static Round timerExpired({int id = 1, int cycleId = 1}) {
    return Round.fromJson(json(
      id: id,
      cycleId: cycleId,
      phase: 'proposing',
      phaseStartedAt: DateTime.now().subtract(const Duration(days: 2)),
      phaseEndsAt: DateTime.now().subtract(const Duration(hours: 1)),
    ));
  }

  /// List of rounds for a cycle
  static List<Round> list({
    int count = 3,
    int cycleId = 1,
    bool includeCompleted = true,
  }) {
    return List.generate(count, (i) {
      final isLast = i == count - 1;
      if (isLast && !includeCompleted) {
        return proposing(id: i + 1, cycleId: cycleId, customId: i + 1);
      }
      return completed(
        id: i + 1,
        cycleId: cycleId,
        customId: i + 1,
        winningPropositionId: i + 1,
      );
    });
  }
}
