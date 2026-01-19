import 'package:equatable/equatable.dart';
import '../core/errors/app_exception.dart';

enum RoundPhase { waiting, proposing, rating }

class Round extends Equatable {
  final int id;
  final int cycleId;
  final int customId; // Round number within cycle
  final RoundPhase phase;
  final DateTime? phaseStartedAt;
  final DateTime? phaseEndsAt;
  final int? winningPropositionId;
  final bool? isSoleWinner; // TRUE = counts toward consensus, FALSE = tied (doesn't count)
  final DateTime createdAt;
  final DateTime? completedAt;

  const Round({
    required this.id,
    required this.cycleId,
    required this.customId,
    required this.phase,
    this.phaseStartedAt,
    this.phaseEndsAt,
    this.winningPropositionId,
    this.isSoleWinner,
    required this.createdAt,
    this.completedAt,
  });

  bool get isComplete => completedAt != null;

  Round copyWith({
    int? id,
    int? cycleId,
    int? customId,
    RoundPhase? phase,
    DateTime? phaseStartedAt,
    DateTime? phaseEndsAt,
    int? winningPropositionId,
    bool? isSoleWinner,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return Round(
      id: id ?? this.id,
      cycleId: cycleId ?? this.cycleId,
      customId: customId ?? this.customId,
      phase: phase ?? this.phase,
      phaseStartedAt: phaseStartedAt ?? this.phaseStartedAt,
      phaseEndsAt: phaseEndsAt ?? this.phaseEndsAt,
      winningPropositionId: winningPropositionId ?? this.winningPropositionId,
      isSoleWinner: isSoleWinner ?? this.isSoleWinner,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Duration? get timeRemaining {
    if (phaseEndsAt == null) return null;
    final remaining = phaseEndsAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory Round.fromJson(Map<String, dynamic> json) {
    return Round(
      id: json['id'] as int,
      cycleId: json['cycle_id'] as int,
      customId: json['custom_id'] as int,
      phase: _parsePhase(json['phase'] as String?),
      phaseStartedAt: json['phase_started_at'] != null
          ? DateTime.parse(json['phase_started_at'] as String)
          : null,
      phaseEndsAt: json['phase_ends_at'] != null
          ? DateTime.parse(json['phase_ends_at'] as String)
          : null,
      winningPropositionId: json['winning_proposition_id'] as int?,
      isSoleWinner: json['is_sole_winner'] as bool?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  static RoundPhase _parsePhase(String? phase) {
    switch (phase) {
      case 'proposing':
        return RoundPhase.proposing;
      case 'rating':
        return RoundPhase.rating;
      case 'waiting':
      case null:
        return RoundPhase.waiting; // Default for null or explicit waiting
      default:
        throw AppException.validation(
          message: 'Unknown round phase: $phase',
          field: 'phase',
        );
    }
  }

  @override
  List<Object?> get props => [
        id,
        cycleId,
        customId,
        phase,
        phaseStartedAt,
        phaseEndsAt,
        winningPropositionId,
        isSoleWinner,
        createdAt,
        completedAt,
      ];
}
